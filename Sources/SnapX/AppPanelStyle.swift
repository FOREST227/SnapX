import SwiftUI

/// Shared appearance for the menu panel and settings window.
enum AppPanelStyle {
    static let width: CGFloat = 320
    static let padding: CGFloat = 18
    static var accent: Color { .accentColor }
    static var selectionFill: Color { accent.opacity(0.07) }
    static var selectionBorder: Color { accent.opacity(0.7) }
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
                : NSColor(srgbRed: 0.04, green: 0.34, blue: 0.15, alpha: 1)
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
    static var background: LinearGradient {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor).opacity(0.95)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
