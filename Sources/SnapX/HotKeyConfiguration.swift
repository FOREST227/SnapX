import Carbon.HIToolbox
import Foundation

enum CaptureShortcutAction: String, CaseIterable, Identifiable {
    case framed
    case display
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .framed:
            "框选截图"
        case .display:
            "全屏截图"
        case .history:
            "截图历史"
        }
    }

    var userDefaultsKey: String {
        "capture_shortcut_\(rawValue)"
    }

    var hotKeyIdentifier: UInt32 {
        switch self {
        case .framed:
            1
        case .display:
            2
        case .history:
            3
        }
    }

    var defaultConfiguration: HotKeyConfiguration {
        switch self {
        case .framed:
            HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_S), modifiers: [.command, .shift])
        case .display:
            HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_F), modifiers: [.command, .shift])
        case .history:
            HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_H), modifiers: [.command, .shift])
        }
    }

    var legacyDefaultConfiguration: HotKeyConfiguration {
        switch self {
        case .framed:
            HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_S), modifiers: [.control, .option])
        case .display:
            HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_F), modifiers: [.control, .option])
        case .history:
            HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_H), modifiers: [.control, .option])
        }
    }
}

struct HotKeyConfiguration: Codable, Equatable {
    var keyCode: UInt32
    var modifiersRawValue: UInt32

    init(keyCode: UInt32, modifiers: HotKeyModifiers) {
        self.keyCode = keyCode
        self.modifiersRawValue = modifiers.rawValue
    }

    var modifiers: HotKeyModifiers {
        HotKeyModifiers(rawValue: modifiersRawValue)
    }

    var displayString: String {
        "\(modifiers.symbolString)\(HotKeyKey.label(for: keyCode))"
    }
}

enum HotKeyConfigurationError: LocalizedError {
    case registrationFailed(status: OSStatus)
    case missingModifiers
    case unsupportedKey
    case duplicateShortcut(actionTitle: String)

    var errorDescription: String? {
        switch self {
        case let .registrationFailed(status):
            "这个组合键无法注册，可能已被系统或其他应用占用（错误代码：\(status)）。请换一个组合键，原设置已保留。"
        case .missingModifiers:
            "快捷键至少需要包含一个修饰键（⌘ / ⌥ / ⌃ / ⇧）。"
        case .unsupportedKey:
            "这个按键无法用作快捷键，请换一个按键。"
        case let .duplicateShortcut(actionTitle):
            "这个快捷键已经被“\(actionTitle)”使用了。"
        }
    }
}

/// 可作为快捷键主按键的虚拟按键标签（不含纯修饰键和媒体键）。
enum HotKeyKey {
    static func label(for keyCode: UInt32) -> String {
        labels[keyCode] ?? "?"
    }

    static func isSupported(keyCode: UInt32) -> Bool {
        labels[keyCode] != nil
    }

    private static let labels: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Help): "Help",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13",
        UInt32(kVK_F14): "F14",
        UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17",
        UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19",
        UInt32(kVK_F20): "F20",
        UInt32(kVK_ISO_Section): "§",
        UInt32(kVK_JIS_Yen): "¥",
        UInt32(kVK_JIS_Underscore): "_",
        UInt32(kVK_JIS_KeypadComma): ",",
        UInt32(kVK_JIS_Eisu): "英数",
        UInt32(kVK_JIS_Kana): "かな",
    ]
}

extension HotKeyModifiers {
    var symbolString: String {
        var symbols = ""
        if contains(.control) { symbols += "⌃" }
        if contains(.option) { symbols += "⌥" }
        if contains(.shift) { symbols += "⇧" }
        if contains(.command) { symbols += "⌘" }
        return symbols
    }
}
