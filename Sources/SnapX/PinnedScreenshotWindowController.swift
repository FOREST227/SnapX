import AppKit
import SwiftUI

@MainActor
final class PinnedScreenshotWindowController: NSWindowController, NSWindowDelegate {
    private let image: NSImage
    private let onClose: (PinnedScreenshotWindowController) -> Void
    private let zoom = HistoryZoomState()

    init(image: NSImage, onClose: @escaping (PinnedScreenshotWindowController) -> Void) {
        self.image = image
        self.onClose = onClose
        let size = Self.initialWindowSize(for: image.size)
        let window = PinnedScreenshotWindow(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        let root = PinnedScreenshotView(item: HistoryItem(image: image, date: Date()), zoom: zoom,
            onCopy: { [weak self] in self?.copyImage() },
            onClose: { [weak self] in self?.close() })
            .frame(minWidth: 80, minHeight: 60)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [.minSize]
        window.contentView = host
        window.setContentSize(size)
        ThemeManager.shared.applyTheme(to: window)
        positionWindow(window, size: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { onClose(self) }
    func setWindowOpacity(_ opacity: Double) { window?.alphaValue = CGFloat(min(max(opacity, 0.25), 1)) }
    func setMousePassthrough(_ enabled: Bool) { window?.ignoresMouseEvents = enabled }
    func zoomIn() { zoom.zoom(1.2) }
    func zoomOut() { zoom.zoom(1 / 1.2) }
    func resetZoom() { zoom.fit() }

    private func positionWindow(_ window: NSWindow, size: CGSize) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            window.center(); return
        }
        let visible = screen.visibleFrame
        window.setFrameOrigin(CGPoint(
            x: min(max(mouse.x + 24, visible.minX), visible.maxX - size.width),
            y: min(max(mouse.y - size.height - 24, visible.minY), visible.maxY - size.height)))
    }
    private func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    private static func initialWindowSize(for imageSize: CGSize) -> CGSize {
        let scale = min(1, 520 / max(imageSize.width, 1), 360 / max(imageSize.height, 1))
        return CGSize(width: max(80, imageSize.width * scale + 2), height: max(60, imageSize.height * scale + 2))
    }
}

private final class PinnedScreenshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct PinnedScreenshotView: View {
    let item: HistoryItem
    @ObservedObject var zoom: HistoryZoomState
    let onCopy: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HistoryImageViewer(item: item, zoom: zoom, pinnedMode: true)
            .padding(1)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.2), lineWidth: 1).allowsHitTesting(false))
            .overlay(PinnedResizeBorder())
            .overlay(alignment: .top) {
                HStack(alignment: .top, spacing: 4) {
                    PinnedDragHandle()
                        .frame(width: 24, height: 24)
                        .padding(3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5).allowsHitTesting(false))
                    Spacer(minLength: 0)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 2) {
                            control("arrow.counterclockwise", "适配图片", action: zoom.fit)
                            control("doc.on.doc", "复制原图", action: onCopy)
                            control("xmark", "关闭钉图", action: onClose)
                        }
                        control("xmark", "关闭钉图", action: onClose)
                    }
                    .padding(3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                }
                .padding(6)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .accessibilityHidden(!isHovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovering)
            }
            .onHover { isHovering = $0 }
            .help("鼠标滚轮或触摸板双指捏合缩放；双指滑动或拖动查看图片。按住左上角图钉按钮或 Option 拖动图片可移动窗口，拖动边框调整窗口大小。双击切换适配与 100%。")
            .contextMenu {
                Button("适配图片", action: zoom.fit)
                Button("100% 原始像素", action: zoom.actualSize)
                Button("复制原图", action: onCopy)
                Divider()
                Button("关闭钉图", action: onClose)
            }
    }
    private func control(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
