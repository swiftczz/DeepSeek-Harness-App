import SwiftUI

struct InstallProgressScreen: View {
    var status: String
    var detail: DshInstallProgress
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 18) {
            WhaleGlyph(size: 88, colorScheme: colorScheme)

            Text(isUpdate ? "正在更新 DSH" : isRepair ? "正在重新安装 DSH" : "正在安装 DSH")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)

            Text(isUpdate
                 ? "新版本会安装到 \(AppPaths.runtimeDisplayPath)，完成后自动启动。"
                 : isRepair
                 ? "上次安装被中断，会清空不完整文件后重新下载，大约三百兆。"
                 : "首次启动需要下载运行时，大约三百兆，会安装到 \(AppPaths.runtimeDisplayPath)。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            progressSection
                .padding(.top, 8)

            detailSection

            NpmCacheHint()
                .padding(.top, 4)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(canvas)
    }

    @ViewBuilder
    private var progressSection: some View {
        if let fraction = detail.fraction {
            VStack(spacing: 8) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 280)
                Text("\(formattedMB(detail.bytes)) / 约 350 MB")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            ProgressView()
                .controlSize(.regular)
        }
    }

    private var detailSection: some View {
        VStack(spacing: 6) {
            if let banner = switchBanner {
                Text(banner)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(detail.stage.isEmpty ? "正在准备…" : detail.stage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if !detail.host.isEmpty {
                Text(detail.host)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if hasCounts {
                Text("已解析 \(detail.resolvedCount)  ·  下载 \(detail.downloadedCount)  ·  缓存 \(detail.cachedCount)")
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            if !packages.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(packages.enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: 420, alignment: .center)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 480)
    }

    private var packages: [String] {
        if !detail.recentPackages.isEmpty {
            return detail.recentPackages
        }
        if detail.packageName.isEmpty {
            return []
        }
        return [detail.packageName]
    }

    private var hasCounts: Bool {
        detail.resolvedCount + detail.downloadedCount + detail.cachedCount > 0
    }

    private var switchBanner: String? {
        let line = status
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty } ?? ""
        guard line.contains("改用") else { return nil }
        return line
    }

    private func formattedMB(_ bytes: Int64) -> String {
        "\(Int((Double(bytes) / 1_048_576).rounded())) MB"
    }

    private var isUpdate: Bool {
        status.contains("更新") && !status.contains("重新安装")
    }

    private var isRepair: Bool {
        status.contains("未完成") || status.contains("重新安装")
    }

    private var canvas: Color {
        AppCanvas.fill(colorScheme)
    }
}

struct StatusScreen: View {
    var message: String?
    var isError = false
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "sparkle")
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isError ? Color.red : Color.accentColor)

            Text("DeepSeek Harness")
                .font(.system(size: 25, weight: .semibold))
                .tracking(-0.4)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(isError ? Color.red.opacity(0.9) : Color.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .textSelection(.enabled)
            }

            if isError {
                Button("重试") {
                    onRetry?()
                }
                .keyboardShortcut(.defaultAction)

                if showsCacheHint {
                    NpmCacheHint(footnote: "安装异常时可删除该目录后重试")
                        .padding(.top, 4)
                }
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var showsCacheHint: Bool {
        guard let message else { return true }
        return !message.contains("Node.js") && !message.contains("bun 或 npm")
    }
}

private struct NpmCacheHint: View {
    var footnote: String?

    var body: some View {
        VStack(spacing: 6) {
            Text("缓存 \(AppPaths.npmCacheDisplayPath)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Button("在 Finder 中显示") {
                AppPaths.revealDirectory(AppPaths.npmCacheDirectory)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}
