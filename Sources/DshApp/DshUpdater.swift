import Foundation

struct DshUpdateInfo: Equatable, Sendable {
    let current: String
    let latest: String
    let registry: URL
}

enum DshUpdater {
    static let packageName = "@deepseek-ai/dsh"

    static func latestRelease(current: String?) async -> DshUpdateInfo? {
        let currentVersion = current?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let latest = await fetchLatest() else { return nil }
        guard let currentVersion, !currentVersion.isEmpty else {
            return DshUpdateInfo(current: "未知", latest: latest.version, registry: latest.registry)
        }
        guard latest.version != currentVersion else { return nil }
        return DshUpdateInfo(current: currentVersion, latest: latest.version, registry: latest.registry)
    }

    static func fetchLatestVersion() async -> String? {
        await fetchLatest()?.version
    }

    private static func fetchLatest() async -> (version: String, registry: URL)? {
        for registry in await registries() {
            guard let url = latestURL(for: registry) else { continue }
            do {
                var request = URLRequest(url: url, timeoutInterval: 8)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                    continue
                }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let version = json["version"] as? String,
                   !version.isEmpty {
                    DshLog.append("[update] \(packageName)@\(version) from \(registry.absoluteString)\n")
                    return (version, registry)
                }
            } catch {
                DshLog.append("[update] \(registry.absoluteString) failed: \(error.localizedDescription)\n")
            }
        }
        return nil
    }

    private static func registries() async -> [URL] {
        var urls: [URL] = []
        if let configured = await Task.detached(operation: { npmConfiguredRegistry() }).value {
            urls.append(configured)
        }
        urls.append(contentsOf: [
            URL(string: "https://registry.npmmirror.com")!,
            URL(string: "https://registry.npmjs.org")!,
        ])

        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private static func npmConfiguredRegistry() -> URL? {
        guard let npm = DshResolver.findNpm() else { return nil }

        let process = Process()
        process.executableURL = npm
        process.arguments = ["config", "get", "registry"]
        process.environment = ShellPath.processEnvironment()
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

        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return URL(string: text)
    }

    private static func latestURL(for registry: URL) -> URL? {
        var base = registry.absoluteString
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return URL(string: "\(base)/@deepseek-ai/dsh/latest")
    }
}
