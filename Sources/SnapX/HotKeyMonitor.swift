import ApplicationServices
import Carbon.HIToolbox
import Foundation

enum HotKeyRegistrationOutcome {
    case registered
    case requiresAccessibilityPermission
    case failed(OSStatus)
}

struct HotKeyModifiers: OptionSet {
    let rawValue: UInt32

    static let command = HotKeyModifiers(rawValue: UInt32(cmdKey))
    static let option = HotKeyModifiers(rawValue: UInt32(optionKey))
    static let control = HotKeyModifiers(rawValue: UInt32(controlKey))
    static let shift = HotKeyModifiers(rawValue: UInt32(shiftKey))

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}

final class GlobalHotKeyMonitor {
    private static let signature = OSType(0x53424F41)

    private let keyCode: UInt32
    private let modifiers: HotKeyModifiers
    private let handler: @Sendable () -> Void
    private let hotKeyID: EventHotKeyID

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var eventTapToken: UUID?

    init(identifier: UInt32, keyCode: UInt32, modifiers: HotKeyModifiers, handler: @escaping @Sendable () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
        self.hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: identifier
        )
    }

    @discardableResult
    func register() -> HotKeyRegistrationOutcome {
        guard hotKeyRef == nil else { return .registered }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }

                let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                var pressedHotKeyID = EventHotKeyID()

                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedHotKeyID
                )

                guard status == noErr,
                      pressedHotKeyID.signature == monitor.hotKeyID.signature,
                      pressedHotKeyID.id == monitor.hotKeyID.id else {
                    return OSStatus(eventNotHandledErr)
                }

                monitor.handler()

                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else { return .failed(handlerStatus) }

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers.rawValue,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            unregister()
            return .failed(registerStatus)
        }

        guard modifiers.contains(.command) else {
            return .registered
        }

        switch SharedCommandHotKeyEventTap.shared.register(
            keyCode: keyCode,
            modifiers: modifiers,
            handler: handler
        ) {
        case let .started(token):
            eventTapToken = token
            return .registered

        case .requiresAccessibilityPermission:
            return .requiresAccessibilityPermission

        case let .failed(status):
            unregister()
            return .failed(status)
        }
    }

    func unregister() {
        if let eventTapToken {
            SharedCommandHotKeyEventTap.shared.unregister(token: eventTapToken)
            self.eventTapToken = nil
        }

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}

private enum EventTapRegistrationOutcome {
    case started(UUID)
    case requiresAccessibilityPermission
    case failed(OSStatus)
}

/// Multiplexes all Command-based global hotkeys through a single CGEventTap so
/// system-wide keystrokes only cross into SnapX once instead of once per shortcut.
private final class SharedCommandHotKeyEventTap: @unchecked Sendable {
    static let shared = SharedCommandHotKeyEventTap()

    private struct Binding {
        let token: UUID
        let keyCode: UInt32
        let cgEventFlags: CGEventFlags
        let handler: @Sendable () -> Void
    }

    private let lock = NSLock()
    private let relevantFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    private var bindings: [Binding] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    func register(
        keyCode: UInt32,
        modifiers: HotKeyModifiers,
        handler: @escaping @Sendable () -> Void
    ) -> EventTapRegistrationOutcome {
        lock.lock()
        defer { lock.unlock() }

        if eventTap == nil, let failure = startTapLocked() {
            return failure
        }

        let token = UUID()
        bindings.append(Binding(
            token: token,
            keyCode: keyCode,
            cgEventFlags: modifiers.cgEventFlags,
            handler: handler
        ))
        return .started(token)
    }

    func unregister(token: UUID) {
        lock.lock()
        defer { lock.unlock() }

        bindings.removeAll { $0.token == token }
        if bindings.isEmpty {
            stopTapLocked()
        }
    }

    private func startTapLocked() -> EventTapRegistrationOutcome? {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let tap = Unmanaged<SharedCommandHotKeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
            return tap.handleEvent(type: type, event: event)
        }

        guard let createdTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return AXIsProcessTrusted() ? .failed(OSStatus(-1)) : .requiresAccessibilityPermission
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)

        eventTap = createdTap
        runLoopSource = source
        return nil
    }

    private func stopTapLocked() {
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = eventTap
            lock.unlock()
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        // Fast-path: all bindings in this tap require Command, so skip ordinary typing immediately.
        let flags = event.flags
        guard flags.contains(.maskCommand) else {
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.keyboardEventAutorepeat) != 1 else {
            return Unmanaged.passUnretained(event)
        }

        let pressedKeyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let normalizedFlags = flags.intersection(relevantFlags)

        lock.lock()
        let matchedHandler = bindings.first {
            $0.keyCode == pressedKeyCode && $0.cgEventFlags == normalizedFlags
        }?.handler
        lock.unlock()

        guard let matchedHandler else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async {
            matchedHandler()
        }
        return nil
    }
}
