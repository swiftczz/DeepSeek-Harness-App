# DeepSeek Harness

用 SwiftUI `WebView` 封装 `dsh web` 的 macOS 薄壳。工程用 Swift Package Manager 管理。

[![Release](https://img.shields.io/github/v/release/swiftczz/DeepSeek-Harness-App?label=release)](https://github.com/swiftczz/DeepSeek-Harness-App/releases/latest)
![Platform](https://img.shields.io/badge/macOS-26.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)

安装包里只有原生应用，不内置 Chromium，也不把 DSH 打进 `.app`。启动后由本机 Node 运行 `@deepseek-ai/dsh`，再把本地页面嵌进窗口。

## 启动流程

1. 在常见路径（Homebrew、nvm、fnm、volta、asdf、nodenv）以及登录 shell 的 PATH 里查找 Node
2. 只使用 `~/.dshapp/runtime` 里的 DSH，不读取 PATH 上的 `dsh`，也不用全局 npm 包
3. 若还没有（或上次安装中断），优先用本机 bun（没有则用 npm）把 `@deepseek-ai/dsh` 装到该目录，大约三百兆；中断留下的不完整文件会先清空再重下。源跟系统 `npm config get registry` 一致，这个源不通才改试 npmmirror / npmjs。运行仍使用 Node。
4. 执行 `node --expose-internals <入口> web --host 127.0.0.1 --port 0`
5. 从进程输出解析 `dsh web: http://127.0.0.1:<端口>`，在窗口中打开
6. 退出时结束 dsh 进程组

以前装在 `~/.deepseek-harness`、`~/.DeepSeek Harness/runtime` 或 `~/Library/Application Support/DeepSeek Harness/runtime` 的副本，启动时会自动迁到新目录。

会话导出和带 `Content-Disposition: attachment` 的下载会存到 `~/Downloads`，并在 Finder 中显示。

## 安装

1. 前往 [Releases](https://github.com/swiftczz/DeepSeek-Harness-App/releases/latest)，下载适合当前 Mac 架构的 DMG，或选择 universal 通用版本。
2. 打开 DMG，将 `DeepSeek Harness.app` 拖入“应用程序”。
3. 首次启动时右键应用并选择“打开”。

发布包使用 Ad-hoc 签名。如果 Gatekeeper 仍然阻止启动，可执行：

```bash
xattr -dr com.apple.quarantine "/Applications/DeepSeek Harness.app"
```

## 环境要求

运行：

- macOS 26.0 或更高版本
- Node.js 22+（本机已安装即可；从 Dock 启动时应用会自己补上 Homebrew / nvm / bun 等 PATH）
- bun（可选；有则优先用来安装 DSH，没有则用 npm）

构建：

- Xcode 26+ / Swift 6.2+

## 从源码构建

```bash
./scripts/build.sh
open "dist/DeepSeek Harness.app"
```

### 构建发布 DMG

```bash
APP_VERSION=0.1.0 ./scripts/build.sh --build-only universal --sign --dmg
APP_VERSION=0.1.0 ./scripts/build.sh --build-only arm64     --sign --dmg
APP_VERSION=0.1.0 ./scripts/build.sh --build-only x86_64    --sign --dmg
```

- `--build-only <arch>`：使用 release 配置构建 `universal`、`arm64` 或 `x86_64`
- `--sign`：为应用添加 Ad-hoc 签名（含 entitlements）
- `--dmg`：在 `dist/` 生成 `DeepSeek-Harness-<arch>-<version>.dmg`
- `APP_VERSION`：写入 `Info.plist` 和 DMG 文件名；如果省略，则依次使用最新 Git 标签、`Packaging/Info.plist` 里的版本，或 `0.0.0-dev`

推送 `v*` 标签会触发 [Release](.github/workflows/release.yml) workflow：打三种架构的 DMG，按 Conventional Commits 生成 changelog，并上传到 GitHub Release。在 Actions 里手动运行则只上传 artifact，不创建 Release。

## 更新 DSH

菜单 **DeepSeek Harness → 检查 DSH 更新…**（⇧⌘U）会按本机 `npm config get registry` 查询；这个源不通再试 npmmirror / npmjs。这里更新的是本地 `@deepseek-ai/dsh`，不是桌面应用本身。

启动后也会在后台检查；有新版本时弹出系统对话框。点 **更新** 会装到 `~/.dshapp/runtime` 并重启本地服务，不必重装本应用。点 **稍后** 会跳过该版本。运行中每 6 小时再查一次。

同菜单里还有 **打开日志** 和 **打开 npm 缓存**。

## 数据目录

```text
~/.dshapp/runtime      # 本地 DSH
~/.dshapp/npm-cache    # 安装过程中的下载缓存；成功后会清掉 _cacache，失败时可手动删除后重试
~/Library/Logs/DeepSeek Harness/dsh.log
```

## 技术栈

- **SwiftUI** — 窗口、菜单和启动界面
- **WebKit** — 嵌入本地 `dsh web`
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
