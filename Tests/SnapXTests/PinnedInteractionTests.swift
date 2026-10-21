import AppKit
import XCTest
@testable import SnapX
final class PinnedInteractionTests: XCTestCase {
    func testEdgesResizeWithoutTranslatingOppositeEdge() {
        let frame = CGRect(x: 100, y: 200, width: 400, height: 240)
        let resized = PinnedResizeEdges([.left, .bottom]).resized(frame, delta: CGSize(width: 50, height: 30), minimum: CGSize(width: 80, height: 60))
        XCTAssertEqual(resized, CGRect(x: 150, y: 230, width: 350, height: 210))
        XCTAssertEqual(resized.maxX, frame.maxX)
        XCTAssertEqual(resized.maxY, frame.maxY)
        let limited = PinnedResizeEdges.left.resized(frame, delta: CGSize(width: 999, height: 0), minimum: CGSize(width: 80, height: 60))
        XCTAssertEqual(limited.width, 80)
        XCTAssertEqual(limited.maxX, frame.maxX)
    }
    func testOnlyFrameEdgesInterceptDragging() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 240)
        XCTAssertTrue(PinnedResizeEdges.hit(at: CGPoint(x: 100, y: 100), in: bounds).isEmpty)
        XCTAssertEqual(PinnedResizeEdges.hit(at: CGPoint(x: 1, y: 1), in: bounds), [.left, .bottom])
        XCTAssertEqual(PinnedResizeEdges.hit(at: CGPoint(x: 399, y: 120), in: bounds), .right)
    }
    @MainActor func testHandleAndOptionDragMoveWindowButPlainImageDragDoesNot() throws {
        _ = NSApplication.shared
        let window = PinnedDragSpyWindow(contentRect: CGRect(x: 100, y: 100, width: 400, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let handle = PinnedDragHandleView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        window.contentView = handle
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 12, y: 12), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        handle.mouseDown(with: down)
        XCTAssertEqual(window.dragCount, 1)
        let canvas = HistoryImageCanvas(frame: CGRect(x: 0, y: 0, width: 400, height: 240))
        canvas.pinnedMode = true
        canvas.setImage(HistoryItem(image: NSImage(size: NSSize(width: 400, height: 240)), date: Date()))
        window.contentView = canvas
        canvas.mouseDown(with: down)
        canvas.mouseUp(with: down)
        XCTAssertEqual(window.dragCount, 1, "Dragging image content must not move the pin, even at minimum zoom")
        let optionDown = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 12, y: 12), modifierFlags: .option, timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: optionDown)
        canvas.mouseUp(with: optionDown)
        XCTAssertEqual(window.dragCount, 2)
        canvas.zoom(by: 2)
        canvas.mouseDown(with: optionDown)
        canvas.mouseUp(with: optionDown)
        XCTAssertEqual(window.dragCount, 3, "Option must move a zoomed pin too")
        canvas.pinnedMode = false
        canvas.mouseDown(with: optionDown)
        canvas.mouseUp(with: optionDown)
        XCTAssertEqual(window.dragCount, 3, "History preview gestures must stay unchanged")
    }

}

private final class PinnedDragSpyWindow: NSWindow {
    var dragCount = 0
    override func performDrag(with event: NSEvent) { dragCount += 1 }
}
