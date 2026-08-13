import Foundation

enum DshError: LocalizedError {
    case missingNode
    case missingNpm
    case missingEntry
    case spawnFailed(String)
    case timedOut
    case exited(Int32)
    case installFailed(Int32, String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .missingNode:
            return "没有找到 Node.js。请先安装 Node 22+（例如 brew install node），或确保 /opt/homebrew/bin 可用。"
        case .missingNpm:
            return "没有找到 npm，无法自动安装 DSH。"
        case .missingEntry:
            return "没有找到 DSH 入口文件。"
        case .spawnFailed(let message):
            return "DSH 启动失败：\(message)"
        case .timedOut:
            return "等待 DSH 启动超时。请查看应用日志。"
        case .exited(let code):
            return "DSH 意外退出（状态码 \(code)）。请查看应用日志。"
        case .installFailed(let code, let output):
            let snippet = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = snippet.isEmpty ? "" : "\n\(snippet.suffix(400))"
            return "安装 DSH 失败（状态码 \(code)）。\(suffix)"
        case .invalidURL:
            return "DSH 没有返回有效的本地地址。"
        }
    }
}
