import SwiftUI
import QuartzCore

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    static let themeChangedNotification = Notification.Name("ThemeManager.themeChanged")

    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: Self.themeKey)
            applyTheme(animated: oldValue != currentTheme)
            NotificationCenter.default.post(name: Self.themeChangedNotification, object: nil)
        }
    }

    private static let themeKey = "app_theme"

    private init() {
        let savedTheme = UserDefaults.standard.string(forKey: Self.themeKey) ?? "system"
        currentTheme = AppTheme(rawValue: savedTheme) ?? .system
        applyTheme()
    }

    private var transitionOverlays: [ObjectIdentifier: NSView] = [:]
    private let systemAppearanceWindows = NSHashTable<NSWindow>.weakObjects()

    func preserveSystemAppearance(for window: NSWindow?) {
        if let window { systemAppearanceWindows.add(window) }
    }

    private func applyTheme(animated: Bool = false) {
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // AppKit owns the status item appearance to match the system menu bar.
        let windows = NSApp.windows.filter { !systemAppearanceWindows.contains($0) }
        // Snapshot only visible UI windows. Capture before changing NSAppearance,
        // since native controls and semantic colors otherwise switch instantly.
        var snapshots: [(NSView, NSImageView)] = []
        for window in windows {
            let key = ObjectIdentifier(window)
            let previous = transitionOverlays.removeValue(forKey: key)
            if animate, let previous {
                // Continue from the currently visible blend on rapid clicks.
                let visibleAlpha = previous.layer?.presentation()?.opacity ?? Float(previous.alphaValue)
                previous.layer?.removeAllAnimations()
                previous.alphaValue = CGFloat(visibleAlpha)
            }
            defer { previous?.removeFromSuperview() }
            guard animate, window.isVisible, window.level.rawValue < NSWindow.Level.screenSaver.rawValue,
                  let content = window.contentView, content.bounds.width > 1, content.bounds.height > 1,
                  let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { continue }
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let image = NSImage(size: content.bounds.size)
            image.addRepresentation(bitmap)
            let overlay = ThemeTransitionOverlay(frame: content.bounds)
            overlay.image = image
            overlay.imageScaling = .scaleAxesIndependently
            overlay.autoresizingMask = [.width, .height]
            overlay.wantsLayer = true
            snapshots.append((content, overlay))
            transitionOverlays[key] = overlay
        }
        let appearance = currentTheme.nsAppearance

        NSApp.appearance = appearance

        for window in windows {
            window.appearance = appearance
            window.contentView?.appearance = appearance
        }
        for (content, overlay) in snapshots {
            content.addSubview(overlay, positioned: .above, relativeTo: nil)
            // Let SwiftUI render the new palette underneath before fading the old one.
            DispatchQueue.main.async { [weak self, weak overlay, weak content] in
                guard let overlay, let content, overlay.superview === content else { return }
                content.layoutSubtreeIfNeeded()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                    overlay.animator().alphaValue = 0
                } completionHandler: { [weak self, weak overlay] in
                    Task { @MainActor in
                        guard let overlay else { return }
                        overlay.removeFromSuperview()
                        if let key = self?.transitionOverlays.first(where: { $0.value === overlay })?.key {
                            self?.transitionOverlays.removeValue(forKey: key)
                        }
                    }
                }
            }
        }
    }

    func applyTheme(to window: NSWindow?) {
        guard let window = window, !systemAppearanceWindows.contains(window) else { return }

        if let appearance = currentTheme.nsAppearance {
            window.appearance = appearance
            window.contentView?.appearance = appearance
        } else {
            window.appearance = nil
            window.contentView?.appearance = nil
        }
    }
}

/// The fading snapshot must never consume clicks or keyboard focus.
private final class ThemeTransitionOverlay: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
}
