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

    private static func fetchLatest() async -> (version: String, registry: URL)? {
        for registry in await NpmRegistry.candidates() {
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

    private static func latestURL(for registry: URL) -> URL? {
        var base = registry.absoluteString
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return URL(string: "\(base)/@deepseek-ai/dsh/latest")
    }
}
