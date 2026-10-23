import AppKit
import SwiftUI

@MainActor
final class RecognizedTextWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void
    private let recognizedText: String

    init(text: String, onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.recognizedText = text

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)
        configureWindow(panel, text: text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        if let parent = window?.parent {
            parent.removeChildWindow(window!)
        }
        onClose()
    }

    func show(relativeTo parentWindow: NSWindow?) {
        guard let window else { return }

        if let parentWindow {
            parentWindow.addChildWindow(window, ordered: .above)
            let origin = CGPoint(
                x: parentWindow.frame.midX - (window.frame.width / 2),
                y: parentWindow.frame.midY - (window.frame.height / 2)
            )
            window.setFrameOrigin(origin)
            parentWindow.makeKey()
        } else {
            window.center()
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureWindow(_ window: NSPanel, text: String) {
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.title = "提取到的文字"
        window.contentMinSize = NSSize(width: 360, height: 280)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.contentView = NSHostingView(rootView: RecognizedTextView(text: text) { [weak self] in
            self?.copyAllText()
        }.ignoresSafeArea(.container, edges: .top))
        ThemeManager.shared.applyTheme(to: window)
    }

    @objc private func copyAllText() {
        ScreenshotEditorFileIO.copyTextToPasteboard(recognizedText)
    }
}
