import AppKit
import SwiftUI
import XCTest
@testable import SnapX

private final class TextEditCounter: NSObject, NSTextStorageDelegate {
    var fullAttributeEdits = 0
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        if editedMask.contains(.editedAttributes), editedRange.location == 0,
           editedRange.length >= textStorage.length, textStorage.length > 0 {
            fullAttributeEdits += 1
        }
    }
}

final class TextInputPerformanceTests: XCTestCase {
    @MainActor func testUnchangedRefreshDoesNotRestyleWholeDocument() async throws {
        _ = NSApplication.shared
        var value = String(repeating: "截图文字，连续输入体验。\n", count: 30)
        var revision = ""
        func editor(_ tag: String) -> InlineTextEditor {
            InlineTextEditor(text: Binding(get: { value }, set: { value = $0 }),
                fontSize: 24, fontWeight: .regular, isItalic: false, isUnderline: false,
                textColor: .black, focused: true, onCommit: { revision = tag }, onEscape: {})
        }
        let host = NSHostingView(rootView: editor("initial"))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let input = try XCTUnwrap(window.firstResponder as? NSTextView)
        let storage = try XCTUnwrap(input.textStorage)
        let counter = TextEditCounter()
        let previousDelegate = storage.delegate
        storage.delegate = counter
        defer { storage.delegate = previousDelegate }
        let began = Date()
        for index in 0..<20 {
            host.rootView = editor("revision-\(index)")
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        print("TEXT_REFRESH: \(counter.fullAttributeEdits) full-document restyles over 20 refreshes; \(Int(Date().timeIntervalSince(began) * 1000)) ms including UI scheduling")
        XCTAssertEqual(counter.fullAttributeEdits, 0, "Unchanged styles must not invalidate layout for every character")
        let finish = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        input.keyDown(with: finish)
        XCTAssertEqual(revision, "revision-19")
    }
}
