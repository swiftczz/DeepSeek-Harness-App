import Foundation

enum NpmRegistry {
    static let npmmirror = URL(string: "https://registry.npmmirror.com")!
    static let npmjs = URL(string: "https://registry.npmjs.org")!

    /// System `npm config` registry first, then npmmirror, then npmjs.
    static func candidates() async -> [URL] {
        var urls: [URL] = []
        if let configured = await Task.detached(operation: { npmConfiguredRegistry() }).value {
            urls.append(configured)
        }
        urls.append(contentsOf: [npmmirror, npmjs])

        var seen = Set<String>()
        return urls.compactMap { normalized($0) }.filter { seen.insert($0.absoluteString).inserted }
    }

    static func host(_ registry: URL) -> String {
        registry.host ?? registry.absoluteString
    }

    private static func normalized(_ url: URL) -> URL? {
        var text = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") {
            text.removeLast()
        }
        return URL(string: text)
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
        guard process.wait(timeout: 3) else {
            return nil
        }

        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return URL(string: text)
    }
}
