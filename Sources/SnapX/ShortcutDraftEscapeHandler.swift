import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutDraftEscapeHandler: NSViewRepresentable {
    let enabled: Bool
    let onCancel: () -> Void
    func makeNSView(context: Context) -> ShortcutDraftEscapeView { ShortcutDraftEscapeView() }
    func updateNSView(_ view: ShortcutDraftEscapeView, context: Context) {
        view.configure(enabled: enabled, onCancel: onCancel)
    }
    static func dismantleNSView(_ view: ShortcutDraftEscapeView, coordinator: ()) { view.removeMonitor() }
}

final class ShortcutDraftEscapeView: NSView {
    private var enabled = false
    private var onCancel: (() -> Void)?
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func configure(enabled: Bool, onCancel: @escaping () -> Void) {
        self.enabled = enabled
        self.onCancel = onCancel
        updateMonitor()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateMonitor() }
    private func updateMonitor() {
        guard enabled, window != nil else { removeMonitor(); return }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }
    func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    func handle(_ event: NSEvent) -> NSEvent? {
        guard enabled, !ShortcutRecorder.isAnyRecording, let window,
              (event.window ?? NSApp.keyWindow) === window,
              event.type == .keyDown, !event.isARepeat,
              event.keyCode == UInt16(kVK_Escape),
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return event }
        enabled = false
        removeMonitor()
        onCancel?()
        return nil
    }
}
