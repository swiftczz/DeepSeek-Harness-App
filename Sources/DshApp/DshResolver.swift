import Foundation

struct DshLaunchPlan: Sendable {
    enum Source: String, Sendable {
        case managed
        case path
        case globalNpm
    }

    let nodeURL: URL
    let entryURL: URL
    let source: Source
    let version: String?
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

    static func resolveLaunchPlan(preferManaged: Bool = false) throws -> DshLaunchPlan? {
        let node = try findNode()
        let fm = FileManager.default

        if preferManaged || fm.isReadableFile(atPath: AppPaths.managedEntry.path) {
            if fm.isReadableFile(atPath: AppPaths.managedEntry.path) {
                return DshLaunchPlan(
                    nodeURL: node,
                    entryURL: AppPaths.managedEntry,
                    source: .managed,
                    version: readVersion(at: AppPaths.managedEntry)
                )
            }
            if preferManaged {
                return nil
            }
        }

        if let dsh = ShellPath.findExecutable("dsh") {
            return DshLaunchPlan(
                nodeURL: node,
                entryURL: dsh,
                source: .path,
                version: readVersion(at: dsh)
            )
        }

        if let npm = findNpm(),
           let globalRoot = npmPrefixRoot(npm: npm) {
            let entry = globalRoot.appendingPathComponent("@deepseek-ai/dsh/lib/bin.js")
            if fm.isReadableFile(atPath: entry.path) {
                return DshLaunchPlan(
                    nodeURL: node,
                    entryURL: entry,
                    source: .globalNpm,
                    version: readVersion(at: entry)
                )
            }
        }

        return nil
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

    private static func npmPrefixRoot(npm: URL) -> URL? {
        let process = Process()
        process.executableURL = npm
        process.arguments = ["root", "-g"]
        process.environment = ShellPath.processEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return nil }
        return URL(fileURLWithPath: text)
    }
}
