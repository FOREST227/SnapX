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
                : NSColor(srgbRed: 0.16, green: 0.76, blue: 0.35, alpha: 1)
        })
    }
    static let controlCornerRadius: CGFloat = 6
    static var controlBorder: Color { Color.primary.opacity(0.18) }
    static var controlFill: Color {
        Color(nsColor: NSColor(name: "SnapXControlFill") { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: isDark ? 0.16 : 0.93, alpha: 1)
        })
    }
    static var groupFill: Color { Color.primary.opacity(0.05) }
    static var backgroundStartColor: NSColor {
        NSColor(name: "SnapXBackgroundStart") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0.24, green: 0.25, blue: 0.27, alpha: 1)
                : .windowBackgroundColor
        }
    }
    static var backgroundEndColor: NSColor {
        NSColor(name: "SnapXBackgroundEnd") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0.065, green: 0.075, blue: 0.09, alpha: 1)
                : .underPageBackgroundColor
        }
    }
    static var background: some View {
        Canvas { context, size in
            let area = Path(CGRect(origin: .zero, size: size))
            let start = Color(nsColor: backgroundStartColor)
            // Use an opaque shared base so different window materials cannot
            // change the appearance of the translucent gradient endpoint.
            context.fill(area, with: .color(start))
            context.fill(area, with: .linearGradient(
                Gradient(colors: [start, Color(nsColor: backgroundEndColor).opacity(0.95)]),
                startPoint: .zero,
                endPoint: CGPoint(x: width, y: 720)
            ))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
