# 开发与构建

[返回项目首页](../README.md)

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

## 许可说明

原项目说明标注为 MIT；当前仓库尚未附带独立的 `LICENSE` 文件。
