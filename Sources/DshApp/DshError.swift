import Foundation

enum DshError: LocalizedError {
    case missingNode
    case missingInstaller
    case missingEntry
    case spawnFailed(String)
    case timedOut
    case exited(Int32)
    case installFailed(Int32, String)
    case installStalled(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .missingNode:
            return "没有找到 Node.js。运行和安装 DSH 都至少需要 Node 22+。\n\nbrew install node"
        case .missingInstaller:
            return "没有找到 bun 或 npm，无法下载 DSH。Node 已安装的话，一般会自带 npm；也可以再装 bun：\n\nbrew install bun"
        case .missingEntry:
            return "没有找到 DSH 入口文件。"
        case .spawnFailed(let message):
            return "DSH 启动失败：\(message)"
        case .timedOut:
            return "等待 DSH 启动超时。请查看应用日志。"
        case .exited(let code):
            return "DSH 意外退出（状态码 \(code)）。请查看应用日志。"
        case .installFailed(let code, let output):
            if code == 15 || code == -15 || code == -1 {
                return "安装 DSH 超时，下载中断。请检查网络后重试。"
            }
            let snippet = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = snippet.isEmpty ? "" : "\n\(snippet.suffix(400))"
            return "安装 DSH 失败（状态码 \(code)）。\(suffix)"
        case .installStalled(let host):
            return "连接 \(host) 超时，没有持续下载进度。"
        case .invalidURL:
            return "DSH 没有返回有效的本地地址。"
        }
    }
}
