import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(appState: AppState) {
        let hostingView = NSHostingView(rootView: SettingsView(appState: appState, windowControlsInset: 36)
            .ignoresSafeArea(.container, edges: .top))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: AppPanelStyle.width, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        window.title = "SnapX 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.contentMinSize = CGSize(width: AppPanelStyle.width, height: 600)
        window.contentMaxSize = CGSize(width: AppPanelStyle.width, height: .greatestFiniteMagnitude)
        window.center()
        window.contentView = hostingView
        window.delegate = self
        window.setFrameAutosaveName("SnapXSettingsWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        if let window {
            let height = max(window.contentView?.bounds.height ?? 800, 600)
            window.setContentSize(CGSize(width: AppPanelStyle.width, height: height))
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowDragView { SettingsWindowDragView() }
    func updateNSView(_ view: SettingsWindowDragView, context: Context) {}
}

final class SettingsWindowDragView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
