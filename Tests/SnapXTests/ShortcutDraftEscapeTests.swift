import AppKit
import Carbon.HIToolbox
import XCTest
@testable import SnapX

final class ShortcutDraftEscapeTests: XCTestCase {
    @MainActor func testEscapeCancelsInvalidInputWithoutButtonFocusOnlyInOwningWindow() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        let other = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; other.isReleasedWhenClosed = false
        defer { window.close(); other.close() }
        let handler = ShortcutDraftEscapeView()
        window.contentView = handler
        defer { handler.removeMonitor() }
        let saved = CaptureShortcutAction.framed.defaultConfiguration
        var draft = ShortcutInputDraft()
        var message = "缺少修饰键"
        XCTAssertThrowsError(try draft.submit(HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_S), modifiers: [])) { _ in
            throw HotKeyConfigurationError.missingModifiers
        })
        handler.configure(enabled: true) { draft.cancel(); message = "" }
        func key(_ code: Int, in owner: NSWindow, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: owner.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code)))
        }
        XCTAssertNotNil(handler.handle(try key(kVK_Escape, in: other)))
        XCTAssertNotNil(handler.handle(try key(kVK_Escape, in: window, flags: .command)))
        XCTAssertNotNil(handler.handle(try key(kVK_ANSI_A, in: window)))
        XCTAssertEqual(draft.displayed(over: saved).displayString, "S")
        let recorder = ShortcutRecorder()
        recorder.start()
        XCTAssertNotNil(handler.handle(try key(kVK_Escape, in: window)), "An active recorder has priority over older error drafts")
        recorder.stop()
        XCTAssertNil(handler.handle(try key(kVK_Escape, in: window)))
        XCTAssertEqual(draft.displayed(over: saved), saved)
        XCTAssertTrue(message.isEmpty)
        XCTAssertNotNil(handler.handle(try key(kVK_Escape, in: window)), "Cancellation must disarm the handler immediately")
    }
}
