import AppKit
import Carbon.HIToolbox
import XCTest
@testable import SnapX

final class HotKeyTests: XCTestCase {
    func testAllRegisteredActionsReceiveTheirOwnEvents() throws {
        let received = Counter()
        let monitors = (1...3).map { id in
            GlobalHotKeyMonitor(identifier: UInt32(id), keyCode: id == 1 ? UInt32(kVK_ANSI_S) : UInt32(kVK_F17 + id),
                                modifiers: id == 1 ? [.option] : [.control, .option, .shift]) {
                received.append(id)
            }
        }
        defer { monitors.forEach { $0.unregister() } }
        for monitor in monitors {
            guard case .registered = monitor.register() else {
                return XCTFail("Test shortcut could not register")
            }
        }
        for id in 1...3 {
            var eventRef: EventRef?
            XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                       0, 0, &eventRef), noErr)
            let event = try XCTUnwrap(eventRef)
            defer { ReleaseEvent(event) }
            var hotKeyID = EventHotKeyID(signature: 0x53424F41, id: UInt32(id))
            XCTAssertEqual(SetEventParameter(event, EventParamName(kEventParamDirectObject),
                                            EventParamType(typeEventHotKeyID),
                                            MemoryLayout<EventHotKeyID>.size, &hotKeyID), noErr)
            XCTAssertEqual(SendEventToEventTarget(event, GetApplicationEventTarget()), noErr)
        }
        XCTAssertEqual(received.values, [1, 2, 3])
    }
    @MainActor
    func testModifiedEscapeIsRecordedRatherThanCancelled() throws {
        let recorder = ShortcutRecorder()
        var captured: UInt32?
        recorder.onCapture = { keyCode, _ in captured = keyCode }
        recorder.start()
        defer { recorder.stop() }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.control, .option], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: UInt16(kVK_Escape)))
        recorder.handle(event)
        XCTAssertEqual(captured, UInt32(kVK_Escape))
        XCTAssertTrue(recorder.isRecording)
    }

    @MainActor
    func testLosingFocusCancelsRecording() {
        let recorder = ShortcutRecorder()
        var cancelled = false
        recorder.onCancel = { cancelled = true }
        recorder.start()
        defer { recorder.stop() }
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertTrue(cancelled)
    }

    @MainActor
    func testOptionSUsesPhysicalKeyEvenWhenItProducesSpecialCharacter() throws {
        let recorder = ShortcutRecorder()
        var captured: HotKeyConfiguration?
        recorder.onCapture = { captured = HotKeyConfiguration(keyCode: $0, modifiers: $1) }
        recorder.start()
        defer { recorder.stop() }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.option], timestamp: 0, windowNumber: 0,
            context: nil, characters: "ß", charactersIgnoringModifiers: "s",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_S)))
        recorder.handle(event)
        XCTAssertEqual(captured, HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_S), modifiers: [.option]))
    }

    @MainActor
    func testRegistrationConflictDoesNotSaveOrChangeShortcut() throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let key = CaptureShortcutAction.framed.userDefaultsKey
        let saved = defaults.object(forKey: key)
        defer {
            if let saved { defaults.set(saved, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        let blocker = GlobalHotKeyMonitor(identifier: 99, keyCode: UInt32(kVK_F16),
                                         modifiers: [.control, .option, .shift]) {}
        guard case .registered = blocker.register() else { return XCTFail("Cannot reserve test shortcut") }
        defer { blocker.unregister() }
        let state = AppState()
        state.setHotKeyRecordingActive(true)
        defer { state.tearDown() }
        let original = state.framedHotKeyConfiguration
        let originalData = defaults.data(forKey: key)
        // The old implementation displays a modal error instead of throwing to the recorder.
        DispatchQueue.main.async { NSApp.abortModal() }
        XCTAssertThrowsError(try state.updateHotKey(for: .framed,
            configuration: HotKeyConfiguration(keyCode: UInt32(kVK_F16), modifiers: [.control, .option, .shift])))
        XCTAssertEqual(state.framedHotKeyConfiguration, original)
        XCTAssertEqual(defaults.data(forKey: key), originalData)
    }

    @MainActor
    func testRecordingOptionSSavesAndRestoresGlobalRegistration() throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let actions = CaptureShortcutAction.allCases
        let saved = actions.map { defaults.object(forKey: $0.userDefaultsKey) }
        defer {
            for (action, value) in zip(actions, saved) {
                if let value { defaults.set(value, forKey: action.userDefaultsKey) }
                else { defaults.removeObject(forKey: action.userDefaultsKey) }
            }
        }
        for (action, keyCode) in zip(actions, [kVK_F15, kVK_F18, kVK_F19]) {
            let configuration = HotKeyConfiguration(keyCode: UInt32(keyCode), modifiers: [.control, .option, .shift])
            defaults.set(try JSONEncoder().encode(configuration), forKey: action.userDefaultsKey)
        }
        let state = AppState()
        defer { state.tearDown() }
        state.setHotKeyRecordingActive(false)
        let recorder = ShortcutRecorder()
        defer { recorder.stop() }
        recorder.onRecordingChanged = { state.setHotKeyRecordingActive($0) }
        recorder.onCapture = { keyCode, modifiers in
            do {
                try state.updateHotKey(for: .framed,
                    configuration: HotKeyConfiguration(keyCode: keyCode, modifiers: modifiers))
                recorder.stop()
            } catch { XCTFail("Recording failed: \(error)") }
        }
        recorder.start()
        let releasedShortcut = GlobalHotKeyMonitor(identifier: 99, keyCode: UInt32(kVK_F15),
                                                  modifiers: [.control, .option, .shift]) {}
        defer { releasedShortcut.unregister() }
        guard case .registered = releasedShortcut.register() else {
            return XCTFail("Existing shortcut was not suspended for recording")
        }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.option], timestamp: 0, windowNumber: 0,
            context: nil, characters: "ß", charactersIgnoringModifiers: "s",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_S)))
        recorder.handle(event)
        XCTAssertFalse(recorder.isRecording)
        let expected = HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_S), modifiers: [.option])
        XCTAssertEqual(state.framedHotKeyConfiguration, expected)
        let data = try XCTUnwrap(defaults.data(forKey: CaptureShortcutAction.framed.userDefaultsKey))
        XCTAssertEqual(try JSONDecoder().decode(HotKeyConfiguration.self, from: data), expected)
        let competingShortcut = GlobalHotKeyMonitor(identifier: 100, keyCode: UInt32(kVK_ANSI_S), modifiers: [.option]) {}
        defer { competingShortcut.unregister() }
        guard case .failed = competingShortcut.register() else {
            return XCTFail("Option+S was not registered after recording completed")
        }
    }

}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []
    func append(_ value: Int) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
    var values: [Int] { lock.lock(); defer { lock.unlock() }; return storage }
}
