import Foundation

enum ShellPath {
    static func augmentedPATH() -> String {
        var parts: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        parts.append(contentsOf: extraDirectories(home: home))
        parts.append(contentsOf: (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init))
        parts.append(contentsOf: [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(home)/.local/bin",
            "\(home)/.volta/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ])

        var seen = Set<String>()
        return parts.filter { seen.insert($0).inserted && !$0.isEmpty }.joined(separator: ":")
    }

    static func findExecutable(_ name: String) -> URL? {
        let path = augmentedPATH()
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.resolvingSymlinksInPath()
            }
        }
        return loginShellWhich(name)
    }

    static func processEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmentedPATH()
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env
    }

    private static func extraDirectories(home: String) -> [String] {
        var directories: [String] = []
        let fm = FileManager.default

        let nvmRoot = ProcessInfo.processInfo.environment["NVM_DIR"] ?? "\(home)/.nvm"
        let versions = URL(fileURLWithPath: nvmRoot).appendingPathComponent("versions/node")
        if let names = try? fm.contentsOfDirectory(atPath: versions.path) {
            for name in names.sorted(by: >) {
                directories.append(versions.appendingPathComponent("\(name)/bin").path)
            }
        }

        directories.append(contentsOf: [
            "\(home)/.local/share/fnm/aliases/default/bin",
            "\(home)/Library/Application Support/fnm/aliases/default/bin",
            "\(home)/.fnm/aliases/default/bin",
            "\(home)/.asdf/shims",
            "\(home)/.nodenv/shims",
        ])

        return directories.filter { fm.fileExists(atPath: $0) }
    }

    private static func loginShellWhich(_ name: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "command -v \(name)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, FileManager.default.isExecutableFile(atPath: text) else {
            return nil
        }
        return URL(fileURLWithPath: text).resolvingSymlinksInPath()
    }
}
