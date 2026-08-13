import Foundation

enum AppPaths {
    static let appName = "DeepSeek Harness"

    static var supportDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent(appName, isDirectory: true)
    }

    static var managedRuntimeDirectory: URL {
        supportDirectory.appendingPathComponent("runtime", isDirectory: true)
    }

    static var managedEntry: URL {
        managedRuntimeDirectory
            .appendingPathComponent("node_modules/@deepseek-ai/dsh/lib/bin.js")
    }

    static var logDirectory: URL {
        let root = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return root.appendingPathComponent("Logs/\(appName)", isDirectory: true)
    }

    static var logFile: URL {
        logDirectory.appendingPathComponent("dsh.log")
    }
}

enum DshLog {
    private static let queue = DispatchQueue(label: "ai.deepseek.dsh.desktop.swift.log")
    nonisolated(unsafe) private static var handle: FileHandle?

    static func prepare() {
        queue.sync {
            let fm = FileManager.default
            try? fm.createDirectory(at: AppPaths.logDirectory, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: AppPaths.logFile.path) {
                fm.createFile(atPath: AppPaths.logFile.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: AppPaths.logFile)
            _ = try? handle?.seekToEnd()
        }
    }

    static func append(_ text: String) {
        queue.async {
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)"
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
}
