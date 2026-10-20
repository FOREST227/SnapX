# SnapX

macOS 原生截图工具。截完图直接在原位编辑，支持标注、钉图、OCR 文字提取。

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/github/license/Forest227/SnapBoard)
![Release](https://img.shields.io/github/v/release/Forest227/SnapBoard)

## 平台状态

- 当前可运行版本：**macOS 13+**
- Windows 适配：已新增 Windows 工程骨架，说明见 [Windows/README.md](Windows/README.md)，迁移路线见 [docs/WINDOWS_PORTING.md](docs/WINDOWS_PORTING.md)
- 计划目标：**Windows x86 / x64 / ARM64**

## 功能一览

### 截图

| 模式 | 说明 |
|------|------|
| 框选截图 | 自动高亮指针所在窗口，单击确认窗口或拖动自由框选；框选后可拖动边框调整范围，也可拖动整体移动 |
| 全屏截图 | 移动鼠标到目标屏幕，单击即可截取整个显示器 |

两种截图时机可选：

- **先冻结** — 触发截图时立即冻结屏幕，在静止画面上框选和编辑
- **先选择** — 在实时画面上框选，确认后才捕获对应区域

触发截图时会播放提示音效。

### 标注编辑

截图后原位弹出编辑菜单，支持 7 种标注工具（键盘 1-7 快速切换）：

| 快捷键 | 工具 |
|--------|------|
| `1` | 矩形 |
| `2` | 高亮 |
| `3` | 文字 |
| `4` | 箭头 |
| `5` | 直线 |
| `6` | 画笔 |
| `7` | 马赛克 |

编辑完成后可：

- **复制到剪贴板** — 完成编辑按 Enter 或点击复制按钮
- **保存到下载文件夹** — 自动以时间戳命名
- **提取文字** — 基于 Apple Vision 的 OCR，支持中英文
- **钉住图片** — 创建浮动置顶窗口

### 截图历史

- 保留最近 50 张截图，支持缩放预览
- 多选模式：按住 ⌘ 多选，支持批量复制
- 右键菜单：快速复制、钉住或删除

### 钉图管理

- 透明度调节（25%–100%）
- 鼠标穿透开关
- 一键关闭所有钉图

### 其他

- **全局快捷键** — 完全可自定义，支持字母和数字键
- **主题切换** — 跟随系统 / 浅色 / 深色
- **开机启动** — 设置中一键开启
- **闪退日志** — 自动捕获崩溃信息，下次启动时提示保存到下载文件夹

## 默认快捷键

| 操作 | 快捷键 |
|------|--------|
| 框选截图 | `⌘⇧S` |
| 全屏截图 | `⌘⇧F` |
| 截图历史 | `⌘⇧H` |

所有快捷键均可在设置中修改。

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- 需要授权：**屏幕录制**权限

## 安装

### 直接下载

前往 [Releases](https://github.com/Forest227/SnapX/releases/latest) 下载 `SnapX-vX.X.X.dmg`，挂载后将 SnapX.app 拖入应用程序文件夹。

### 首次打开

GitHub 发布包使用临时签名，未经过 Apple 公证。如提示无法验证开发者，请确认安装包来自本项目 Releases，再在“系统设置 → 隐私与安全性”中允许打开。

### 手动更新

应用不再内置检查更新或后台自动更新。需要新版时，请通过菜单中的“GitHub 发布页”下载安装。

### 从源码构建

```bash
git clone https://github.com/Forest227/SnapX.git
cd SnapX

# 直接运行
swift run

# 首次配置固定的本机签名证书（以后无需重复创建）
bash Scripts/setup_local_signing.sh

# 打包 .app（输出到 Build/SnapX-arm64.app）
bash Scripts/build_app.sh arm64

# 保存截图并退出 SnapX 后，构建、备份旧版、安装到固定位置并启动
bash Scripts/install_local.sh
```

需要 Swift 6.2+ 工具链。

本机构建固定使用钥匙串中的 `SnapX Dev` 代码签名证书，证书指纹及公开证书保存在
`~/Library/Application Support/SnapX/Signing/`，私钥保存在登录钥匙串。初始化脚本可重复运行，
会复用原身份；构建找不到该身份时直接报错，不会退回临时签名。请保留原证书及私钥，
换电脑时通过钥匙串访问安全导出并迁移该身份，不要重新生成同名证书。

第一次从临时签名切换到固定签名后，需要重新授予屏幕录制及辅助功能权限。
之后保持同一签名身份、Bundle ID 和 `/Applications/SnapX.app` 安装位置，通常可以沿用权限；
macOS 自身要求的再次确认仍可能出现。不要混用 `swift run`、GitHub 下载版和本机签名版来验证权限保留。

GitHub Actions 显式使用 `SNAPX_SIGNING_MODE=adhoc` 保留原有发布方式，不包含本机私钥。
用这些临时签名的发布包覆盖本机签名版会改变身份，可能再次要求授权。


## 项目结构

```
Sources/SnapX/
├── SnapXApp.swift                  # 应用入口
├── AppDelegate.swift               # 应用生命周期
├── AppState.swift                  # 全局状态、权限、快捷键管理
├── CaptureCoordinator.swift        # 截图流程编排
├── SelectionOverlay.swift          # 框选 / 全屏选择遮罩
├── ScreenshotEditorWindowController.swift  # 标注编辑器、OCR
├── PinnedScreenshotWindowController.swift  # 浮动钉图窗口
├── ScreenshotHistory.swift         # 截图历史模型
├── HistoryWindowController.swift   # 截图历史面板
├── HotKeyConfiguration.swift       # 快捷键配置
├── HotKeyMonitor.swift             # Carbon 全局热键监听
├── StatusBarController.swift       # 菜单栏图标
├── MenuBarContentView.swift        # 菜单栏面板
├── SettingsView.swift              # 设置面板
├── SettingsWindowController.swift  # 设置窗口
├── ThemeManager.swift              # 主题管理
└── CrashReporter.swift             # 崩溃日志捕获
```

零外部依赖，仅使用 Apple 原生框架（AppKit、CoreGraphics、Vision、Carbon）。

如果要持续推进 Windows 适配，可以先运行：

```bash
python3 Scripts/audit_platform_dependencies.py
```

它会列出当前哪些源码文件仍强绑定 macOS 框架和 API。

## 许可

[MIT](LICENSE)

## 发布流程

提升 `Packaging/SnapX-Info.plist` 中的版本号，新增对应的 `release/v版本号/RELEASE.md`，
将这些修改提交到 `main` 后，GitHub Actions 会先测试，再构建 Apple Silicon、Intel 和通用版，
最后创建对应标签与 GitHub Release。也支持推送版本标签或手动运行发布工作流。
已存在且指向不同提交的版本标签会阻止发布，请使用新的版本号。
