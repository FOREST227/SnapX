import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    var windowControlsInset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if windowControlsInset > 0 {
                SettingsWindowDragArea()
                    .frame(height: windowControlsInset)
                    .accessibilityHidden(true)
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("设置").font(.system(size: 20, weight: .semibold, design: .rounded))
                        Spacer()
                    }
                    captureSection
                    shortcutSection
                    generalSection
                    permissionSection
                    experimentalSection
                    Text("设置自动保存")
                        .font(.system(size: 12))
                        .foregroundStyle(AppPanelStyle.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(AppPanelStyle.padding)
                .background(SettingsScrollAppearance().allowsHitTesting(false).accessibilityHidden(true))
            }
            .modifier(SettingsPlainScrollEdges())
            .clipped()
        }
        .frame(width: AppPanelStyle.width)
        .frame(minHeight: 600, idealHeight: 800)
        .background(AppPanelStyle.background)
        .tint(AppPanelStyle.accent)
        .onAppear(perform: refreshStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
    }

    private var captureSection: some View {
        SettingsSection(title: "截图方式", detail: "选择画面固定的时刻") {
            VStack(spacing: 10) {
                ForEach(CaptureTimingMode.allCases) { mode in
                    CaptureTimingModeButton(mode: mode, isSelected: appState.captureTimingMode == mode) {
                        appState.captureTimingMode = mode
                    }
                }
            }
        }
    }

    private var experimentalSection: some View {
        SettingsSection(title: "实验性功能") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Label("智能边缘吸附", systemImage: "viewfinder")
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                    Toggle("启用实验性智能边缘吸附", isOn: $appState.isEdgeSnappingEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                VStack(spacing: 6) {
                    HStack {
                        Text("吸附范围")
                        Spacer()
                        Text("\(Int(appState.edgeSnappingRange))pt")
                            .monospacedDigit()
                            .foregroundStyle(AppPanelStyle.accent)
                        Button {
                            appState.setEdgeSnappingRange(EdgeSnapRange.defaultValue)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.borderless)
                        .disabled(appState.edgeSnappingRange == EdgeSnapRange.defaultValue)
                        .help("恢复默认 16pt")
                        .accessibilityLabel("恢复默认吸附范围 16pt")
                    }
                    .font(.system(size: 12, weight: .medium))
                    Slider(value: Binding(get: { appState.edgeSnappingRange },
                                          set: { appState.setEdgeSnappingRange($0) }),
                           in: EdgeSnapRange.allowed, step: 1)
                        .accessibilityLabel("吸附范围")
                        .accessibilityValue("\(Int(appState.edgeSnappingRange))点")
                    HStack {
                        Text("4pt · 精细")
                        Spacer()
                        Text("32pt · 宽松")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(AppPanelStyle.secondaryText)
                }
                .disabled(!appState.isEdgeSnappingEnabled)
                Text("靠近边缘时显示蓝色起点，按下后锁定；拖动框选会贴合附近边界。按住 Option（⌥）可临时关闭吸附。")
                    .panelDescription(size: 12)
                    .fixedSize(horizontal: false, vertical: true)
                Text("默认关闭；识别可能不准。支持常见圆角气泡，外留约 2pt；不会自动选中整张表格。")
                    .panelDescription(size: 11)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .settingsGroup()
        }
    }

    private var shortcutSection: some View {
        SettingsSection(title: "快捷键") {
            VStack(spacing: 0) {
                ForEach(CaptureShortcutAction.allCases) { action in
                    HotKeyEditorRow(
                        action: action,
                        currentConfiguration: appState.hotKeyConfiguration(for: action),
                        onSave: { try appState.updateHotKey(for: action, configuration: $0) },
                        onReset: { try appState.resetHotKey(for: action) },
                        onRecordingChanged: { appState.setHotKeyRecordingActive($0) }
                    )
                    if action != CaptureShortcutAction.allCases.last { rowDivider }
                }
            }
            .settingsGroup()
            Text("点击按键框录入，至少包含一个修饰键。录入时全局快捷键暂停，Esc 取消。")
                .panelDescription(size: 12)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var generalSection: some View {
        SettingsSection(title: "通用") {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("外观")
                    ThemeSegmentedControl(selection: $appState.currentTheme)
                }
                .padding(14)
                rowDivider
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("登录时启动")
                        Text(appState.launchAtLoginStatusMessage.isEmpty
                             ? "登录 Mac 后自动运行 SnapX"
                             : appState.launchAtLoginStatusMessage)
                            .panelDescription(size: 12)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("登录时启动 SnapX", isOn: Binding(
                        get: { appState.isLaunchAtLoginEnabled },
                        set: { appState.setLaunchAtLoginEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(14)
            }
            .font(.system(size: 13))
            .settingsGroup()
        }
    }

    private var permissionSection: some View {
        SettingsSection(title: "权限") {
            VStack(spacing: 0) {
                PermissionSettingRow(title: "屏幕录制", detail: "用于截取屏幕内容",
                    isGranted: appState.permissionStatus == .granted) {
                    openPrivacySettings("Privacy_ScreenCapture")
                }
                rowDivider
                PermissionSettingRow(title: "辅助功能", detail: "用于优先响应含 ⌘ 的全局快捷键",
                    isGranted: appState.isAccessibilityPermissionGranted) {
                    openPrivacySettings("Privacy_Accessibility")
                }
            }
            .settingsGroup()
            Text("授权后返回此页面，状态会自动刷新。")
                .panelDescription(size: 12)
        }
    }

    private var rowDivider: some View { Divider().padding(.horizontal, 14) }

    private func refreshStatus() {
        appState.refreshPermissionStates()
        appState.refreshLaunchAtLoginState()
    }

    private func openPrivacySettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(AppPanelStyle.secondaryText)
                }
            }
            content()
        }
    }
}

private extension View {
    func settingsGroup() -> some View {
        background(AppPanelStyle.groupFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

private struct CaptureTimingModeButton: View {
    let mode: CaptureTimingMode
    let isSelected: Bool
    let action: () -> Void

    private var steps: [String] {
        mode == .freezeFirst ? ["触发", "冻结", "框选"] : ["触发", "框选", "冻结"]
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(mode.title).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AppPanelStyle.accent : Color.secondary.opacity(0.5))
                }
                HStack(spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        Text(step)
                            .font(.system(size: 11, weight: step == "冻结" ? .semibold : .regular))
                            .foregroundStyle(AppPanelStyle.secondaryText)
                        if index < steps.count - 1 {
                            Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(AppPanelStyle.secondaryText)
                        }
                    }
                }
                .accessibilityHidden(true)
                Text(mode.description)
                    .panelDescription(size: 12)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppPanelStyle.selectionFill : AppPanelStyle.groupFill,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? AppPanelStyle.selectionBorder : Color.primary.opacity(0.1), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityValue(isSelected ? "已选中" : "未选中")
        .accessibilityHint(mode.description)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct ThemeSegmentedControl: View {
    @Binding var selection: AppTheme
    @FocusState private var focusedTheme: AppTheme?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTheme.allCases) { theme in
                Button { selection = theme } label: {
                    HStack(spacing: 4) {
                        Image(systemName: theme.icon).font(.system(size: 11, weight: .medium))
                        Text(theme.displayName).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(selection == theme ? AppPanelStyle.accent : AppPanelStyle.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .contentShape(Capsule())
                    .background {
                        if selection == theme {
                            Capsule()
                                .fill(AppPanelStyle.controlFill)
                                .overlay(Capsule().strokeBorder(AppPanelStyle.controlBorder, lineWidth: 0.5))
                                .matchedGeometryEffect(id: "themeSelection", in: selectionAnimation)
                        }
                    }
                }
                .buttonStyle(.plain)
                .focused($focusedTheme, equals: theme)
                .accessibilityValue(selection == theme ? "已选中" : "未选中")
                .accessibilityAddTraits(selection == theme ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.055), in: Capsule())
        .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.22), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("界面外观")
        .onMoveCommand { direction in
            let themes = AppTheme.allCases
            guard let index = themes.firstIndex(of: focusedTheme ?? selection) else { return }
            let next: Int
            switch direction {
            case .left: next = max(index - 1, 0)
            case .right: next = min(index + 1, themes.count - 1)
            default: return
            }
            selection = themes[next]
            focusedTheme = themes[next]
        }
    }
}


private struct PermissionSettingRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppPanelStyle.success)
                        .font(.system(size: 12, weight: .medium))
                        .help("已授权")
                        .accessibilityLabel("\(title)已授权")
                } else {
                    Label("未授权", systemImage: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppPanelStyle.warning)
                }
            }
            HStack(spacing: 12) {
                Text(detail)
                    .panelDescription(size: 12)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(isGranted ? "管理" : "去授权", action: openSettings)
                    .buttonStyle(PanelNeutralButtonStyle())
                    .fixedSize()
                    .accessibilityLabel("在系统设置中管理\(title)权限")
            }
        }
        .padding(14)
    }
}

/// 监听键盘输入，录制用户自定义的快捷键组合。同一时间只允许一个录制器工作。
@MainActor
final class ShortcutRecorder: ObservableObject {
    private static weak var activeRecorder: ShortcutRecorder?
    static var isAnyRecording: Bool { activeRecorder?.isRecording == true }

    @Published private(set) var isRecording = false

    var onCapture: ((UInt32, HotKeyModifiers) -> Void)?
    var onCancel: (() -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []

    nonisolated init() {}

    func start() {
        guard !isRecording else { return }
        if let active = Self.activeRecorder, active !== self {
            active.stop()
        }
        Self.activeRecorder = self
        isRecording = true
        onRecordingChanged?(true)
        let window = NSApp?.keyWindow
        for name in [NSApplication.didResignActiveNotification, NSWindow.willCloseNotification,
                     NSWindow.didResignKeyNotification] {
            let isAppNotification = name == NSApplication.didResignActiveNotification
            guard isAppNotification || window != nil else { continue }
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: isAppNotification ? nil : window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stop()
                    self?.onCancel?()
                }
            })
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                // 录制器已释放时放行事件，避免遗留监视器吞掉按键。
                return event
            }
            // 本地监视器在主线程分发事件；吞掉所有按键避免触发其它 UI。
            MainActor.assumeIsolated {
                self.handle(event)
            }
            return nil
        }
    }

    func stop() {
        guard isRecording else { return }
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        isRecording = false
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }
        onRecordingChanged?(false)
    }

    func handle(_ event: NSEvent) {
        guard isRecording, !event.isARepeat else { return }

        let modifiers = HotKeyModifiers(eventFlags: event.modifierFlags)
        if Int(event.keyCode) == kVK_Escape && modifiers.isEmpty {
            stop()
            onCancel?()
            return
        }

        onCapture?(UInt32(event.keyCode), modifiers)
    }

    // 注：不在 deinit 中调用 NSEvent.removeMonitor（新 SDK 下该 API 为主执行器隔离）。
    // 所有正常出口（取消、保存、恢复默认、窗口关闭）都会显式调用 stop()；
    // 若实例异常释放，监视器回调中的 weak self 会把按键事件放行，不再拦截。
}

private extension HotKeyModifiers {
    init(eventFlags: NSEvent.ModifierFlags) {
        var value: HotKeyModifiers = []
        if eventFlags.contains(.control) { value.insert(.control) }
        if eventFlags.contains(.option) { value.insert(.option) }
        if eventFlags.contains(.shift) { value.insert(.shift) }
        if eventFlags.contains(.command) { value.insert(.command) }
        self = value
    }
}

private struct HotKeyEditorRow: View {
    let action: CaptureShortcutAction
    let currentConfiguration: HotKeyConfiguration
    let onSave: (HotKeyConfiguration) throws -> Void
    let onReset: () throws -> Void
    let onRecordingChanged: (Bool) -> Void

    @StateObject private var recorder = ShortcutRecorder()
    @State private var errorMessage = ""
    @State private var inputDraft = ShortcutInputDraft()
    @State private var didSave = false
    @State private var feedbackTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayedConfiguration: HotKeyConfiguration {
        inputDraft.displayed(over: currentConfiguration)
    }

    private var shortcutParts: [String] {
        displayedConfiguration.modifiers.symbolString.map { String($0) } + [HotKeyKey.label(for: displayedConfiguration.keyCode)]
    }

    private var shortcutAccessibilityValue: String {
        if recorder.isRecording { return "等待按键" }
        if !errorMessage.isEmpty {
            return "未保存，\(displayedConfiguration.displayString)。当前生效：\(currentConfiguration.displayString)"
        }
        return (didSave ? "已保存，" : "") + currentConfiguration.displayString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(action.title)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)


                Button(action: toggleRecording) {
                    Group {
                        if recorder.isRecording {
                            Text("请按组合键…")
                        } else if didSave {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(AppPanelStyle.success)
                                .transition(reduceMotion ? .identity : .scale(scale: 0.85).combined(with: .opacity))
                        } else {
                            HStack(spacing: 6) {
                                ForEach(Array(shortcutParts.enumerated()), id: \.offset) { _, part in
                                    Text(part)
                                }
                            }
                        }
                    }
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 116, height: 30)
                        .background(AppPanelStyle.controlFill, in: RoundedRectangle(cornerRadius: AppPanelStyle.controlCornerRadius))
                        .overlay {
                            if !errorMessage.isEmpty {
                                RoundedRectangle(cornerRadius: AppPanelStyle.controlCornerRadius)
                                    .strokeBorder(AppPanelStyle.warning, lineWidth: 1.5)
                            } else if recorder.isRecording {
                                ShortcutRecordingOutline()
                            } else {
                                RoundedRectangle(cornerRadius: AppPanelStyle.controlCornerRadius)
                                    .strokeBorder(didSave ? AppPanelStyle.success : AppPanelStyle.controlBorder,
                                                  lineWidth: didSave ? 1.5 : 0.5)
                            }
                        }
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: didSave)
                        .contentShape(RoundedRectangle(cornerRadius: AppPanelStyle.controlCornerRadius))
                }
                .buttonStyle(.plain)
                .help("点击录入快捷键；Esc 取消录入或撤销无效输入")
                .accessibilityLabel("设置\(action.title)快捷键")
                .accessibilityValue(shortcutAccessibilityValue)

                Group {
                    if !errorMessage.isEmpty {
                        ShortcutErrorIndicator(message: errorMessage, actionTitle: action.title,
                            onReset: restoreDefaults, onCancel: cancelRecording)
                    } else {
                        Button {
                            if recorder.isRecording { cancelRecording() } else { restoreDefaults() }
                        } label: {
                            Image(systemName: recorder.isRecording ? "xmark" : "arrow.counterclockwise")
                                .font(.system(size: 12))
                                .frame(width: 26, height: 30)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(AppPanelStyle.secondaryText)
                        .disabled(!recorder.isRecording && currentConfiguration == action.defaultConfiguration)
                        .opacity(!recorder.isRecording && currentConfiguration == action.defaultConfiguration ? 0.4 : 1)
                        .help(recorder.isRecording ? "取消录入" : "恢复默认快捷键")
                        .accessibilityLabel(recorder.isRecording ? "取消录入" : "恢复\(action.title)默认快捷键")
                    }
                }
                .frame(width: 26, height: 30)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ShortcutDraftEscapeHandler(enabled: !errorMessage.isEmpty, onCancel: cancelRecording)
            .allowsHitTesting(false).accessibilityHidden(true))
        .onDisappear {
            feedbackTask?.cancel()
            didSave = false
            recorder.stop()
        }
    }

    private func toggleRecording() {
        if recorder.isRecording { cancelRecording(); return }
        feedbackTask?.cancel()
        didSave = false
        errorMessage = ""
        inputDraft.cancel()
        recorder.onCapture = { keyCode, modifiers in
            do {
                try inputDraft.submit(HotKeyConfiguration(keyCode: keyCode, modifiers: modifiers), save: onSave)
                recorder.stop()
                showSavedFeedback()
            } catch {
                recorder.stop()
                didSave = false
                errorMessage = error.localizedDescription
            }
        }
        recorder.onCancel = { inputDraft.cancel(); errorMessage = "" }
        recorder.onRecordingChanged = onRecordingChanged
        recorder.start()
    }

    private func cancelRecording() {
        recorder.stop()
        inputDraft.cancel()
        errorMessage = ""
    }

    private func restoreDefaults() {
        do {
            try inputDraft.submit(action.defaultConfiguration) { _ in try onReset() }
            showSavedFeedback()
        } catch {
            didSave = false
            errorMessage = error.localizedDescription
        }
    }

    private func showSavedFeedback() {
        errorMessage = ""
        feedbackTask?.cancel()
        didSave = true
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            didSave = false
        }
    }
}

private struct ShortcutRecordingOutline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: AppPanelStyle.controlCornerRadius)
            .strokeBorder(AppPanelStyle.accent, lineWidth: 2)
            .opacity(pulse && !reduceMotion ? 0.45 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = !reduceMotion }
            .onChange(of: reduceMotion) { pulse = !$0 }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// An error stays discoverable without inserting another row into the settings layout.
struct ShortcutErrorIndicator: View {
    let message: String
    let actionTitle: String
    let onReset: () -> Void
    let onCancel: () -> Void
    @State private var showsDetails = false

    var body: some View {
        Button { showsDetails.toggle() } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppPanelStyle.warning)
                .frame(width: 26, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(message)
        .accessibilityLabel("查看\(actionTitle)快捷键错误")
        .accessibilityValue(message)
        .onDisappear { showsDetails = false }
        .popover(isPresented: $showsDetails, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                Label("快捷键未更改", systemImage: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppPanelStyle.warning)
                Text(message)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("恢复默认") { showsDetails = false; onReset() }
                    Spacer()
                    Button("知道了") { showsDetails = false }
                }
                .buttonStyle(PanelNeutralButtonStyle())
            }
            .padding(14)
            .frame(width: 260)
            .background(ShortcutDraftEscapeHandler(enabled: true) {
                showsDetails = false
                onCancel()
            }.allowsHitTesting(false).accessibilityHidden(true))
        }
    }
}
