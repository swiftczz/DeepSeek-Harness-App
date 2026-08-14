import Foundation

enum AppPaths {
    static let appName = "DeepSeek Harness"
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

    static var logDirectory: URL {
        let root = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return root.appendingPathComponent("Logs/\(appName)", isDirectory: true)
    }

    static var logFile: URL {
        logDirectory.appendingPathComponent("dsh.log")
    }

    private static var previousHomeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".deepseek-harness", isDirectory: true)
    }

    private static var legacyRuntimeDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
        return [
            previousHomeDirectory.appendingPathComponent("runtime", isDirectory: true),
            home.appendingPathComponent(".DeepSeek Harness", isDirectory: true)
                .appendingPathComponent("runtime", isDirectory: true),
            appSupport.appendingPathComponent(appName, isDirectory: true)
                .appendingPathComponent("runtime", isDirectory: true),
        ]
    }

    static func migrateLegacyRuntimeIfNeeded() {
        migratePreviousHomeIfNeeded()

        let fm = FileManager.default
        if fm.isReadableFile(atPath: managedEntry.path) {
            return
        }

        for legacy in legacyRuntimeDirectories {
            let legacyEntry = legacy.appendingPathComponent("node_modules/@deepseek-ai/dsh/lib/bin.js")
            guard fm.isReadableFile(atPath: legacyEntry.path) else {
                continue
            }

            do {
                try fm.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
                if fm.fileExists(atPath: managedRuntimeDirectory.path) {
                    try fm.removeItem(at: managedRuntimeDirectory)
                }
                try fm.moveItem(at: legacy, to: managedRuntimeDirectory)
                DshLog.append("[runtime] migrated \(legacy.path) -> \(managedRuntimeDirectory.path)\n")
                removeEmptyParentIfNeeded(legacy.deletingLastPathComponent())
            } catch {
                DshLog.append("[runtime] migrate failed: \(error.localizedDescription)\n")
            }
            return
        }
    }

    private static func migratePreviousHomeIfNeeded() {
        let fm = FileManager.default
        let previous = previousHomeDirectory
        guard fm.fileExists(atPath: previous.path) else { return }
        guard !fm.fileExists(atPath: homeDirectory.path) else { return }
        do {
            try fm.moveItem(at: previous, to: homeDirectory)
            DshLog.append("[runtime] migrated \(previous.path) -> \(homeDirectory.path)\n")
        } catch {
            DshLog.append("[runtime] migrate home failed: \(error.localizedDescription)\n")
        }
    }

    private static func removeEmptyParentIfNeeded(_ directory: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: directory.path), items.isEmpty else {
            return
        }
        try? fm.removeItem(at: directory)
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
