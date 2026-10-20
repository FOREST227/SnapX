import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(appState: AppState) {
        let hostingView = NSHostingView(rootView: SettingsView(appState: appState))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: AppPanelStyle.width, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        window.title = "SnapX 设置"
        window.titlebarAppearsTransparent = false
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
            let height = max(window.contentLayoutRect.height, 600)
            window.setContentSize(CGSize(width: AppPanelStyle.width, height: height))
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
