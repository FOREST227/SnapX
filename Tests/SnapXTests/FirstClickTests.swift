import AppKit
import XCTest
@testable import SnapX

final class FirstClickTests: XCTestCase {
    @MainActor
    func testSelectionAcceptsFirstActivationClick() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        var captures = 0
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let bounds = CGRect(x: screen.frame.minX, y: desktopTop - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height)
        let highlightedWindow: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: 987654),
            kCGWindowBounds as String: bounds.dictionaryRepresentation,
            kCGWindowOwnerPID as String: NSNumber(value: 999999),
            kCGWindowOwnerName as String: "Highlighted test window",
        ]
        let controller = SelectionOverlayWindowController(screen: screen, mode: .framed,
            hotKeyHint: "⌥S", frozenImage: nil, frozenWindowInfo: [highlightedWindow],
            captureHandler: { request in
                captures += 1
                guard case let .window(selection) = request else { return XCTFail("Expected highlighted window") }
                XCTAssertEqual(selection.windowID, 987654)
            }, cancelHandler: {})
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        let canvas = try XCTUnwrap(window.contentView)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertTrue(canvas.acceptsFirstMouse(for: nil), "An activation click must also reach selection handling")
        let point = CGPoint(x: screen.frame.width / 2, y: screen.frame.height / 2)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0))
        canvas.mouseDown(with: down)
        canvas.mouseUp(with: up)
        XCTAssertEqual(captures, 1)
    }

    @MainActor
    func testEditorAcceptsFirstActivationClick() throws {
        let controller = ScreenshotEditorWindowController(
            image: NSImage(size: NSSize(width: 100, height: 100)), sourceRect: nil,
            onPin: { _ in }, onCopy: { _ in }, onClose: {})
        defer { controller.close() }
        let surface = try XCTUnwrap(controller.window?.contentView)
        let content = try XCTUnwrap(surface.hitTest(CGPoint(x: surface.bounds.midX, y: surface.bounds.midY)))
        XCTAssertTrue(content.acceptsFirstMouse(for: nil), "The first editor click must not only activate the window")
    }
}
