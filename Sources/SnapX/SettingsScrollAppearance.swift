import AppKit
import SwiftUI

/// Configure only the settings scroll view, without changing the system preference.
struct SettingsScrollAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsScrollAppearanceView { SettingsScrollAppearanceView() }
    func updateNSView(_ view: SettingsScrollAppearanceView, context: Context) { view.configureScroller() }
}

final class SettingsScrollAppearanceView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureScroller()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureScroller()
        DispatchQueue.main.async { [weak self] in self?.configureScroller() }
    }
    override func layout() {
        super.layout()
        configureScroller()
    }
    func configureScroller() {
        guard let scroll = enclosingScrollView else { return }
        PanelScrollAppearance.configure(scroll)
    }
}

@MainActor
enum PanelScrollAppearance {
    static func configure(_ scroll: NSScrollView) {
        if scroll.scrollerStyle != .overlay { scroll.scrollerStyle = .overlay }
        if scroll.verticalScroller?.controlSize != .small { scroll.verticalScroller?.controlSize = .small }
        if scroll.drawsBackground { scroll.drawsBackground = false }
        if scroll.contentView.drawsBackground { scroll.contentView.drawsBackground = false }
        if !scroll.autohidesScrollers { scroll.autohidesScrollers = true }
    }
}

/// AppKit may reapply the system's legacy scroller preference after attachment
/// or an appearance change. Reassert the panel policy when it lays out the view.
final class PanelOverlayScrollView: NSScrollView {
    private var isConfiguringAppearance = false

    override func tile() {
        if !isConfiguringAppearance {
            isConfiguringAppearance = true
            PanelScrollAppearance.configure(self)
            isConfiguringAppearance = false
        }
        super.tile()
    }
}

struct SettingsPlainScrollEdges: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        // Older SDKs do not expose scroll-edge effects; keep the macOS 13 build path.
        #if canImport(SwiftUI, _version: 7.0)
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectHidden(true)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
