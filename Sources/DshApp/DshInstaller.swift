import Foundation

enum DshInstaller {
    static func install(
        version: String? = nil,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        _ = try DshResolver.findNode()
        guard let npm = DshResolver.findNpm() else {
            throw DshError.missingNpm
        }

        let prefix = AppPaths.managedRuntimeDirectory
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)

        let spec = version.map { "@deepseek-ai/dsh@\($0)" } ?? "@deepseek-ai/dsh"
        DshLog.append("[install] npm install --prefix \(prefix.path) \(spec)\n")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = npm
            process.arguments = [
                "install",
                "--omit=dev",
                "--prefix",
                prefix.path,
                spec,
            ]
            process.environment = ShellPath.processEnvironment()
            process.currentDirectoryURL = prefix

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice

            let output = OutputBox()

            let handleChunk: (Pipe) -> Void = { pipe in
                pipe.fileHandleForReading.readabilityHandler = { file in
                    let data = file.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    output.append(text)
                    DshLog.append("[install] \(text)")
                    onOutput(text)
                }
            }
            handleChunk(stdout)
            handleChunk(stderr)

            process.terminationHandler = { finished in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DshError.installFailed(finished.terminationStatus, output.snapshot()))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: DshError.spawnFailed(error.localizedDescription))
            }
        }

        guard FileManager.default.isReadableFile(atPath: AppPaths.managedEntry.path) else {
            throw DshError.missingEntry
        }
    }
}

private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ chunk: String) {
        lock.lock()
        text += chunk
        if text.count > 16_384 {
            text = String(text.suffix(16_384))
        }
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}
