import AppKit
import SwiftUI
import XCTest
@testable import SnapX

final class TextInputTests: XCTestCase {
    @MainActor
    func testNativeEditorReceivesInputAndUsesUpdatedCommitCallback() async throws {
        _ = NSApplication.shared
        var text = ""
        var committed = ""
        func editor(_ revision: String) -> InlineTextEditor {
            InlineTextEditor(text: Binding(get: { text }, set: { text = $0 }),
                fontSize: 24, fontWeight: .regular, isItalic: false, isUnderline: false,
                textColor: .black, focused: true, onCommit: { committed = revision }, onEscape: { committed = revision })
        }
        let host = NSHostingView(rootView: editor("old"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let input = try XCTUnwrap(window.firstResponder as? NSTextView)
        input.insertText("截图文字123", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(text, "截图文字123")
        host.rootView = editor("new")
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(input.delegate?.textView?(input, doCommandBy: #selector(NSResponder.insertNewline(_:))), false)
        input.insertNewline(nil)
        XCTAssertTrue(text.contains("\n"), "Return inserts a newline")
        input.delegate?.textDidEndEditing?(Notification(name: NSText.didEndEditingNotification, object: input))
        XCTAssertEqual(committed, "", "Style-control focus must not finish editing")
        let finish = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        input.keyDown(with: finish)
        XCTAssertEqual(committed, "new")
        committed = ""
        _ = input.delegate?.textView?(input, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(committed, "new", "Callbacks must follow the current SwiftUI draft")
        input.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        host.rootView = editor("composition")
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(input.hasMarkedText(), "A SwiftUI refresh must preserve input-method composition")
    }
    @MainActor
    func testWrappingGrowsEditorAndStyleChangesPreserveSelection() async throws {
        _ = NSApplication.shared
        var text = String(repeating: "多行文字测试", count: 8)
        var height: CGFloat = 0
        func editor(underline: Bool) -> InlineTextEditor {
            InlineTextEditor(text: Binding(get: { text }, set: { text = $0 }),
                fontSize: 24, fontWeight: .regular, isItalic: false, isUnderline: underline,
                textColor: .black, focused: true, onCommit: {}, onEscape: {},
                onHeightChange: { height = $0 })
        }
        let host = NSHostingView(rootView: editor(underline: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let input = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertGreaterThan(height, 100, "Wrapped text must grow beyond a single line")
        XCTAssertEqual(input.textContainer?.containerSize.width ?? 0, 180, accuracy: 1)
        input.setSelectedRange(NSRange(location: 2, length: 3))
        host.rootView = editor(underline: false)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(input.selectedRange(), NSRange(location: 2, length: 3))
        XCTAssertNil(input.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil))
    }

}
