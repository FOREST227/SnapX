import AppKit
import XCTest
@testable import SnapX

final class FrozenCaptureTests: XCTestCase {
    @MainActor
    func testFailedFreezeNeverFallsBackToLiveCapture() {
        var captureCount = 0
        let coordinator = CaptureCoordinator(captureDisplayImage: { _ in captureCount += 1; return nil })
        coordinator.captureTimingMode = .freezeFirst
        XCTAssertFalse(coordinator.prepareCapture(displayIDs: [1]))
        XCTAssertNil(coordinator.imageForCapture(request: .display(ScreenSelection(
            displayID: 1, rect: CGRect(x: 0, y: 0, width: 10, height: 10), scaleFactor: 1))))
        XCTAssertEqual(captureCount, 1)
    }

    @MainActor
    func testPartialFreezeAbortsInsteadOfShowingAnUnfrozenScreen() throws {
        let frame = try makeFrame(red: 1, blue: 0)
        let coordinator = CaptureCoordinator(captureDisplayImage: { id in id == 1 ? frame : nil })
        coordinator.captureTimingMode = .freezeFirst
        XCTAssertFalse(coordinator.prepareCapture(displayIDs: [1, 2]))
    }

    @MainActor
    func testConfirmationKeepsOriginalFrameAfterDesktopChanges() throws {
        let original = try makeFrame(red: 1, blue: 0)
        let later = try makeFrame(red: 0, blue: 1)
        var desktop = original
        var captureCount = 0
        let coordinator = CaptureCoordinator(captureDisplayImage: { _ in
            captureCount += 1
            return desktop
        })
        coordinator.captureTimingMode = .freezeFirst
        XCTAssertTrue(coordinator.prepareCapture(displayIDs: [1]))
        desktop = later
        let request = ScreenshotCaptureRequest.area(ScreenSelection(
            displayID: 1, rect: CGRect(x: 2, y: 2, width: 4, height: 4), scaleFactor: 1))
        let result = try XCTUnwrap(coordinator.imageForCapture(request: request))
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(result.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        let color = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.9)
        XCTAssertLessThan(color.blueComponent, 0.1)
        XCTAssertEqual(captureCount, 1)
    }

    @MainActor
    func testClickStillSelectsFrozenWindowAfterItDisappearsFromDesktop() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let bounds = CGRect(x: screen.frame.minX, y: desktopTop - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height)
        let info: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: 987654),
            kCGWindowBounds as String: bounds.dictionaryRepresentation,
            kCGWindowOwnerPID as String: NSNumber(value: 999999),
            kCGWindowOwnerName as String: "Vanished test window",
        ]
        var captured: ScreenshotCaptureRequest?
        let controller = SelectionOverlayWindowController(screen: screen, mode: .framed,
            hotKeyHint: "⌥S", frozenImage: try makeFrame(red: 1, blue: 0), frozenWindowInfo: [info],
            captureHandler: { captured = $0 }, cancelHandler: {})
        defer { controller.close() }
        let view = try XCTUnwrap(controller.window?.contentView)
        let point = CGPoint(x: screen.frame.width / 2, y: screen.frame.height / 2)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        view.mouseDown(with: down)
        view.mouseUp(with: up)
        guard case let .window(selection) = captured else { return XCTFail("Frozen window was lost") }
        XCTAssertEqual(selection.windowID, 987654)
        XCTAssertEqual(selection.bounds, bounds)
    }

    @MainActor
    func testLiveModeWaitsUntilConfirmationToCapture() throws {
        var captures = 0
        let frame = try makeFrame(red: 1, blue: 0)
        let coordinator = CaptureCoordinator(captureDisplayImage: { _ in captures += 1; return frame })
        coordinator.captureTimingMode = .liveSelect
        XCTAssertTrue(coordinator.prepareCapture(displayIDs: [1]))
        XCTAssertEqual(captures, 0)
        XCTAssertNotNil(coordinator.imageForCapture(request: .display(ScreenSelection(
            displayID: 1, rect: CGRect(x: 0, y: 0, width: 10, height: 10), scaleFactor: 1))))
        XCTAssertEqual(captures, 1)
    }

    @MainActor
    func testLiveConfirmationFreezesOneFrameForSelectionAndRecrop() throws {
        let red = try makeFrame(red: 1, blue: 0)
        let blue = try makeFrame(red: 0, blue: 1)
        var desktop = red
        var reads = 0
        let coordinator = CaptureCoordinator(captureDisplayImage: { _ in
            reads += 1
            return desktop
        })
        coordinator.captureTimingMode = .liveSelect
        XCTAssertTrue(coordinator.prepareCapture(displayIDs: [1]))
        XCTAssertEqual(reads, 0)
        let request = ScreenshotCaptureRequest.area(ScreenSelection(
            displayID: 1, rect: CGRect(x: 2, y: 2, width: 4, height: 4), scaleFactor: 1))
        let result = try XCTUnwrap(coordinator.imageForCapture(request: request))
        desktop = blue
        let fullFrame = try XCTUnwrap(coordinator.resolveFullScreenImage(displayID: 1).image)
        let model = ScreenshotEditorViewModel(image: result, cropInfo: ScreenshotEditorCropInfo(
            fullScreenImage: fullFrame, selectionRect: CGRect(x: 2, y: 2, width: 4, height: 4),
            displayID: 1, scaleFactor: 1))
        model.recrop(newRect: CGRect(x: 0, y: 0, width: 6, height: 6))
        let recropped = try XCTUnwrap(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let recropColor = try XCTUnwrap(NSBitmapImageRep(cgImage: recropped).colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(recropColor.redComponent, 0.9)
        XCTAssertLessThan(recropColor.blueComponent, 0.1)
        XCTAssertEqual(model.image.size, NSSize(width: 6, height: 6))
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(result.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        let color = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.9)
        XCTAssertLessThan(color.blueComponent, 0.1)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(result.size, NSSize(width: 4, height: 4))
    }

    @MainActor
    func testConfirmationExcludesOverlayWithoutReadingCompositedScreen() throws {
        let frame = try makeFrame(red: 1, blue: 0)
        var capturedReferences: [CGWindowID] = []
        let coordinator = CaptureCoordinator(captureDisplayImage: { _ in
            XCTFail("Capturing the display directly would include the selection overlay"); return nil
        }, captureBelowWindow: { displayID, windowID in
            XCTAssertEqual(displayID, 1)
            capturedReferences.append(windowID)
            return frame
        })
        coordinator.captureTimingMode = .liveSelect
        XCTAssertTrue(coordinator.prepareCapture(displayIDs: [1]))
        XCTAssertTrue(coordinator.freezeDisplays([1], belowWindows: [1: 88]))
        let image = try XCTUnwrap(coordinator.imageForCapture(request: .area(ScreenSelection(
            displayID: 1, rect: CGRect(x: 1, y: 1, width: 4, height: 4), scaleFactor: 1))))
        XCTAssertEqual(image.size, NSSize(width: 4, height: 4))
        XCTAssertEqual(capturedReferences, [88])
    }

    @MainActor
    func testPartlyOffscreenWindowKeepsVisibleCropSize() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let displayBounds = CGDisplayBounds(screen.displayID)
        let scale = screen.backingScaleFactor
        let context = try XCTUnwrap(CGContext(data: nil,
            width: Int(displayBounds.width * scale), height: Int(displayBounds.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let frame = try XCTUnwrap(context.makeImage())
        let window = WindowCaptureSelection(windowID: 987654,
            bounds: CGRect(x: displayBounds.maxX - 20, y: displayBounds.minY + 50, width: 40, height: 30),
            ownerName: "Partly offscreen", windowName: nil)
        let result = try XCTUnwrap(ScreenshotCapturer.cropFromFrozen(request: .window(window),
            frozenImages: [screen.displayID: frame]))
        XCTAssertEqual(result.size, CGSize(width: 20, height: 30), "Clipped pixels must not be stretched to the original window size")
    }

    func testWindowGeometryOnUpperAndAdjacentDisplays() throws {
        let window = WindowCaptureSelection(windowID: 1, bounds: CGRect(x: 900, y: -200, width: 200, height: 100),
            ownerName: "Window", windowName: nil)
        let left = try XCTUnwrap(window.screenSelection(displayID: 1,
            displayBounds: CGRect(x: 0, y: -1000, width: 1000, height: 1000), scaleFactor: 2))
        let right = try XCTUnwrap(window.screenSelection(displayID: 2,
            displayBounds: CGRect(x: 1000, y: -1000, width: 1000, height: 1000), scaleFactor: 1))
        XCTAssertEqual(left.rect, CGRect(x: 900, y: 800, width: 100, height: 100))
        XCTAssertEqual(right.rect, CGRect(x: 0, y: 800, width: 100, height: 100))
        XCTAssertEqual(left.scaleFactor, 2)
        XCTAssertEqual(right.scaleFactor, 1)
        XCTAssertNil(window.clipped(to: CGRect(x: 0, y: 0, width: 1000, height: 1000)))
    }

    private func makeFrame(red: CGFloat, blue: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8,
            bytesPerRow: 40, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: red, green: 0, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        return try XCTUnwrap(context.makeImage())
    }
}
