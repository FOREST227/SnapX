import AppKit
import SwiftUI

@MainActor
final class HistoryBrowserModel: ObservableObject {
    @Published var selection = HistorySelection()
    func reconcile(_ items: [HistoryItem]) { selection.reconcile(items.map(\.id)) }
    func select(_ item: HistoryItem, items: [HistoryItem]) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        selection.select(item.id, in: items.map(\.id), command: modifiers.contains(.command), shift: modifiers.contains(.shift))
    }
    func move(_ delta: Int, items: [HistoryItem]) { selection.move(delta, in: items.map(\.id)) }
}

@MainActor
final class HistoryWindowController: NSWindowController {
    private static var shared: HistoryWindowController?
    private let model = HistoryBrowserModel()
    private var largeWindow: NSWindow?
    private static let minimumContentSize = NSSize(width: 600, height: 400)

    init(appState: AppState) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "截图历史"
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: HistoryView(model: model, appState: appState,
            onExpand: { [weak self] in self?.showLargePreview(appState: appState) })
            .frame(minWidth: Self.minimumContentSize.width, minHeight: Self.minimumContentSize.height))
        host.sizingOptions = [.minSize]
        window.contentView = host
        window.contentMinSize = Self.minimumContentSize
        window.setContentSize(NSSize(width: 960, height: 640))
        window.center()
        ThemeManager.shared.applyTheme(to: window)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func present(appState: AppState) {
        if shared == nil { shared = HistoryWindowController(appState: appState) }
        shared?.model.reconcile(ScreenshotHistory.shared.items)
        if let window = shared?.window, let size = window.contentView?.bounds.size {
            window.setContentSize(NSSize(width: max(size.width, minimumContentSize.width), height: max(size.height, minimumContentSize.height)))
        }
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showLargePreview(appState: AppState) {
        guard model.selection.focusedID != nil else { return }
        if largeWindow == nil {
            let screen = window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
            let size = CGSize(width: min(1100, screen.width - 40), height: min(760, screen.height - 60))
            let panel = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                                 styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            panel.title = "截图预览"
            panel.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: HistoryDetailView(model: model, appState: appState,
                expanded: true, onExpand: { [weak self] in
                    self?.largeWindow?.close()
                    self?.window?.makeKeyAndOrderFront(nil)
                }).frame(minWidth: 560, minHeight: 360))
            host.sizingOptions = [.minSize]
            panel.contentView = host
            panel.setContentSize(size)
            panel.center()
            ThemeManager.shared.applyTheme(to: panel)
            largeWindow = panel
        }
        largeWindow?.makeKeyAndOrderFront(nil)
    }
}

struct HistoryView: View {
    @ObservedObject var model: HistoryBrowserModel
    let appState: AppState
    let onExpand: () -> Void
    @ObservedObject private var history = ScreenshotHistory.shared

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("历史记录").font(.headline)
                    Spacer()
                    Text("\(history.items.count)").foregroundStyle(.secondary).monospacedDigit()
                    Menu {
                        Button("清空历史", role: .destructive) { history.clear(); model.reconcile(history.items) }
                            .disabled(history.items.isEmpty)
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                }.padding(14)
                Divider()
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(history.items) { item in
                                Button { model.select(item, items: history.items) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Image(nsImage: item.image).resizable().aspectRatio(contentMode: .fit)
                                            .frame(maxWidth: .infinity).frame(height: 94)
                                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                                        HStack {
                                            Text(item.date, style: .time).font(.system(size: 11))
                                            Spacer()
                                            if model.selection.selectedIDs.contains(item.id) {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(model.selection.selectedIDs.contains(item.id) ? Color.accentColor.opacity(0.12) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(model.selection.focusedID == item.id ? Color.accentColor : Color.clear, lineWidth: 2))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("截图 \(item.date.formatted())")
                                .id(item.id)
                            }
                        }.padding(10)
                    }
                    .onChange(of: model.selection.focusedID) { id in
                        if let id { reader.scrollTo(id) }
                    }
                }
                Divider()
                Text("⌘ 多选 · Shift 连选 · ↑↓ 切图")
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(10)
            }
            .frame(width: 190)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            HistoryDetailView(model: model, appState: appState, expanded: false, onExpand: onExpand)
        }
        .onAppear { model.reconcile(history.items) }
        .onChange(of: history.items.map(\.id)) { _ in model.reconcile(history.items) }
    }
}

struct HistoryDetailView: View {
    @ObservedObject var model: HistoryBrowserModel
    let appState: AppState
    let expanded: Bool
    let onExpand: () -> Void
    @ObservedObject private var history = ScreenshotHistory.shared
    @StateObject private var zoom = HistoryZoomState()
    @State private var notice: String?
    private var item: HistoryItem? { history.items.first { $0.id == model.selection.focusedID } }
    private var selected: [HistoryItem] { history.items.filter { model.selection.selectedIDs.contains($0.id) } }
    private var isBatch: Bool { !expanded && !selected.isEmpty && (selected.count > 1 || selected.first?.id != item?.id) }

    var body: some View {
        VStack(spacing: 0) {
            if let item {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(isBatch ? "已选择 \(selected.count) 张截图" : item.date.formatted(date: .abbreviated, time: .standard))
                            .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(pixelDescription(item.image)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        Button { copy() } label: { Label(isBatch ? "复制所选" : "复制", systemImage: "doc.on.doc") }
                        Button { for value in targets { appState.pinImage(value.image) }; notice = "已钉住" } label: { Label("钉住", systemImage: "pin") }
                        Button { save(item) } label: { Label("保存", systemImage: "square.and.arrow.down") }.disabled(isBatch)
                        Button(role: .destructive) { delete() } label: { Image(systemName: "trash") }.help(isBatch ? "删除所选" : "删除当前截图")
                        Spacer(minLength: 0)
                        Button(action: onExpand) { Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }
                            .help(expanded ? "返回历史（Esc）" : "大图预览（空格）")
                    }.buttonStyle(.borderless).font(.system(size: 12))
                }.padding(12)
                Divider()
                HistoryImageViewer(item: item, zoom: zoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("截图预览，滚轮或捏合缩放，拖动平移，双击切换适配与原始像素")
                Divider()
                HStack(spacing: 10) {
                    Button { zoom.zoom(1 / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }.help("缩小")
                    Text("\(zoom.percent)%").monospacedDigit().frame(minWidth: 42)
                    Button { zoom.zoom(1.25) } label: { Image(systemName: "plus.magnifyingglass") }.help("放大")
                    Button("适配") { zoom.fit() }
                    Button("100%") { zoom.actualSize() }
                    Spacer(minLength: 0)
                    Button { model.move(-1, items: history.items) } label: { Image(systemName: "chevron.left") }
                        .disabled(history.items.first?.id == item.id).help("上一张")
                    Button { model.move(1, items: history.items) } label: { Image(systemName: "chevron.right") }
                        .disabled(history.items.last?.id == item.id).help("下一张")
                }.buttonStyle(.borderless).font(.system(size: 12)).padding(12)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40))
                    Text("暂无截图历史")
                    Text("截图后可在这里浏览、复制和钉住图片").font(.system(size: 12))
                    if expanded { Button("返回历史", action: onExpand) }
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let notice {
                HStack {
                    Text(notice).font(.system(size: 11)).lineLimit(2)
                    Spacer()
                    Button { self.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.padding(8).background(Color.accentColor.opacity(0.08))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(HistoryKeyboardHandler { code, modifiers in
            guard modifiers.intersection([.command, .option, .control]).isEmpty else {
                if modifiers.contains(.command), code == 8 { copy(); return true }
                return false
            }
            switch code {
            case 123, 126: model.move(-1, items: history.items)
            case 124, 125: model.move(1, items: history.items)
            case 49: onExpand()
            case 53: if expanded { onExpand() } else { return false }
            default: return false
            }
            return true
        }.frame(width: 0, height: 0))
        .onChange(of: history.items.map(\.id)) { _ in model.reconcile(history.items) }
        .onChange(of: model.selection.focusedID) { _ in notice = nil }
    }
    private var targets: [HistoryItem] { isBatch ? selected : item.map { [$0] } ?? [] }
    private func copy() {
        guard !targets.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(targets.map(\.image))
        notice = isBatch ? "已复制 \(targets.count) 张截图" : "已复制"
    }
    private func delete() {
        let ids = Set(targets.map(\.id))
        history.removeAll { ids.contains($0.id) }
        model.reconcile(history.items)
    }
    private func save(_ item: HistoryItem) {
        do {
            let url = try ScreenshotEditorFileIO.saveImageToDownloads(item.image)
            notice = "已保存到下载：\(url.lastPathComponent)"
        } catch { notice = "保存失败：\(error.localizedDescription)" }
    }
    private func pixelDescription(_ image: NSImage) -> String {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        return "\(cg.width) × \(cg.height) px"
    }
}
