import Foundation

enum AppPaths {
    static let runtimeHomeName = ".dshapp"

    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(runtimeHomeName, isDirectory: true)
    }

    static var runtimeDisplayPath: String {
        "~/\(runtimeHomeName)/runtime"
    }

    static var managedRuntimeDirectory: URL {
        homeDirectory.appendingPathComponent("runtime", isDirectory: true)
    }

    static var managedEntry: URL {
        managedRuntimeDirectory
            .appendingPathComponent("node_modules/@deepseek-ai/dsh/lib/bin.js")
    }

    static var managedReadyStamp: URL {
        managedRuntimeDirectory.appendingPathComponent(".dsh-ready")
    }

    static var npmCacheDirectory: URL {
        homeDirectory.appendingPathComponent("npm-cache", isDirectory: true)
    }

    static var npmCacheDisplayPath: String {
        "~/\(runtimeHomeName)/npm-cache"
    }

    static func clearInstallCache() {
        let url = npmCacheDirectory
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        DshLog.append("[install] clearing \(url.path)\n")
        try? FileManager.default.removeItem(at: url)
    }

    static func revealDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.path]
        try? process.run()
    }

    static var logFile: URL {
        homeDirectory.appendingPathComponent("dsh.log")
    }
}

enum DshLog {
    private static let queue = DispatchQueue(label: "ai.deepseek.dsh.desktop.swift.log")
    nonisolated(unsafe) private static let timestamp = ISO8601DateFormatter()
    private static let maxBytes: UInt64 = 2 * 1024 * 1024
    private static let keptBytes: UInt64 = 1024 * 1024
    nonisolated(unsafe) private static var handle: FileHandle?

    static func prepare() {
        queue.sync {
            try? handle?.close()
            handle = nil
            let fm = FileManager.default
            try? fm.createDirectory(
                at: AppPaths.logFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !fm.fileExists(atPath: AppPaths.logFile.path) {
                fm.createFile(atPath: AppPaths.logFile.path, contents: nil)
            }
            trimIfNeeded()
            handle = try? FileHandle(forWritingTo: AppPaths.logFile)
            _ = try? handle?.seekToEnd()
        }
    }

    static func append(_ text: String) {
        queue.async {
            let line = "\(timestamp.string(from: Date())) \(text)"
            fputs(line, stderr)
            if let data = line.data(using: .utf8) {
                try? handle?.write(contentsOf: data)
            }
        }
    }

    static func revealInFinder() {
        prepare()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-R", AppPaths.logFile.path]
        try? process.run()
    }

    private static func trimIfNeeded() {
        let url = AppPaths.logFile
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
              size.uint64Value > maxBytes,
              let reader = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? reader.close() }
        let total = (try? reader.seekToEnd()) ?? 0
        guard total > keptBytes else { return }
        try? reader.seek(toOffset: total - keptBytes)
        guard var data = try? reader.readToEnd(), !data.isEmpty else { return }
        if let newline = data.firstIndex(of: UInt8(ascii: "\n")), newline + 1 < data.count {
            data = Data(data[(newline + 1)...])
        }
        var kept = Data("# log trimmed\n".utf8)
        kept.append(data)
        try? kept.write(to: url, options: .atomic)
    }
}

enum AppHTTP {
    static let session = URLSession(configuration: .ephemeral)
}
