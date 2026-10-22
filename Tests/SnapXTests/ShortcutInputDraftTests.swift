import Carbon.HIToolbox
import XCTest
@testable import SnapX

final class ShortcutInputDraftTests: XCTestCase {
    func testRejectedPlainKeyStaysVisibleWithoutChangingSavedShortcut() {
        let saved = CaptureShortcutAction.framed.defaultConfiguration
        let candidate = HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_S), modifiers: [])
        var draft = ShortcutInputDraft()
        XCTAssertThrowsError(try draft.submit(candidate) { _ in throw HotKeyConfigurationError.missingModifiers })
        XCTAssertEqual(draft.displayed(over: saved).displayString, "S")
        XCTAssertEqual(draft.attempted, candidate)
        draft.cancel()
        XCTAssertEqual(draft.displayed(over: saved), saved)
    }

    func testSuccessfulRetryShowsNewSavedConfiguration() throws {
        var saved = CaptureShortcutAction.framed.defaultConfiguration
        var draft = ShortcutInputDraft()
        let rejected = HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_S), modifiers: [])
        XCTAssertThrowsError(try draft.submit(rejected) { _ in throw HotKeyConfigurationError.missingModifiers })
        let valid = HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_S), modifiers: [.option])
        try draft.submit(valid) { saved = $0 }
        XCTAssertNil(draft.attempted)
        XCTAssertEqual(draft.displayed(over: saved), valid)
    }
}
