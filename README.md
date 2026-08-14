# DeepSeek Harness

DeepSeek 编码 Agent 的 macOS 应用。装好后打开就能用。

[![Release](https://img.shields.io/github/v/release/swiftczz/DeepSeek-Harness-App?label=release)](https://github.com/swiftczz/DeepSeek-Harness-App/releases/latest)
![Platform](https://img.shields.io/badge/macOS-26.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)

本机需要 Node.js 22+。应用会在本地运行 `@deepseek-ai/dsh`，把界面开在原生窗口里。安装包不内置 Chromium，也不把 DSH 打进 `.app`。

## 安装

1. 前往 [Releases](https://github.com/swiftczz/DeepSeek-Harness-App/releases/latest)，下载适合当前 Mac 架构的 DMG，或选择 universal 通用版本。
2. 打开 DMG，将 `DeepSeek Harness.app` 拖入「应用程序」。
3. 第一次启动请右键应用，选择「打开」。

发布包使用 Ad-hoc 签名。如果系统仍然拦住，可执行：

```bash
xattr -dr com.apple.quarantine "/Applications/DeepSeek Harness.app"
```

第一次打开时，如果本机还没有 DSH，应用会自动下载（大约三百兆）。之后再开就是窗口本身。会话导出和浏览器下载会存到 `~/Downloads`。

## 环境要求

运行：

- macOS 26.0 或更高版本
- Node.js 22+（Homebrew、nvm、fnm、volta 等装的都可以；从 Dock 启动也能找到）

构建：

- Xcode 26+ / Swift 6.2+

## 更新 DSH

菜单 **DeepSeek Harness → 检查 DSH 更新…**（⇧⌘U）检查的是本地 DSH，不是这个桌面应用。点 **更新** 会装好并重启服务，不必重装本应用。点 **稍后** 会跳过该版本。启动后也会在后台检查。

同菜单里还有 **打开日志** 和 **打开 npm 缓存**。

## 数据目录

```text
~/.dshapp/runtime      # 本地 DSH
~/.dshapp/npm-cache    # 安装过程中的下载缓存；成功后会清掉，失败时可手动删除后重试
~/.dshapp/dsh.log
```

## 从源码构建

```bash
./scripts/build.sh
open "dist/DeepSeek Harness.app"
```

### 构建发布 DMG

```bash
./scripts/build.sh --build-only universal --sign --dmg
./scripts/build.sh --build-only arm64     --sign --dmg
./scripts/build.sh --build-only x86_64    --sign --dmg
```

- `--build-only <arch>`：使用 release 配置构建 `universal`、`arm64` 或 `x86_64`
- `--sign`：为应用添加 Ad-hoc 签名（含 entitlements）
- `--dmg`：在 `dist/` 生成 `DeepSeek-Harness-<arch>-<version>.dmg`
- `APP_VERSION`：写入 `Info.plist` 和 DMG 文件名；如果省略，则依次使用最新 Git 标签、`Packaging/Info.plist` 里的版本，或 `0.0.0-dev`

推送 `v*` 标签会触发 [Release](.github/workflows/release.yml) workflow：打三种架构的 DMG，按 Conventional Commits 生成 changelog，并上传到 GitHub Release。在 Actions 里手动运行则只上传 artifact，不创建 Release。

## 技术栈

- **SwiftUI** — 窗口、菜单和启动界面
- **WebKit** — 嵌入本地 DSH 页面
- **Observation** — 应用共享状态
- **Swift Package Manager** — 构建和依赖管理

## 项目结构

```text
DeepSeek-Harness/
├── .github/workflows/      # 发布自动化
├── Packaging/              # Info.plist、图标、entitlements
├── scripts/                # 构建、打包和 changelog
├── Sources/DshApp/         # 应用入口、启动、更新和 WebView
├── Package.swift
└── README.md
```
