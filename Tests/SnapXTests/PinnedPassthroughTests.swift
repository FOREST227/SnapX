import AppKit
import XCTest
@testable import SnapX

final class PinnedPassthroughTests: XCTestCase {
    @MainActor func testPinDoubleClickTogglesAndFloatingHandleMovesClickThroughWindow() async throws {
        _ = NSApplication.shared
        let controller = PinnedScreenshotWindowController(image: NSImage(size: NSSize(width: 400, height: 240)), onClose: { _ in })
        defer { controller.close() }
        controller.showWindow(nil)
        let window = try XCTUnwrap(controller.window)
        // Production placement follows the pointer. Keep this geometry test away
        // from the menu bar, where AppKit constrains upward moves on CI displays.
        let visibleFrame = try XCTUnwrap(window.screen ?? NSScreen.main).visibleFrame
        window.setFrameOrigin(CGPoint(x: visibleFrame.midX - window.frame.width / 2,
                                      y: visibleFrame.midY - window.frame.height / 2))
        window.contentView?.layoutSubtreeIfNeeded()
        func findHandle(_ view: NSView) -> PinnedDragHandleView? {
            if let handle = view as? PinnedDragHandleView { return handle }
            return view.subviews.lazy.compactMap { findHandle($0) }.first
        }
        func event(_ type: NSEvent.EventType, window: NSWindow, point: CGPoint, count: Int = 1) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: count, pressure: 1))
        }
        let normalHandle = try XCTUnwrap(findHandle(XCTUnwrap(window.contentView)))
        normalHandle.mouseDown(with: try event(.leftMouseDown, window: window, point: .zero, count: 2))
        XCTAssertTrue(controller.isMousePassthroughEnabled)
        XCTAssertTrue(window.ignoresMouseEvents)
        let floatingWindow = try XCTUnwrap(window.childWindows?.first)
        let floatingHandle = try XCTUnwrap(findHandle(XCTUnwrap(floatingWindow.contentView)))
        XCTAssertFalse(floatingWindow.ignoresMouseEvents)
        XCTAssertTrue(floatingWindow.isVisible)
        XCTAssertTrue(floatingHandle.passthroughActive)
        XCTAssertEqual(floatingWindow.frame.size, NSSize(width: 30, height: 30))
        let original = window.frame
        floatingHandle.mouseDown(with: try event(.leftMouseDown, window: floatingWindow, point: CGPoint(x: 15, y: 15)))
        floatingHandle.mouseDragged(with: try event(.leftMouseDragged, window: floatingWindow, point: CGPoint(x: 25, y: 35)))
        floatingHandle.mouseUp(with: try event(.leftMouseUp, window: floatingWindow, point: CGPoint(x: 25, y: 35)))
        XCTAssertEqual(window.frame.origin.x, original.minX + 10, accuracy: 0.5)
        XCTAssertEqual(window.frame.origin.y, original.minY + 20, accuracy: 0.5)
        XCTAssertEqual(window.frame.size, original.size)
        XCTAssertTrue(window.ignoresMouseEvents)
        floatingHandle.mouseDown(with: try event(.leftMouseDown, window: floatingWindow, point: CGPoint(x: 15, y: 15), count: 2))
        XCTAssertFalse(controller.isMousePassthroughEnabled)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertFalse(floatingWindow.isVisible)
        XCTAssertNil(floatingWindow.parent)
        controller.setMousePassthrough(true)
        controller.close()
        XCTAssertFalse(floatingWindow.isVisible)
        XCTAssertNil(floatingWindow.parent)
    }
    @MainActor func testGlobalDefaultBeforeShowAndPerPinIndependence() {
        _ = NSApplication.shared
        let first = PinnedScreenshotWindowController(image: NSImage(size: NSSize(width: 400, height: 240)), onClose: { _ in })
        let second = PinnedScreenshotWindowController(image: NSImage(size: NSSize(width: 400, height: 240)), onClose: { _ in })
        defer { first.close(); second.close() }
        first.setMousePassthrough(true)
        second.setMousePassthrough(true)
        XCTAssertFalse(first.window?.childWindows?.first?.isVisible ?? false)
        first.showWindow(nil)
        XCTAssertTrue(first.window?.childWindows?.first?.isVisible == true)
        first.toggleMousePassthrough()
        XCTAssertFalse(first.isMousePassthroughEnabled)
        XCTAssertTrue(second.isMousePassthroughEnabled)
    }

}
