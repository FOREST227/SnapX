import SwiftUI

/// Shared appearance for the menu panel and settings window.
enum AppPanelStyle {
    static let width: CGFloat = 320
    static let padding: CGFloat = 18
    static var accent: Color { .accentColor }
    static var selectionFill: Color { accent.opacity(0.07) }
    static var selectionBorder: Color { accent }
    static var warning: Color { Color(nsColor: .systemOrange) }
    static var error: Color { Color(nsColor: .systemRed) }
    // Opaque adaptive text avoids low contrast over the panel's darker gradient end.
    static var secondaryTextColor: NSColor {
        NSColor(name: "SnapXSecondaryText") { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: isDark ? 0.82 : 0.12, alpha: 1)
        }
    }
    static var secondaryText: Color { Color(nsColor: secondaryTextColor) }
    static var success: Color {
        Color(nsColor: NSColor(name: "SnapXSuccess") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0.36, green: 0.85, blue: 0.55, alpha: 1)
                : NSColor(srgbRed: 0.19, green: 0.80, blue: 0.39, alpha: 1)
        })
    }
    static let controlCornerRadius: CGFloat = 6
    static var controlBorder: Color { Color.primary.opacity(0.18) }
    static var controlFill: Color {
        Color(nsColor: NSColor(name: "SnapXControlFill") { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(white: 0.16, alpha: 1)
                : NSColor(srgbRed: 250.0 / 255, green: 251.0 / 255, blue: 253.0 / 255, alpha: 1)
        })
    }
    static var groupFill: Color { Color.primary.opacity(0.05) }
    static func backgroundStart(isDark: Bool) -> NSColor {
        isDark ? NSColor(srgbRed: 0.24, green: 0.25, blue: 0.27, alpha: 1)
            : NSColor(srgbRed: 0.96, green: 0.97, blue: 0.985, alpha: 1)
    }
    static func backgroundEnd(isDark: Bool) -> NSColor {
        isDark ? NSColor(srgbRed: 0.065, green: 0.075, blue: 0.09, alpha: 1)
            : NSColor(srgbRed: 0.77, green: 0.79, blue: 0.82, alpha: 1)
    }
    static var backgroundStartColor: NSColor {
        NSColor(name: "SnapXBackgroundStart") { appearance in
            backgroundStart(isDark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        }
    }
    static var backgroundEndColor: NSColor {
        NSColor(name: "SnapXBackgroundEnd") { appearance in
            backgroundEnd(isDark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        }
    }
    static var background: some View { PanelBackground() }
}

private struct PanelBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            PanelGradient(isDark: true)
            PanelGradient(isDark: false).opacity(scheme == .dark ? 0 : 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: scheme)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PanelGradient: View {
    let isDark: Bool
    var body: some View {
        Canvas { context, size in
            let area = Path(CGRect(origin: .zero, size: size))
            let start = Color(nsColor: AppPanelStyle.backgroundStart(isDark: isDark))
            context.fill(area, with: .color(start))
            context.fill(area, with: .linearGradient(
                Gradient(colors: [start, Color(nsColor: AppPanelStyle.backgroundEnd(isDark: isDark)).opacity(0.95)]),
                startPoint: .zero, endPoint: CGPoint(x: AppPanelStyle.width, y: 720)))
            if !isDark {
                context.fill(area, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.42), location: 0.38),
                        .init(color: .clear, location: 0.72),
                        .init(color: .clear, location: 1)
                    ]), startPoint: CGPoint(x: -100, y: 0), endPoint: CGPoint(x: 360, y: 650)))
            }
        }
    }
}
