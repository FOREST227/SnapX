import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                header
                themeSection
                captureTimingModeSection
                launchAtLoginSection
                shortcutSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 430, idealWidth: 430, minHeight: 500, idealHeight: 580)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            appState.refreshLaunchAtLoginState()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("设置")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("管理开机启动、截图模式和截图快捷键。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var captureTimingModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("截图模式", systemImage: "camera.viewfinder")
                .font(.system(size: 15, weight: .semibold))

            Text("选择触发截图时的行为方式。")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                ForEach(CaptureTimingMode.allCases) { mode in
                    CaptureTimingModeButton(
                        mode: mode,
                        isSelected: appState.captureTimingMode == mode,
                        action: { appState.captureTimingMode = mode }
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("开机启动", systemImage: "power.circle")
                .font(.system(size: 15, weight: .semibold))

            HStack(alignment: .top, spacing: 16) {
                Text("登录 macOS 时自动启动 SnapX")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { appState.isLaunchAtLoginEnabled },
                        set: { appState.setLaunchAtLoginEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }

            if !appState.launchAtLoginStatusMessage.isEmpty {
                Text(appState.launchAtLoginStatusMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("外观", systemImage: "paintbrush")
                .font(.system(size: 15, weight: .semibold))

            Text("选择应用界面主题，截图编辑器将跟随此设置。")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    ThemeButton(
                        theme: theme,
                        isSelected: appState.currentTheme == theme,
                        action: { appState.currentTheme = theme }
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("截图快捷键", systemImage: "keyboard")
                .font(.system(size: 15, weight: .semibold))

            Text("点击快捷键输入框后按下想要的组合键即可设定，例如 ⌘⇧S。支持字母、数字、F1–F20、方向键等；至少需要一个修饰键。修改后立即生效。")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HotKeyEditorCard(
                action: .framed,
                currentConfiguration: appState.framedHotKeyConfiguration,
                onSave: { try appState.updateHotKey(for: .framed, configuration: $0) },
                onReset: { try appState.resetHotKey(for: .framed) },
                onRecordingChanged: { appState.setHotKeyRecordingActive($0) }
            )

            HotKeyEditorCard(
                action: .display,
                currentConfiguration: appState.displayHotKeyConfiguration,
                onSave: { try appState.updateHotKey(for: .display, configuration: $0) },
                onReset: { try appState.resetHotKey(for: .display) },
                onRecordingChanged: { appState.setHotKeyRecordingActive($0) }
            )

            HotKeyEditorCard(
                action: .history,
                currentConfiguration: appState.historyHotKeyConfiguration,
                onSave: { try appState.updateHotKey(for: .history, configuration: $0) },
                onReset: { try appState.resetHotKey(for: .history) },
                onRecordingChanged: { appState.setHotKeyRecordingActive($0) }
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 监听键盘输入，录制用户自定义的快捷键组合。同一时间只允许一个录制器工作。
@MainActor
private final class ShortcutRecorder: ObservableObject {
    private static weak var activeRecorder: ShortcutRecorder?

    @Published private(set) var isRecording = false

    var onCapture: ((UInt32, HotKeyModifiers) -> Void)?
    var onCancel: (() -> Void)?

    private var monitor: Any?

    func start() {
        guard !isRecording else { return }
        if let active = Self.activeRecorder, active !== self {
            active.stop()
        }
        Self.activeRecorder = self
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 本地监视器在主线程分发事件；吞掉所有按键避免触发其它 UI。
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }

        if Int(event.keyCode) == kVK_Escape {
            stop()
            onCancel?()
            return
        }

        let modifiers = HotKeyModifiers(eventFlags: event.modifierFlags)
        onCapture?(UInt32(event.keyCode), modifiers)
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
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

private struct HotKeyEditorCard: View {
    let action: CaptureShortcutAction
    let currentConfiguration: HotKeyConfiguration
    let onSave: (HotKeyConfiguration) throws -> Void
    let onReset: () throws -> Void
    let onRecordingChanged: (Bool) -> Void

    @StateObject private var recorder = ShortcutRecorder()
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(action.title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if !recorder.isRecording {
                    Text(currentConfiguration.displayString)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    toggleRecording()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: recorder.isRecording ? "record.circle.fill" : "keyboard")
                        Text(recorder.isRecording ? "请按下快捷键…" : currentConfiguration.displayString)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .frame(minWidth: 190, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .tint(recorder.isRecording ? .red : .accentColor)

                if recorder.isRecording {
                    Button("取消") {
                        cancelRecording()
                    }
                    .buttonStyle(.bordered)
                }

                Button("恢复默认") {
                    restoreDefaults()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("点击输入框后按下想要的组合键即可保存，Esc 取消。录制期间当前快捷键暂停生效。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onChange(of: currentConfiguration) { _ in
            if !recorder.isRecording {
                errorMessage = ""
            }
        }
        .onDisappear {
            if recorder.isRecording {
                recorder.stop()
                onRecordingChanged(false)
            }
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            cancelRecording()
            return
        }

        errorMessage = ""
        recorder.onCapture = { keyCode, modifiers in
            capture(keyCode: keyCode, modifiers: modifiers)
        }
        recorder.onCancel = {
            errorMessage = ""
            onRecordingChanged(false)
        }
        recorder.start()
        onRecordingChanged(true)
    }

    private func cancelRecording() {
        recorder.stop()
        errorMessage = ""
        onRecordingChanged(false)
    }

    private func capture(keyCode: UInt32, modifiers: HotKeyModifiers) {
        do {
            try onSave(HotKeyConfiguration(keyCode: keyCode, modifiers: modifiers))
            errorMessage = ""
            recorder.stop()
            onRecordingChanged(false)
        } catch {
            // 保存失败时保持录制状态，方便直接重按组合键。
            errorMessage = error.localizedDescription
        }
    }

    private func restoreDefaults() {
        if recorder.isRecording {
            recorder.stop()
            onRecordingChanged(false)
        }
        do {
            try onReset()
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ThemeButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: theme.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                Text(theme.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CaptureTimingModeButton: View {
    let mode: CaptureTimingMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                Text(mode.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                Text(mode.description)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
