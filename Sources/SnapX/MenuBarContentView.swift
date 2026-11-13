import SwiftUI

@MainActor
struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    /// Only the live popover animates in; snapshots and previews render settled.
    var animatesEntrance = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasEntered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 14)
            if !allPermissionsGranted {
                permissionNotice
                    .padding(.bottom, 14)
            }
            captureActions
            PanelHairline()
                .padding(.vertical, 12)
            pinControls
            PanelHairline()
                .padding(.top, 12)
                .padding(.bottom, 8)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(width: AppPanelStyle.width)
        .opacity(isSettled ? 1 : 0)
        .offset(y: isSettled ? 0 : 4)
        .tint(AppPanelStyle.accent)
        .onAppear {
            appState.refreshPermissionStates()
            withAnimation(AppMotion.enter(reduceMotion)) { hasEntered = true }
        }
        .onDisappear { hasEntered = false }
    }

    private var isSettled: Bool { !animatesEntrance || hasEntered }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SnapX")
                    .font(.system(size: 17, weight: .medium))
                Text("快速截屏、标注、钉图")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if allPermissionsGranted {
                HStack(spacing: 5) {
                    Circle()
                        .fill(AppPanelStyle.success)
                        .frame(width: 6, height: 6)
                    Text("已就绪")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .help("屏幕录制与辅助功能均已授权")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("权限已就绪")
            }
        }
        .padding(.horizontal, 2)
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("需要授权后才能正常使用", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(AppPanelStyle.warning)

            permissionStatusRow(
                title: "屏幕录制",
                isGranted: appState.permissionStatus == .granted,
                missingDetail: "未授权会导致无法截图"
            )
            permissionStatusRow(
                title: "辅助功能",
                isGranted: appState.isAccessibilityPermissionGranted,
                missingDetail: "未授权时快捷键可能无响应"
            )

            HStack(spacing: 8) {
                if appState.permissionStatus == .needsPermission {
                    Button("授权屏幕录制", action: appState.requestScreenCaptureAccess)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                if !appState.isAccessibilityPermissionGranted {
                    Button("授权辅助功能", action: appState.requestAccessibilityAccess)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPanelStyle.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func permissionStatusRow(title: String, isGranted: Bool, missingDetail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isGranted ? AppPanelStyle.success : AppPanelStyle.warning)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12.5))
            Spacer(minLength: 8)
            Text(isGranted ? "已授权" : missingDetail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)\(isGranted ? "已授权" : "未授权")")
    }

    private var captureActions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: appState.startFramedCapture) {
                menuLabel(title: "框选截图", shortcut: appState.framedHotKeyDisplay, systemImage: "camera.viewfinder")
            }
            .buttonStyle(MenuPrimaryButtonStyle())
            .padding(.bottom, 4)

            Button(action: appState.startDisplayCapture) {
                menuLabel(title: "全屏截图", shortcut: appState.displayHotKeyDisplay, systemImage: "rectangle.dashed")
            }
            .buttonStyle(MenuRowButtonStyle())

            Button(action: appState.openHistory) {
                menuLabel(title: "截图历史", shortcut: appState.historyHotKeyDisplay, systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(MenuRowButtonStyle())
        }
    }

    private func menuLabel(title: String, shortcut: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .frame(width: 18)
            Text(title)
            Spacer()
            Text(shortcut)
                .font(.system(size: 12))
                .monospacedDigit()
                .opacity(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var pinControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("钉图")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空", action: appState.clearPinnedShots)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(appState.pinnedCount == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(AppPanelStyle.error))
                    .disabled(appState.pinnedCount == 0)
                    .help("关闭所有钉图")
            }

            HStack(spacing: 10) {
                Text("透明度")
                    .font(.system(size: 13))
                Slider(value: pinOpacityBinding, in: 0.25 ... 1)
                    .controlSize(.small)
                    .accessibilityLabel("钉图透明度")
                Text("\(Int(appState.pinOpacity * 100))%")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("鼠标穿透")
                        .font(.system(size: 13))
                    Spacer()
                    Toggle("允许钉图鼠标穿透", isOn: mousePassthroughBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .accessibilityHint("统一设置所有钉图的鼠标穿透；单张钉图可双击左上角图钉单独切换。")
                }
                Text("开启后可点击钉图下方的窗口。\n双击钉图左上角图钉可单独切换。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 2)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Text("钉图 \(appState.pinnedCount) 张 · v\(appVersion)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .padding(.leading, 2)
            Spacer()
            Button(action: appState.openSettings) { Image(systemName: "gearshape") }
                .buttonStyle(MenuIconButtonStyle())
                .help("设置")
                .accessibilityLabel("设置")
            Button(action: openGitHubReleases) { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(MenuIconButtonStyle())
                .help("GitHub 发布页")
                .accessibilityLabel("GitHub 发布页")
            Button(action: appState.quit) { Image(systemName: "power") }
                .buttonStyle(MenuIconButtonStyle())
                .help("退出 SnapX（右键可重启）")
                .accessibilityLabel("退出 SnapX")
                .contextMenu {
                    Button("重启 SnapX", action: appState.restart)
                    Button("退出 SnapX", action: appState.quit)
                }
        }
    }

    private var pinOpacityBinding: Binding<Double> {
        Binding(
            get: { appState.pinOpacity },
            set: { newValue in
                appState.updatePinOpacity(newValue)
            }
        )
    }

    private var mousePassthroughBinding: Binding<Bool> {
        Binding(
            get: { appState.isMousePassthroughEnabled },
            set: { newValue in
                appState.setMousePassthroughEnabled(newValue)
            }
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var allPermissionsGranted: Bool {
        appState.permissionStatus == .granted && appState.isAccessibilityPermissionGranted
    }

    private func openGitHubReleases() {
        if let url = URL(string: "https://github.com/Forest227/SnapX/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct PanelHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 2)
    }
}

/// The single filled action in the panel; slightly desaturated so it anchors
/// the layout without shouting over the native material.
struct MenuPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppPanelStyle.accent)
                    .saturation(0.86)
            }
            .modifier(MenuHoverHighlight(color: Color.white.opacity(0.10), radius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}

/// Borderless menu row: only the hover highlight reveals the hit area.
struct MenuRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
            }
            .modifier(MenuHoverHighlight(color: Color.primary.opacity(0.07), radius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

struct MenuIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0))
            }
            .modifier(MenuHoverHighlight(color: Color.primary.opacity(0.07), radius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct MenuHoverHighlight: ViewModifier {
    let color: Color
    let radius: CGFloat
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isHovering ? color : .clear)
                    .allowsHitTesting(false)
            }
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: isHovering ? 0.12 : 0.18), value: isHovering)
    }
}
