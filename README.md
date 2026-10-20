<p align="center">
  <img src="Packaging/AppIcon-master.png" width="96" alt="SnapX 应用图标">
</p>

<h1 align="center">SnapX</h1>

<p align="center">截下来，标清楚，随手贴到需要的地方。</p>

<p align="center">
  <a href="https://github.com/FOREST227/SnapX/releases/latest"><img src="https://img.shields.io/github/v/release/FOREST227/SnapX" alt="最新版本"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-blue" alt="支持 macOS 13 及更新版本">
</p>

<p align="center">
  <a href="https://github.com/FOREST227/SnapX/releases/latest"><strong>下载 SnapX</strong></a> ·
  <a href="release/v0.2.0/RELEASE.md">看看这次更新了什么</a> ·
  <a href="https://github.com/FOREST227/SnapX/issues">反馈问题</a>
</p>

SnapX 是一款常驻 Mac 菜单栏的截图工具。框选之后直接在原位画框、加箭头、写说明，再复制、保存或钉在桌面上。不必为了标注一张图，再打开另一个编辑器。

<img src="docs/images/editor-preview.png" width="880" alt="SnapX 编辑器示例：在截图上添加红色线框和箭头，下方工具栏提供标注、OCR、保存、钉图和复制操作">

*编辑界面预览，图中为演示内容。*

## 你可以用它做什么

- **🎯 截取需要的内容**：拖动框选、单击高亮窗口，或选择整块屏幕。多屏也能指定目标显示器。
- **✍️ 把重点讲清楚**：线框、高亮、文字、箭头、直线、画笔和马赛克，支持标注撤销与重做。
- **📌 留在眼前对照**：把图片钉在桌面上，调整透明度或开启鼠标穿透，方便边看边写。
- **🔤 从图片里取文字**：识别简体中文、繁体中文和英文，将结果复制出来。

截图完成后还可以保存为 PNG，或在历史记录中找回最近的截图。

## 下载与安装

前往 **[下载页面](https://github.com/FOREST227/SnapX/releases/latest)**，按你的 Mac 选择安装包：

| 你的 Mac | 选择的文件 |
| --- | --- |
| M 系列芯片 | 名称中带 `arm64` |
| Intel 芯片 | 名称中带 `x86_64` |
| 不确定，或希望两种 Mac 都能使用 | 名称中带 `universal` |

建议下载 **DMG**，打开后将 `SnapX.app` 拖入“应用程序”文件夹。也提供 ZIP，解压后移动应用即可。需要 macOS 13（Ventura）或更新版本。

首次启动时，请按提示配置**屏幕录制**和**辅助功能**权限。应用启动后会出现在菜单栏。

> 安装包尚未经过 Apple 公证。如果系统提示无法验证开发者，请确认文件来自本仓库的下载页面，再到“系统设置 → 隐私与安全性”中允许打开。

## 第一次截图，只需三步

1. 按 **⌘⇧S**，或点击菜单栏里的“框选截图”。
2. **拖动鼠标**选一块区域，或**单击高亮窗口**选取它在当前屏幕上的可见部分。
3. 按需要添加标注，再按 **Enter** 或点击 **✓** 复制；也可以点击保存、钉图或提取文字。

建议先调整截图范围，再添加标注。重新裁剪会清空当前标注，裁剪操作暂不支持撤销。

## 选择适合你的截图时机

**想抓住一个菜单、弹窗或瞬间画面？**

选择 **「触发时冻结」**：按下快捷键就保存画面，你可以慢慢框选。

**想先看着实时画面确定范围？**

选择 **「选区确认时冻结」**：松开鼠标完成框选，或单击确认窗口时，才固定画面。

进入编辑后，选区、背景和再次调整范围都使用同一张图，最后保存时不会重新截屏。这里的“冻结”不会暂停其他应用。

<details>
<summary>查看截图方式与快捷键设置</summary>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark.png">
  <img src="docs/images/settings-light.png" width="320" alt="SnapX 设置界面：选择冻结时机，并为框选截图、全屏截图和截图历史录入快捷键">
</picture>

支持跟随系统、浅色和深色外观。快捷键、登录时启动和权限入口都可以在设置中找到。

</details>

## 记住这几个快捷键就够了

| 操作 | 默认快捷键 |
| --- | --- |
| 框选截图 | **⌘⇧S** |
| 全屏截图 | **⌘⇧F** |
| 打开截图历史 | **⌘⇧H** |
| 撤销一条标注 | **⌘Z** |
| 重做标注 | **⌘Y** 或 **⇧⌘Z** |
| 完成并复制 | **Enter** |
| 取消当前操作／退出编辑 | **Esc** |

编辑时按 `1`–`7` 可以切换七种标注工具。正在输入文字时，部分按键由文字编辑器处理。

全局快捷键可以自定义：打开设置，点击按键框，再按下想要的组合键。录入期间全局快捷键暂停，按 `Esc` 取消；发生冲突时会提示原因并保留原设置。

## 用起来更顺手的小功能

**图片钉在桌面上**

钉图支持 25%–100% 透明度和鼠标穿透，也能从菜单栏一键关闭所有钉图。适合对照参考图、操作步骤或资料。

**最近的截图还能找回来**

历史记录最多保留 50 张截图，支持预览、多选和右键操作。

**随 Mac 登录自动启动**

在设置中开启“登录时启动”，需要时按 macOS 提示批准登录项。

## 常见问题

<details>
<summary>快捷键按了没反应，怎么办？</summary>

先确认 SnapX 正在运行，再到设置中检查权限状态和快捷键是否保存成功。尝试换一个不与其他应用冲突的组合键；含 ⌘ 的全局快捷键可能需要辅助功能权限。授权后如果系统要求重启应用，请退出后重新打开。

</details>

<details>
<summary>截图后怎么保存成文件？</summary>

点击编辑工具栏中的保存按钮。图片会以 PNG 格式保存到下载文件夹，并按时间命名。按 Enter 或点击 ✓ 则会复制到剪贴板。

</details>

<details>
<summary>如何更新到新版本？</summary>

从 v0.2.0 起，SnapX 不再内置自动更新。点击菜单中的“GitHub 发布页”，下载新版；保存当前工作并退出旧版后，再替换“应用程序”里的 SnapX。

不同签名身份之间切换，可能需要重新授予权限。如果你经常自己编译，可以使用[固定本机签名](docs/DEVELOPMENT.md#本机长期使用固定签名)。

</details>

<details>
<summary>支持 Windows 吗？</summary>

当前完整应用仅支持 macOS。Windows 版仍在适配中，仓库中的 Windows 工程尚未与 macOS 版功能对等，进展见 [Windows 说明](Windows/README.md)。

</details>

## 反馈与参与

遇到问题或有改进想法，欢迎[提交反馈](https://github.com/FOREST227/SnapX/issues)。附上 macOS 版本、芯片类型、SnapX 版本和复现步骤，会更容易定位；如附截图，请先遮挡私人信息。

<details>
<summary>我想从源码构建或参与开发</summary>

需要 Swift 6.2+ 和 macOS SDK，建议使用完整 Xcode。macOS 主程序没有第三方包依赖。

完整的构建、固定签名、测试、项目结构和发布流程，请看 **[开发文档](docs/DEVELOPMENT.md)**。

</details>
