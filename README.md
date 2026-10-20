# SnapX

一款常驻 macOS 菜单栏的原生截图工具。框选后直接在原位标注、复制、保存或钉住图片，也可以提取截图中的文字。

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](#系统要求)
[![Swift](https://img.shields.io/badge/Swift-6.2%2B-orange)](#从源码构建)
[![Release](https://img.shields.io/github/v/release/FOREST227/SnapX)](https://github.com/FOREST227/SnapX/releases/latest)

**[下载最新版本](https://github.com/FOREST227/SnapX/releases/latest)** · **[v0.2.0 更新说明](release/v0.2.0/RELEASE.md)** · **[反馈问题](https://github.com/FOREST227/SnapX/issues)**

## 快速开始

1. 从 [Releases](https://github.com/FOREST227/SnapX/releases/latest) 下载适合你 Mac 的安装包，将 `SnapX.app` 放入“应用程序”文件夹。
2. 启动 SnapX，在系统设置中授予屏幕录制权限；按提示配置辅助功能权限。
3. 按 **⌘⇧S** 开始截图：单击高亮窗口，或拖动鼠标框选区域。
4. 完成标注后按 **Enter** 或点击完成按钮复制截图，也可以选择保存、提取文字或钉图。

SnapX 常驻菜单栏。点击菜单栏图标，可以调整钉图、打开历史或进入设置。

## 截图方式

支持自由框选、窗口可见区域截图和整屏截图。多屏环境下，可以单击目标显示器截取该屏幕；跨屏窗口按当前屏幕上的可见范围选取。

在设置中选择画面固定的时机：

| 截图方式 | 什么时候固定画面 | 使用场景 |
| --- | --- | --- |
| **触发时冻结** | 按下截图快捷键时保存画面，再在静止画面上框选 | 菜单、弹窗、视频画面等临时内容 |
| **选区确认时冻结** | 在实时画面上选择，松开鼠标完成框选或单击确认窗口时保存画面 | 需要先确定范围再截图的日常操作 |

进入编辑后，选区、背景和再次调整选框都使用同一张画面，保存时不会重新截屏。“冻结”只表示固定截图画面，不会暂停其他应用。

## 标注与输出

编辑器提供七种工具，可以用数字键快速切换：

| 按键 | 工具 | 用途 |
| --- | --- | --- |
| `1` | 线框 | 标出需要关注的区域 |
| `2` | 高亮 | 突出文字或局部内容 |
| `3` | 文字 | 添加说明，支持字号及粗体、斜体、下划线 |
| `4` | 箭头 | 指向具体位置 |
| `5` | 直线 | 分隔或连接内容 |
| `6` | 画笔 | 自由绘制 |
| `7` | 马赛克 | 遮挡图片中的信息 |

框选后可拖动边框调整范围。编辑完成后，可以：

- **复制**：将结果放入剪贴板，直接粘贴到其他应用。
- **保存**：保存为 PNG 到下载文件夹，按时间命名。
- **提取文字**：使用 Apple Vision 识别简体中文、繁体中文和英文，并复制结果。
- **钉住**：让图片浮动置顶，便于对照文档、代码或设计稿。

标注支持逐条撤销和重做。新增或修改标注后，旧的重做记录会清空；裁剪和选框调整暂不支持撤销、重做。

## 快捷键

### 全局快捷键

| 操作 | 默认快捷键 |
| --- | --- |
| 框选截图 | `⌘⇧S` |
| 全屏截图 | `⌘⇧F` |
| 截图历史 | `⌘⇧H` |

在“设置 → 快捷键”中点击按键框，再按下新的组合键即可修改。支持字母、数字、F1–F20、方向键及部分符号、功能键；组合键至少需要一个修饰键。录入期间全局快捷键暂停，按 `Esc` 取消。注册失败时会显示错误并保留原设置。

### 截图编辑快捷键

| 操作 | 快捷键 |
| --- | --- |
| 切换标注工具 | `1`–`7` |
| 撤销标注 | `⌘Z` |
| 重做标注 | `⌘Y` / `⇧⌘Z` |
| 完成并复制 | `Enter` |
| 取消当前操作或退出编辑 | `Esc` |

正在编辑文字时，部分按键会由文字编辑器处理。

## 钉图、历史与设置

- **钉图**：支持 25%–100% 透明度、鼠标穿透，以及一键关闭所有钉图。
- **历史**：保留最近 50 张截图，支持预览、多选和右键操作。
- **外观**：跟随系统、浅色或深色；主面板和设置页使用统一配色。
- **登录时启动**：从设置中开启，按 macOS 要求批准登录项。
- **权限状态**：在设置中查看屏幕录制和辅助功能授权，并直接打开对应系统设置。
- **崩溃日志**：下次启动时提示保存日志，方便定位问题。

## 安装与更新

### 选择安装包

| 你的设备 | 文件名标识 |
| --- | --- |
| Apple Silicon（M 系列） | `arm64` |
| Intel Mac | `x86_64` |
| 希望同时兼容两种架构 | `universal` |

每种架构均提供 DMG 和 ZIP。DMG 挂载后拖入应用程序文件夹；ZIP 解压后将应用移入同一位置。

### 首次打开与权限

GitHub 发布包使用临时签名，未经过 Apple 公证。如果 macOS 提示无法验证开发者，请确认安装包来自本仓库 Releases，再在“系统设置 → 隐私与安全性”中允许打开。

- **屏幕录制**：用于获取屏幕画面。
- **辅助功能**：用于增强含 `⌘` 的全局快捷键响应。

授权后返回 SnapX 检查状态；如果系统要求重启应用，请退出后重新打开。

### 手动更新

从 **v0.2.0** 起，SnapX 不再包含“检查更新”或后台自动更新。点击菜单中的“GitHub 发布页”，或访问 [Releases](https://github.com/FOREST227/SnapX/releases/latest) 下载新版；保存当前工作并退出旧版后再替换应用。

## 系统要求

- macOS 13（Ventura）或更新版本。
- 提供 Apple Silicon、Intel 和通用版构建。
- 当前可用的完整应用为 macOS 版。`Windows/` 是适配中的工程骨架，不是与 macOS 版功能对等的正式版本，详见 [Windows 说明](Windows/README.md) 和 [迁移计划](docs/WINDOWS_PORTING.md)。

## 从源码构建

需要 **Swift 6.2+** 和相应 macOS SDK。建议安装完整 Xcode；构建脚本会优先使用 `/Applications/Xcode.app` 中的开发工具。macOS 主程序通过 Swift Package Manager 构建，无第三方包依赖。

```bash
git clone https://github.com/FOREST227/SnapX.git
cd SnapX

# 编译开发版本
swift build
```

### 本机长期使用：固定签名

```bash
# 首次创建或复用本机代码签名证书
bash Scripts/setup_local_signing.sh

# 保存截图并退出 SnapX 后，构建、备份旧版、安装并启动
bash Scripts/install_local.sh
```

安装脚本默认选择当前 Mac 的架构，固定安装到 `/Applications/SnapX.app`。也可以只生成应用包：

```bash
bash Scripts/build_app.sh arm64
bash Scripts/build_app.sh x86_64
bash Scripts/build_app.sh universal
```

产物位于 `Build/SnapX-<架构>.app`；不传架构参数时默认生成通用版。

本机签名使用钥匙串中的 `SnapX Dev` 证书，公开证书与指纹保存在 `~/Library/Application Support/SnapX/Signing/`，私钥保存在登录钥匙串。脚本会复用同一身份；找不到原身份时直接报错，不会悄悄退回临时签名。

切换签名后通常需要重新授权一次。之后复用同一证书、Bundle ID 和安装位置，可改善重复构建后的权限保留，但不能免除 macOS 自身要求的再次确认。请保留原证书和私钥；重新生成同名证书并不等于保留原身份。

旧版安装备份保存在 `~/Library/Application Support/SnapX/InstallBackups/`。

### 临时签名构建

仅需生成与 GitHub 发布方式一致的临时签名包时，可显式指定：

```bash
SNAPX_SIGNING_MODE=adhoc bash Scripts/build_app.sh universal
```

GitHub 发布包不包含本机私钥。用临时签名包覆盖固定签名包，会改变应用签名身份，可能需要重新授权。

### 运行测试

```bash
swift test
bash Tests/local_signing.sh
bash Tests/universal_build.sh

# 已配置固定签名并生成 arm64 应用包后，可验证签名身份稳定性
bash Tests/signing_identity.sh
```

Swift 测试包含快捷键、冻结与裁剪、首次点击、撤销重做、主题、布局和文字对比度检查；部分测试需要 macOS 图形会话。使用完整 Xcode 时，可通过 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 指定工具路径。

## 项目结构

| 路径 | 内容 |
| --- | --- |
| `Sources/SnapX/` | macOS 应用、截图流程、编辑器、菜单栏和设置 |
| `Tests/` | Swift 回归测试与构建、签名脚本检查 |
| `Scripts/` | 构建、本机签名、安装及辅助工具 |
| `Packaging/` | 应用元数据、图标、音效和安装说明 |
| `release/` | 各版本发布说明 |
| `.github/workflows/` | 测试、构建和发布流程 |
| `Windows/` | Windows 适配工程 |

## 发布流程

更新 `Packaging/SnapX-Info.plist` 的版本号，并新增 `release/v版本号/RELEASE.md`。将修改推送到 `main` 后，GitHub Actions 会执行测试，生成三种架构的 DMG／ZIP，并创建对应标签和 Release。工作流也支持推送版本标签或手动运行。

如果目标版本标签已存在且指向不同提交，发布会停止；请提升版本号后再发布。

## 反馈与贡献

欢迎通过 [Issues](https://github.com/FOREST227/SnapX/issues) 反馈问题。请附上 macOS 版本、芯片类型、SnapX 版本、复现步骤，以及使用的截图方式。界面或显示问题可补充截图；分享前请遮挡私人信息。

提交代码前请运行相关测试，并尽量让每个改动聚焦一个问题。

## 许可证

原项目说明标注为 MIT；当前仓库尚未附带独立的 `LICENSE` 文件。
