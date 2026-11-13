import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init()

        configureStatusItem()
        configurePopover()
        NotificationCenter.default.addObserver(self, selector: #selector(applyPopoverTheme),
            name: ThemeManager.themeChangedNotification, object: nil)


        appState.dismissStatusPanel = { [weak self] in
            self?.closePopover()
        }
    }

    func tearDown() {
        NotificationCenter.default.removeObserver(self)
        appState.dismissStatusPanel = nil
        closePopover()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        ThemeManager.shared.preserveSystemAppearance(for: button.window)

        let image = Self.makeStatusIcon()
        image.isTemplate = true
        image.accessibilityDescription = "SnapX"

        button.image = image
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "SnapX"
    }

    /// Template glyph matching the app icon: four viewfinder corner brackets
    /// around an X. Drawn rather than an SF Symbol so the status item is
    /// recognizable among other camera/viewfinder icons.
    private static func makeStatusIcon() -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()

            let inset: CGFloat = 2.25
            let arm: CGFloat = 4.25
            let brackets = NSBezierPath()
            brackets.lineWidth = 1.5
            brackets.lineCapStyle = .round
            for (cornerX, cornerY) in [(inset, 18 - inset), (18 - inset, 18 - inset),
                                       (inset, inset), (18 - inset, inset)] {
                let sx: CGFloat = cornerX < 9 ? 1 : -1
                let sy: CGFloat = cornerY < 9 ? 1 : -1
                brackets.move(to: CGPoint(x: cornerX + arm * sx, y: cornerY))
                brackets.line(to: CGPoint(x: cornerX, y: cornerY))
                brackets.line(to: CGPoint(x: cornerX, y: cornerY + arm * sy))
            }
            brackets.stroke()

            let cross = NSBezierPath()
            cross.lineWidth = 1.7
            cross.lineCapStyle = .round
            cross.move(to: CGPoint(x: 6.4, y: 11.6))
            cross.line(to: CGPoint(x: 11.6, y: 6.4))
            cross.move(to: CGPoint(x: 11.6, y: 11.6))
            cross.line(to: CGPoint(x: 6.4, y: 6.4))
            cross.stroke()
            return true
        }
    }

    private func configurePopover() {
        let hostingController = NSHostingController(rootView: MenuBarContentView(appState: appState, animatesEntrance: true))
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = CGSize(width: AppPanelStyle.width, height: 430)
        applyPopoverTheme()
    }

    @objc private func applyPopoverTheme() {
        popover.appearance = ThemeManager.shared.currentTheme.nsAppearance
        ThemeManager.shared.applyTheme(to: popover.contentViewController?.view.window)
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }

        appState.refreshPermissionStates()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        applyPopoverTheme()
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }
}
