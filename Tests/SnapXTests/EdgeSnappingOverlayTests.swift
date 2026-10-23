import AppKit
import XCTest
@testable import SnapX

final class EdgeSnappingOverlayTests: XCTestCase {
    @MainActor func testDisabledModeStaysManualAndOptionBypassesEnabledSnapping() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let image = try frame(size: screen.frame.size)
        for enabled in [false, true] {
            var captured: ScreenshotCaptureRequest?
            let controller = SelectionOverlayWindowController(screen: screen, mode: .framed, hotKeyHint: "⌥S",
                frozenImage: image, frozenWindowInfo: [], isEdgeSnappingEnabled: enabled,
                captureHandler: { captured = $0 }, cancelHandler: {})
            defer { controller.close() }
            let canvas = try XCTUnwrap(controller.window?.contentView as? SelectionOverlayCanvasView)
            let start = CGPoint(x: 43, y: 77), end = CGPoint(x: 556, y: 224)
            canvas.mouseDown(with: try event(.leftMouseDown, at: start, canvas: canvas))
            canvas.mouseDragged(with: try event(.leftMouseDragged, at: end, canvas: canvas))
            if enabled {
                for _ in 0..<100 {
                    if canvas.snapResult?.edges.count == 4 { break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                XCTAssertEqual(canvas.snapResult?.edges.count, 4)
                canvas.flagsChanged(with: try keyEvent(modifiers: .option))
                XCTAssertEqual(canvas.snapResult?.rect, CGRect(x: 43, y: 77, width: 513, height: 147))
                canvas.flagsChanged(with: try keyEvent(modifiers: []))
                XCTAssertEqual(canvas.snapResult?.edges.count, 4)
            }
            let preview = canvas.snapResult?.rect
            canvas.mouseUp(with: try event(.leftMouseUp, at: end, canvas: canvas))
            guard case let .area(selection) = captured else { return XCTFail("Expected area capture") }
            XCTAssertEqual(selection.rect, preview, "The confirmed crop must match the shown selection")
            controller.freeze(image)
            XCTAssertEqual(canvas.snapResult?.rect, preview, "The transition overlay must not jump back to the raw rectangle")
            if !enabled { XCTAssertEqual(selection.rect, CGRect(x: 43, y: 77, width: 513, height: 147)) }
        }
    }

    @MainActor func testHoverPreviewsStartingAnchorAndSmallDragKeepsIt() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let controller = SelectionOverlayWindowController(screen: screen, mode: .framed, hotKeyHint: "⌥S",
            frozenImage: try frame(size: screen.frame.size), frozenWindowInfo: [], isEdgeSnappingEnabled: true,
            captureHandler: { _ in }, cancelHandler: {})
        defer { controller.close() }
        let canvas = try XCTUnwrap(controller.window?.contentView as? SelectionOverlayCanvasView)
        let start = CGPoint(x: 43, y: 77)
        canvas.mouseMoved(with: try event(.mouseMoved, at: start, canvas: canvas))
        for _ in 0..<100 {
            if canvas.anchorPreviewPoint != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let preview = try XCTUnwrap(canvas.anchorPreviewPoint)
        XCTAssertEqual(preview.x, 40, accuracy: 1)
        XCTAssertEqual(preview.y, 80, accuracy: 1)
        canvas.mouseDown(with: try event(.leftMouseDown, at: start, canvas: canvas))
        canvas.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 55, y: 100), canvas: canvas))
        let initialOrigin = try XCTUnwrap(canvas.snapResult?.rect.origin)
        // Large 1x displays downsample; keep the full border including sample uncertainty.
        XCTAssertEqual(initialOrigin.x, 40, accuracy: 3)
        XCTAssertEqual(initialOrigin.y, 80, accuracy: 3)
        XCTAssertLessThanOrEqual(initialOrigin.x, 40)
        XCTAssertLessThanOrEqual(initialOrigin.y, 80)
        canvas.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 557, y: 398), canvas: canvas))
        XCTAssertEqual(canvas.snapResult?.rect.origin, initialOrigin)
        canvas.flagsChanged(with: try keyEvent(modifiers: .option))
        XCTAssertNil(canvas.anchorPreviewPoint)
        XCTAssertEqual(canvas.snapResult?.rect.origin, start)
    }

    @MainActor func testOptionHeldOnReleaseUsesRawCoordinates() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        var captured: ScreenshotCaptureRequest?
        let controller = SelectionOverlayWindowController(screen: screen, mode: .framed, hotKeyHint: "⌥S",
            frozenImage: try frame(size: screen.frame.size), frozenWindowInfo: [], isEdgeSnappingEnabled: true,
            captureHandler: { captured = $0 }, cancelHandler: {})
        defer { controller.close() }
        let canvas = try XCTUnwrap(controller.window?.contentView as? SelectionOverlayCanvasView)
        // Reverse dragging must work too.
        canvas.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 556, y: 224), canvas: canvas))
        canvas.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 43, y: 77), canvas: canvas))
        for _ in 0..<100 {
            if canvas.snapResult?.edges.count == 4 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(canvas.snapResult?.edges.count, 4)
        canvas.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 43, y: 77), canvas: canvas, modifiers: .option))
        guard case let .area(selection) = captured else { return XCTFail("Expected area") }
        XCTAssertEqual(selection.rect, CGRect(x: 43, y: 77, width: 513, height: 147))
    }

    @MainActor func testStoppingAnalysisRejectsLateResults() async throws {
        let analysis = EdgeSnapAnalysis()
        var updates = 0
        analysis.onUpdate = { updates += 1 }
        analysis.start(size: CGSize(width: 640, height: 400), continuous: true, image: { nil })
        analysis.stop()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(analysis.map)
        XCTAssertEqual(updates, 0)
    }

    @MainActor func testLiveAnalysisRefreshesAndHandlesUnavailableFrames() async throws {
        let analysis = EdgeSnapAnalysis()
        var updates = 0
        analysis.onUpdate = { updates += 1 }
        analysis.start(size: CGSize(width: 640, height: 400), continuous: true, image: { nil })
        for _ in 0..<30 {
            if updates >= 2 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertGreaterThanOrEqual(updates, 2)
        XCTAssertNil(analysis.map)
        XCTAssertFalse(analysis.isAnalyzing, "Unavailable snapshots must not leave an endless loading indicator")
        analysis.stop()
        let count = updates
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(updates, count)
    }

    @MainActor func testExperimentDefaultsOffAndPersistsExplicitChoice() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "experimentalEdgeSnapping")
        defer {
            if let previous { defaults.set(previous, forKey: "experimentalEdgeSnapping") }
            else { defaults.removeObject(forKey: "experimentalEdgeSnapping") }
        }
        defaults.removeObject(forKey: "experimentalEdgeSnapping")
        let state = AppState()
        XCTAssertFalse(state.isEdgeSnappingEnabled)
        state.isEdgeSnappingEnabled = true
        XCTAssertTrue(AppState().isEdgeSnappingEnabled)
        state.isEdgeSnappingEnabled = false
        XCTAssertFalse(AppState().isEdgeSnappingEnabled)
    }

    @MainActor private func event(_ type: NSEvent.EventType, at point: CGPoint, canvas: NSView,
                                  modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: modifiers,
            timestamp: 0, windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 1,
            clickCount: 1, pressure: 1))
    }
    private func keyEvent(modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 58))
    }
    private func frame(size: CGSize) throws -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            if ((x == 40 || x == 560) && (80...220).contains(y)) || ((y == 80 || y == 220) && (40...560).contains(x)) {
                let i = (y * w + x) * 4
                bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0
            }
        } }
        return try XCTUnwrap(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData)), decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
