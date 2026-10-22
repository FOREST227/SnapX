import Foundation

/// An attempted shortcut may be displayed without changing the active registration.
struct ShortcutInputDraft {
    private(set) var attempted: HotKeyConfiguration?

    func displayed(over saved: HotKeyConfiguration) -> HotKeyConfiguration {
        attempted ?? saved
    }

    mutating func submit(_ candidate: HotKeyConfiguration,
                         save: (HotKeyConfiguration) throws -> Void) throws {
        attempted = candidate
        try save(candidate)
        attempted = nil
    }

    mutating func cancel() { attempted = nil }
}
