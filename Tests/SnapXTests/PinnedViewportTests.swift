import AppKit
import XCTest
@testable import SnapX

final class PinnedViewportTests: XCTestCase {
    @MainActor func testZoomPreservesWindowFrameAndCloseHasSingleOwner() async throws {
        _ = NSApplication.shared
        let image = NSImage(size: NSSize(width: 400, height: 240))
        var closed = 0
        let controller = PinnedScreenshotWindowController(image: image, onClose: { _ in closed += 1 })
        let window = try XCTUnwrap(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()
        let original = window.frame
        func findCanvas(_ view: NSView) -> HistoryImageCanvas? {
            if let canvas = view as? HistoryImageCanvas { return canvas }
            return view.subviews.lazy.compactMap { findCanvas($0) }.first
        }
        let canvas = try XCTUnwrap(findCanvas(XCTUnwrap(window.contentView)))
        let originalScale = canvas.scale
        XCTAssertFalse(window.styleMask.contains(.titled), "Pinned images should not have detached title-bar controls")
        XCTAssertLessThanOrEqual(original.width - image.size.width, 4, "Chrome should be only a thin border")
        XCTAssertLessThanOrEqual(original.height - image.size.height, 4)
        controller.zoomIn()
        XCTAssertGreaterThan(canvas.scale, originalScale)
        let scroll = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line,
            wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0))
        let beforeScroll = canvas.scale
        canvas.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: scroll)))
        XCTAssertGreaterThan(canvas.scale, beforeScroll)
        XCTAssertEqual(window.frame, original)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(window.frame, original)
        controller.zoomOut()
        controller.resetZoom()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(window.frame, original)
        XCTAssertTrue(canvas.fitted)
        controller.setWindowOpacity(0.8)
        XCTAssertEqual(window.alphaValue, 0.8, accuracy: 0.001)
        controller.setMousePassthrough(true)
        XCTAssertTrue(window.ignoresMouseEvents)
        controller.setMousePassthrough(false)
        XCTAssertFalse(window.ignoresMouseEvents)
        controller.close()
        XCTAssertEqual(closed, 1)
    }
    @MainActor func testPinnedMinimumFillsViewportAndTrackpadScrollDoesNotZoom() throws {
        let canvas = HistoryImageCanvas(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        canvas.pinnedMode = true
        canvas.setImage(HistoryItem(image: NSImage(size: NSSize(width: 400, height: 240)), date: Date()))
        let minimum = canvas.scale
        canvas.zoom(by: 0.1)
        XCTAssertEqual(canvas.scale, minimum, accuracy: 0.001)
        XCTAssertTrue(canvas.fitted)
        canvas.zoom(by: 2)
        let enlarged = canvas.scale
        canvas.scrollWheel(with: PinnedTestTrackpadScrollEvent())
        XCTAssertEqual(canvas.scale, enlarged)
        canvas.scrollWheel(with: PinnedTestTrackpadMomentumEvent())
        XCTAssertEqual(canvas.scale, enlarged)
        canvas.magnify(with: PinnedTestMagnifyEvent())
        XCTAssertGreaterThan(canvas.scale, enlarged)
        canvas.setFrameSize(NSSize(width: 1200, height: 240))
        XCTAssertGreaterThanOrEqual(canvas.scale, minimum * 3)
        canvas.actualSize()
        XCTAssertGreaterThanOrEqual(canvas.scale, minimum * 3)
    }

    @MainActor func testHighResolutionMouseWheelZoomsWithoutCommandInBothViewers() {
        for pinned in [false, true] {
            let canvas = HistoryImageCanvas(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
            canvas.pinnedMode = pinned
            canvas.setImage(HistoryItem(image: NSImage(size: NSSize(width: 400, height: 240)), date: Date()))
            let before = canvas.scale
            canvas.scrollWheel(with: PinnedTestPrecisionMouseEvent())
            XCTAssertGreaterThan(canvas.scale, before, "High-resolution wheel events without gesture phases are mouse zoom, with no modifier required")
        }
    }

    @MainActor func testMinimumZoomKeepsViewedPositionUntilExplicitFit() {
        let canvas = HistoryImageCanvas(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        canvas.pinnedMode = true
        canvas.setImage(HistoryItem(image: NSImage(size: NSSize(width: 400, height: 200)), date: Date()))
        canvas.zoom(by: 2)
        canvas.scrollWheel(with: PinnedTestHorizontalPanEvent())
        XCTAssertEqual(canvas.pan.x, -40, accuracy: 0.001)
        canvas.zoom(by: 0.5)
        XCTAssertTrue(canvas.fitted)
        XCTAssertEqual(canvas.pan.x, -20, accuracy: 0.001, "Reaching the minimum must preserve the viewed image point")
        canvas.setFrameSize(canvas.frame.size)
        XCTAssertEqual(canvas.pan.x, -20, accuracy: 0.001)
        canvas.setFrameSize(NSSize(width: 160, height: 200))
        XCTAssertEqual(canvas.pan.x, -20, accuracy: 0.001)
        canvas.actualSize()
        XCTAssertEqual(canvas.pan.x, -20, accuracy: 0.001)
        canvas.fit()
        XCTAssertEqual(canvas.pan, .zero)
    }

}

private final class PinnedTestMagnifyEvent: NSEvent {
    override var magnification: CGFloat { 0.25 }
    override var locationInWindow: NSPoint { NSPoint(x: 200, y: 120) }
}

private class PinnedTestPrecisionMouseEvent: NSEvent {
    override var hasPreciseScrollingDeltas: Bool { true }
    override var scrollingDeltaX: CGFloat { 0 }
    override var scrollingDeltaY: CGFloat { 3 }
    override var phase: NSEvent.Phase { [] }
    override var momentumPhase: NSEvent.Phase { [] }
    override var modifierFlags: NSEvent.ModifierFlags { [] }
    override var locationInWindow: NSPoint { NSPoint(x: 200, y: 120) }
}
private final class PinnedTestTrackpadScrollEvent: PinnedTestPrecisionMouseEvent {
    override var phase: NSEvent.Phase { .changed }
}
private final class PinnedTestTrackpadMomentumEvent: PinnedTestPrecisionMouseEvent {
    override var momentumPhase: NSEvent.Phase { .changed }
}

private final class PinnedTestHorizontalPanEvent: PinnedTestPrecisionMouseEvent {
    override var phase: NSEvent.Phase { .changed }
    override var scrollingDeltaX: CGFloat { 40 }
    override var scrollingDeltaY: CGFloat { 0 }
}
