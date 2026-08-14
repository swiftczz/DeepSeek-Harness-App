import Foundation

struct DshLaunchPlan: Sendable {
    let nodeURL: URL
    let entryURL: URL
    let version: String?
}

enum PackageInstaller: Sendable {
    case bun(URL)
    case npm(URL)

    var name: String {
        switch self {
        case .bun: "bun"
        case .npm: "npm"
        }
    }

    var executable: URL {
        switch self {
        case .bun(let url), .npm(let url): url
        }
    }
}

enum DshResolver {
    static func findNode() throws -> URL {
        if let node = ShellPath.findExecutable("node") {
            return node
        }
        throw DshError.missingNode
    }

    static func findNpm() -> URL? {
        ShellPath.findExecutable("npm")
    }

    static func findBun() -> URL? {
        ShellPath.findExecutable("bun")
    }

    static func findInstaller() throws -> PackageInstaller {
        if let bun = findBun() {
            return .bun(bun)
        }
        if let npm = findNpm() {
            return .npm(npm)
        }
        throw DshError.missingInstaller
    }

    static var hasManagedRuntime: Bool {
        let fm = FileManager.default
        return fm.isReadableFile(atPath: AppPaths.managedEntry.path)
            && fm.isReadableFile(atPath: AppPaths.managedReadyStamp.path)
    }

    static var hasIncompleteRuntime: Bool {
        FileManager.default.fileExists(atPath: AppPaths.managedRuntimeDirectory.path)
            && !hasManagedRuntime
    }

    static func markRuntimeReady() {
        let stamp = AppPaths.managedReadyStamp
        try? FileManager.default.createDirectory(
            at: stamp.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? "ok\n".write(to: stamp, atomically: true, encoding: .utf8)
    }

    static func clearRuntimeReady() {
        try? FileManager.default.removeItem(at: AppPaths.managedReadyStamp)
    }

    static func removeIncompleteRuntime() throws {
        guard !hasManagedRuntime else { return }
        let url = AppPaths.managedRuntimeDirectory
        if FileManager.default.fileExists(atPath: url.path) {
            DshLog.append("[install] removing incomplete runtime at \(url.path)\n")
            try FileManager.default.removeItem(at: url)
        }
    }

    static func resolveLaunchPlan() throws -> DshLaunchPlan? {
        let node = try findNode()
        guard hasManagedRuntime else {
            return nil
        }
        return DshLaunchPlan(
            nodeURL: node,
            entryURL: AppPaths.managedEntry,
            version: readVersion(at: AppPaths.managedEntry)
        )
    }

    static func readVersion(at entry: URL) -> String? {
        let packageJSON = entry.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("package.json")
        guard
            let data = try? Data(contentsOf: packageJSON),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = json["version"] as? String
        else {
            return nil
        }
        return version
    }
}
