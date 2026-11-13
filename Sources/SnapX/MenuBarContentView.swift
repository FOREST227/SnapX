import SwiftUI

@MainActor
struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            permissionCard
            pinControls
            actionButtons
            Divider().opacity(0.5)
            secondaryActions
            footer
        }
        .padding(AppPanelStyle.padding)
        .frame(width: AppPanelStyle.width)
        .background(AppPanelStyle.background)
        .tint(AppPanelStyle.accent)
        .onAppear {
            appState.refreshPermissionStates()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SnapX")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text("快速截屏、标注、钉图")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(AppPanelStyle.secondaryText)
        }
    }

    @ViewBuilder
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if allPermissionsGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(AppPanelStyle.accent)
                    Text("权限已就绪")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(appState.hotKeySummaryDisplay)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(AppPanelStyle.secondaryText)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(AppPanelStyle.warning)
                    Text("权限状态")
                        .font(.system(size: 13, weight: .semibold))
                }

                permissionStatusRow(
                    title: "屏幕录制",
                    isGranted: appState.permissionStatus == .granted,
                    grantedDetail: "截图功能可用",
                    missingDetail: "未授权会导致无法截图"
                )

                permissionStatusRow(
                    title: "辅助功能",
                    isGranted: appState.isAccessibilityPermissionGranted,
                    grantedDetail: "Command 全局快捷键可用",
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
        }
        .padding(12)
        .background(
            AppPanelStyle.groupFill,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: appState.startFramedCapture) {
                actionLabel(
                    title: "框选截图",
                    shortcut: appState.framedHotKeyDisplay,
                    systemImage: "camera.viewfinder"
                )
            }
            .buttonStyle(MenuActionButtonStyle(emphasis: .primary))

            Button(action: appState.startDisplayCapture) {
                actionLabel(
                    title: "全屏截图",
                    shortcut: appState.displayHotKeyDisplay,
                    systemImage: "rectangle.inset.filled"
                )
            }
            .buttonStyle(MenuActionButtonStyle())

            Button(action: appState.openHistory) {
                actionLabel(
                    title: "截图历史",
                    shortcut: appState.historyHotKeyDisplay,
                    systemImage: "clock.arrow.circlepath"
                )
            }
            .buttonStyle(MenuActionButtonStyle())
        }
    }

    private var secondaryActions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: appState.openSettings) {
                secondaryLabel(title: "设置", systemImage: "gearshape")
            }
            .buttonStyle(MenuSecondaryButtonStyle())

            Button(action: openGitHubReleases) {
                secondaryLabel(title: "GitHub 发布页", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(MenuSecondaryButtonStyle())

            Button(action: appState.restart) {
                secondaryLabel(title: "重启 SnapX", systemImage: "arrow.clockwise.circle")
            }
            .buttonStyle(MenuSecondaryButtonStyle())

            Button(action: appState.quit) {
                secondaryLabel(title: "退出 SnapX", systemImage: "power")
            }
            .buttonStyle(MenuSecondaryButtonStyle(destructive: true))
        }
    }

    private var pinControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("钉图")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("当前 \(appState.pinnedCount) 张")
                    .panelDescription(size: 12)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("钉图透明度", systemImage: "circle.lefthalf.filled")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(Int(appState.pinOpacity * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppPanelStyle.secondaryText)
                }

                Slider(value: pinOpacityBinding, in: 0.25 ... 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("允许钉图鼠标穿透")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Toggle("允许钉图鼠标穿透", isOn: mousePassthroughBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityHint("统一设置所有钉图的鼠标穿透；单张钉图可双击左上角图钉单独切换。")
                }
                Text("开启后可点击钉图下方的窗口。\n双击钉图左上角图钉可单独切换。")
                    .panelDescription(size: 11.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(action: appState.clearPinnedShots) {
                    Label("清空钉图", systemImage: "rectangle.stack.badge.minus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(Color(nsColor: .systemRed))
                .opacity(appState.pinnedCount == 0 ? 0.4 : 1)
                .disabled(appState.pinnedCount == 0)
            }
        }
        .padding(12)
        .background(AppPanelStyle.groupFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private func actionLabel(title: String, shortcut: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
            Text(title)
            Spacer()
            Text(shortcut)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private func secondaryLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
            Text(title)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("v\(appVersion)")
                .font(.system(size: 11))
                .foregroundStyle(AppPanelStyle.secondaryText)
        }
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

    private func permissionStatusRow(title: String, isGranted: Bool, grantedDetail: String, missingDetail: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isGranted ? AppPanelStyle.success : AppPanelStyle.warning)
                .help(isGranted ? "已授权" : "未授权")
                .accessibilityLabel("\(title)\(isGranted ? "已授权" : "未授权")")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(isGranted ? grantedDetail : missingDetail)
                    .panelDescription(size: 11.5)
            }

            Spacer(minLength: 8)

            if !isGranted {
                Text("未授权")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPanelStyle.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppPanelStyle.groupFill, in: Capsule())
            }
        }
    }
}

/// Shared geometry keeps primary, secondary, and disabled actions aligned.
struct MenuActionButtonStyle: ButtonStyle {
    enum Emphasis { case normal, primary, destructive }
    var emphasis: Emphasis = .normal
    @Environment(\.isEnabled) private var isEnabled

    private var fill: Color {
        guard isEnabled else { return AppPanelStyle.groupFill }
        switch emphasis {
        case .normal: return AppPanelStyle.groupFill
        case .primary: return AppPanelStyle.accent
        case .destructive: return Color(nsColor: .systemRed)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? (emphasis == .normal ? Color.primary : Color.white) : Color.secondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isEnabled && emphasis == .normal ? 0.12 : 0), lineWidth: 0.5)
            }
            .modifier(MenuHoverHighlight(color: emphasis == .primary ? Color.white.opacity(0.10) : Color.primary.opacity(0.06), radius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed && isEnabled ? 0.75 : (isEnabled ? 1 : 0.55))
    }
}

struct MenuSecondaryButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(!isEnabled ? Color.secondary : (destructive ? Color(nsColor: .systemRed) : Color.primary))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 28)
            .modifier(MenuHoverHighlight(color: Color.primary.opacity(0.06), radius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed && isEnabled ? 0.75 : (isEnabled ? 1 : 0.55))
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
            .animation(AppMotion.quick(reduceMotion), value: isHovering)
    }
}
