import AppKit
import XCTest
import SwiftUI
@testable import SnapX

final class TextClickTests: XCTestCase {
    @MainActor func testFirstClickIsDeliveredImmediatelyAndSecondClickIsDouble() throws {
        let view = EditorTextInteractionView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        var clicks: [Bool] = []
        view.onTap = { _, double in clicks.append(double) }
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
        view.mouseDown(with: try event(.leftMouseDown, count: 1))
        view.mouseUp(with: try event(.leftMouseUp, count: 1))
        XCTAssertEqual(clicks, [false], "Single click must be delivered synchronously, without the double-click interval")
        view.mouseDown(with: try event(.leftMouseDown, count: 2))
        view.mouseUp(with: try event(.leftMouseUp, count: 2))
        XCTAssertEqual(clicks, [false, true])
    }
    @MainActor func testRealCanvasClickStartsDraftImmediatelyAndCommitsTypedText() async throws {
        _ = NSApplication.shared
        let image = NSImage(size: CGSize(width: 400, height: 300))
        let model = ScreenshotEditorViewModel(image: image)
        model.activeTool = .text
        let layout = ScreenshotEditorLayout(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            screenSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 20, y: 20, width: 400, height: 300),
            toolbarRect: CGRect(x: 20, y: 480, width: 650, height: 56), displayScale: 1)
        let host = NSHostingView(rootView: ScreenshotEditorRootView(viewModel: model, layout: layout,
            onClose: {}, onDone: {}, onPin: {}, onSave: {}, onExtractText: {}))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        func findCanvas(_ view: NSView) -> EditorTextInteractionView? {
            if let canvas = view as? EditorTextInteractionView { return canvas }
            return view.subviews.lazy.compactMap { findCanvas($0) }.first
        }
        let canvas = try XCTUnwrap(findCanvas(host))
        XCTAssertEqual(canvas.bounds.size, CGSize(width: 400, height: 300))
        let point = canvas.convert(CGPoint(x: 120, y: 90), to: nil)
        canvas.mouseDown(with: try event(.leftMouseDown, count: 1, point: point))
        canvas.mouseUp(with: try event(.leftMouseUp, count: 1, point: point))
        XCTAssertTrue(model.hasActiveTextDraft, "The real root view must begin the draft before mouseUp returns")
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let input = try XCTUnwrap(window.firstResponder as? NSTextView)
        input.insertText("立即输入中文", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(nanoseconds: 30_000_000)
        let finish = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        input.keyDown(with: finish)
        XCTAssertFalse(model.hasActiveTextDraft)
        guard case let .text(annotation) = model.annotations.first else { return XCTFail("Expected committed text") }
        XCTAssertEqual(annotation.text, "立即输入中文")
        XCTAssertEqual(annotation.origin.x, 120, accuracy: 0.1)
        XCTAssertEqual(annotation.origin.y, 90, accuracy: 0.1)
    }

    @MainActor func testDraggingDoesNotAlsoCreateText() throws {
        let view = EditorTextInteractionView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        var taps = 0, drags = 0, finished = 0
        view.onTap = { _, _ in taps += 1 }
        view.onDrag = { _, _ in drags += 1 }
        view.onDragEnd = { finished += 1 }
        view.mouseDown(with: try event(.leftMouseDown, count: 1))
        view.mouseDragged(with: try event(.leftMouseDragged, count: 1, point: CGPoint(x: 80, y: 70)))
        view.mouseUp(with: try event(.leftMouseUp, count: 1, point: CGPoint(x: 80, y: 70)))
        XCTAssertEqual(taps, 0)
        XCTAssertEqual(drags, 1)
        XCTAssertEqual(finished, 1)
    }
    private func event(_ type: NSEvent.EventType, count: Int, point: CGPoint = CGPoint(x: 30, y: 30)) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: count, pressure: 1))
    }
}
