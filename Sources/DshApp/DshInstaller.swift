import Foundation

struct DshInstallProgress: Sendable {
    var bytes: Int64
    var fraction: Double?
    var message: String
    var host: String
    var stage: String
    var packageName: String
    var recentPackages: [String]
    var resolvedCount: Int
    var downloadedCount: Int
    var cachedCount: Int

    static let empty = DshInstallProgress(
        bytes: 0,
        fraction: 0,
        message: "",
        host: "",
        stage: "",
        packageName: "",
        recentPackages: [],
        resolvedCount: 0,
        downloadedCount: 0,
        cachedCount: 0
    )

    static var indeterminate: DshInstallProgress {
        var value = empty
        value.fraction = nil
        return value
    }
}

enum DshInstaller {
    static let estimatedRuntimeBytes: Int64 = 350 * 1024 * 1024
    /// No npm output and no new files since spawn: registry likely unreachable.
    private static let connectStallTimeout: TimeInterval = 30
    /// After the registry has responded, tarball downloads can be silent for a while.
    private static let downloadStallTimeout: TimeInterval = 180

    static func install(
        version: String? = nil,
        onProgress: @escaping @Sendable (DshInstallProgress) -> Void = { _ in }
    ) async throws {
        _ = try DshResolver.findNode()
        let installer = try DshResolver.findInstaller()
        resetMeasuredBytes()

        let prefix = AppPaths.managedRuntimeDirectory
        let cache = AppPaths.npmCacheDirectory
        if !DshResolver.hasManagedRuntime {
            try DshResolver.removeIncompleteRuntime()
        } else {
            DshResolver.clearRuntimeReady()
        }
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let spec = version.map { "@deepseek-ai/dsh@\($0)" } ?? "@deepseek-ai/dsh"
        let registries = await NpmRegistry.candidates()
        var lastError: Error?

        for (index, registry) in registries.enumerated() {
            let host = NpmRegistry.host(registry)
            let status = "正在用 \(installer.name) 从 \(host) 下载…"
            onProgress(
                DshInstallProgress(
                    bytes: measuredBytes(),
                    fraction: 0,
                    message: status,
                    host: host,
                    stage: "正在连接…",
                    packageName: "",
                    recentPackages: [],
                    resolvedCount: 0,
                    downloadedCount: 0,
                    cachedCount: 0
                )
            )
            DshLog.append("[install] \(installer.name) \(spec) --registry \(registry.absoluteString) --prefix \(prefix.path)\n")

            do {
                try await runInstall(
                    installer: installer,
                    prefix: prefix,
                    cache: cache,
                    spec: spec,
                    registry: registry,
                    onProgress: onProgress
                )
                lastError = nil
                break
            } catch {
                lastError = error
                DshLog.append("[install] \(installer.name) \(host) failed: \(error.localizedDescription)\n")
                if index == registries.count - 1 {
                    break
                }
                onProgress(
                    DshInstallProgress(
                        bytes: measuredBytes(),
                        fraction: 0,
                        message: "\(host) 没有下载进度，改用下一个源…",
                        host: host,
                        stage: "正在切换源…",
                        packageName: "",
                        recentPackages: [],
                        resolvedCount: 0,
                        downloadedCount: 0,
                        cachedCount: 0
                    )
                )
                if !DshResolver.hasManagedRuntime {
                    try DshResolver.removeIncompleteRuntime()
                    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
                    resetMeasuredBytes()
                }
            }
        }

        if let lastError {
            throw lastError
        }

        let finalBytes = directoryBytes(prefix)
        resetMeasuredBytes()
        onProgress(
            DshInstallProgress(
                bytes: finalBytes,
                fraction: 1,
                message: "",
                host: "",
                stage: "安装完成",
                packageName: "",
                recentPackages: [],
                resolvedCount: 0,
                downloadedCount: 0,
                cachedCount: 0
            )
        )

        guard FileManager.default.isReadableFile(atPath: AppPaths.managedEntry.path) else {
            throw DshError.missingEntry
        }
        DshResolver.markRuntimeReady()
        AppPaths.clearInstallCache()
    }

    private static func runInstall(
        installer: PackageInstaller,
        prefix: URL,
        cache: URL,
        spec: String,
        registry: URL,
        onProgress: @escaping @Sendable (DshInstallProgress) -> Void
    ) async throws {
        let host = NpmRegistry.host(registry)
        let tracker = InstallActivity(host: host, kind: {
            if case .bun = installer { return .bun }
            return .npm
        }())
        let poller = Task {
            while !Task.isCancelled {
                if directoryBytes(prefix) > 8 * 1024 * 1024 {
                    tracker.markExtracting()
                }
                onProgress(progressSnapshot(tracker: tracker))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { poller.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = installer.executable
            process.arguments = installArguments(
                installer: installer,
                prefix: prefix,
                cache: cache,
                spec: spec,
                registry: registry
            )
            process.environment = installEnvironment(for: installer)
            process.currentDirectoryURL = prefix

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice

            let output = OutputBox()
            let resume = ResumeOnce()
            let stall = StallClock()

            let handleChunk: (Pipe) -> Void = { pipe in
                pipe.fileHandleForReading.readabilityHandler = { file in
                    let data = file.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    stall.poke()
                    tracker.ingest(text)
                    output.append(text)
                    DshLog.append("[install] \(text)")
                }
            }
            handleChunk(stdout)
            handleChunk(stderr)

            process.terminationHandler = { finished in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                if finished.terminationStatus == 0 {
                    resume.resume(continuation, .success(()))
                } else {
                    resume.resume(
                        continuation,
                        .failure(DshError.installFailed(finished.terminationStatus, output.snapshot()))
                    )
                }
            }

            do {
                try process.run()
            } catch {
                resume.resume(continuation, .failure(DshError.spawnFailed(error.localizedDescription)))
                return
            }

            let pid = process.processIdentifier
            Task {
                var lastBytes = measuredBytes()
                while !Task.isCancelled && process.isRunning {
                    try? await Task.sleep(for: .seconds(1))
                    let bytes = measuredBytes()
                    if bytes > lastBytes + 32 * 1024 {
                        lastBytes = bytes
                        stall.poke()
                    }
                    if stall.stalled(connect: connectStallTimeout, download: downloadStallTimeout) {
                        let waited = stall.hasActivity ? downloadStallTimeout : connectStallTimeout
                        DshLog.append("[install] no progress from \(host) for \(Int(waited))s\n")
                        resume.resume(continuation, .failure(DshError.installStalled(host)))
                        process.terminate()
                        try? await Task.sleep(for: .seconds(2))
                        if process.isRunning {
                            kill(pid, SIGKILL)
                        }
                        return
                    }
                }
            }
        }
    }

    private static func installArguments(
        installer: PackageInstaller,
        prefix: URL,
        cache: URL,
        spec: String,
        registry: URL
    ) -> [String] {
        switch installer {
        case .bun:
            [
                "add",
                "--cwd",
                prefix.path,
                "--omit=dev",
                "--registry",
                registry.absoluteString,
                "--cache-dir",
                cache.path,
                "--linker=hoisted",
                spec,
            ]
        case .npm:
            [
                "install",
                "--omit=dev",
                "--prefix",
                prefix.path,
                "--registry",
                registry.absoluteString,
                "--cache",
                cache.path,
                "--fetch-retries=1",
                "--fetch-retry-mintimeout=1000",
                "--fetch-retry-maxtimeout=5000",
                spec,
            ]
        }
    }

    private static func installEnvironment(for installer: PackageInstaller) -> [String: String] {
        var environment = ShellPath.processEnvironment()
        switch installer {
        case .bun:
            break
        case .npm:
            environment["npm_config_fund"] = "false"
            environment["npm_config_audit"] = "false"
            environment["npm_config_update_notifier"] = "false"
            environment["npm_config_loglevel"] = "http"
            environment["npm_config_progress"] = "false"
        }
        return environment
    }

    private static func progressSnapshot(tracker: InstallActivity) -> DshInstallProgress {
        let bytes = measuredBytes()
        let snap = tracker.snapshot()
        return DshInstallProgress(
            bytes: min(bytes, estimatedRuntimeBytes),
            fraction: min(0.99, Double(bytes) / Double(estimatedRuntimeBytes)),
            message: "",
            host: snap.host,
            stage: snap.stage,
            packageName: snap.packageName,
            recentPackages: snap.recentPackages,
            resolvedCount: snap.resolvedCount,
            downloadedCount: snap.downloadedCount,
            cachedCount: snap.cachedCount
        )
    }

    private static let sizeLock = NSLock()
    nonisolated(unsafe) private static var cachedSize: (at: Date, bytes: Int64)?

    private static func resetMeasuredBytes() {
        sizeLock.lock()
        cachedSize = nil
        sizeLock.unlock()
    }

    private static func measuredBytes() -> Int64 {
        sizeLock.lock()
        if let cached = cachedSize, Date().timeIntervalSince(cached.at) < 1 {
            let bytes = cached.bytes
            sizeLock.unlock()
            return bytes
        }
        sizeLock.unlock()
        let bytes = directoryBytes(AppPaths.managedRuntimeDirectory) + directoryBytes(AppPaths.npmCacheDirectory)
        sizeLock.lock()
        cachedSize = (Date(), bytes)
        sizeLock.unlock()
        return bytes
    }

    private static func directoryBytes(_ url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return 0
        }
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let blocks = Int64(text.split(whereSeparator: \.isWhitespace).first.flatMap { Int64($0) } ?? 0)
        return blocks * 1024
    }
}

private final class InstallActivity: @unchecked Sendable {
    enum Kind {
        case bun
        case npm
    }

    struct Snapshot {
        var host: String
        var stage: String
        var packageName: String
        var recentPackages: [String]
        var resolvedCount: Int
        var downloadedCount: Int
        var cachedCount: Int
    }

    private let lock = NSLock()
    private let host: String
    private let kind: Kind
    private var stage = "正在连接…"
    private var packageName = ""
    private var recentPackages: [String] = []
    private var resolvedCount = 0
    private var downloadedCount = 0
    private var cachedCount = 0
    private var sawTarball = false

    init(host: String, kind: Kind) {
        self.host = host
        self.kind = kind
    }

    func ingest(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            parse(String(line))
        }
    }

    func markExtracting() {
        lock.lock()
        defer { lock.unlock() }
        if sawTarball || downloadedCount > 0 || kind == .bun {
            stage = "正在解压安装…"
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            host: host,
            stage: stage,
            packageName: packageName,
            recentPackages: recentPackages,
            resolvedCount: resolvedCount,
            downloadedCount: downloadedCount,
            cachedCount: cachedCount
        )
    }

    private func parse(_ line: String) {
        switch kind {
        case .bun:
            parseBun(line)
        case .npm:
            parseNpm(line)
        }
    }

    private func parseBun(_ line: String) {
        if line.contains("Resolving") {
            lock.lock()
            stage = "正在解析依赖…"
            lock.unlock()
            return
        }
        if line.contains("Downloaded "), line.contains("tarball") {
            lock.lock()
            downloadedCount += 1
            sawTarball = true
            stage = "正在下载软件包…"
            if let name = Self.bunDownloadedName(in: line) {
                remember(name)
            }
            lock.unlock()
            return
        }
        if line.contains("] Extract") || line.contains("] Extracted") {
            lock.lock()
            stage = "正在解压安装…"
            if line.hasPrefix("["), let end = line.firstIndex(of: "]") {
                remember(String(line[line.index(after: line.startIndex)..<end]))
            }
            lock.unlock()
            return
        }
        if line.contains("Resolved, downloaded and extracted") {
            lock.lock()
            stage = "正在解压安装…"
            if let count = Self.bracketCount(in: line) {
                downloadedCount = max(downloadedCount, count)
            }
            lock.unlock()
            return
        }
        if line.contains("package installed") || line.contains("packages installed") {
            lock.lock()
            stage = "正在解压安装…"
            lock.unlock()
        }
    }

    private func parseNpm(_ line: String) {
        if line.contains("added") && line.contains("package") {
            lock.lock()
            stage = "正在解压安装…"
            lock.unlock()
            return
        }
        guard line.contains("http") else { return }
        let name = Self.packageName(in: line)
        let cacheHit = line.contains("cache hit")
        let tarball = line.contains(".tgz") || line.contains("/-/")
        lock.lock()
        defer { lock.unlock() }
        if let name {
            remember(name)
        }
        if cacheHit {
            cachedCount += 1
            if stage == "正在连接…" {
                stage = "正在解析依赖…"
            }
        } else if tarball {
            downloadedCount += 1
            sawTarball = true
            stage = "正在下载软件包…"
        } else {
            resolvedCount += 1
            if !sawTarball {
                stage = "正在解析依赖…"
            }
        }
    }

    private func remember(_ name: String) {
        packageName = name
        if recentPackages.last != name {
            recentPackages.append(name)
            if recentPackages.count > 4 {
                recentPackages.removeFirst()
            }
        }
    }

    private static func bunDownloadedName(in line: String) -> String? {
        guard let start = line.range(of: "Downloaded ") else { return nil }
        var rest = String(line[start.upperBound...])
        guard let end = rest.range(of: " tarball") else { return nil }
        rest = String(rest[..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    private static func bracketCount(in line: String) -> Int? {
        guard let start = line.firstIndex(of: "["), let end = line.firstIndex(of: "]") else {
            return nil
        }
        let inner = line[line.index(after: start)..<end]
        return Int(inner)
    }

    private static func packageName(in line: String) -> String? {
        guard let http = line.range(of: "https://") else { return nil }
        var token = String(line[http.lowerBound...])
        if let space = token.firstIndex(of: " ") {
            token = String(token[..<space])
        }
        token = token.removingPercentEncoding ?? token
        guard let url = URL(string: token) else { return nil }
        var parts = url.path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return nil }
        if let cut = parts.firstIndex(of: "-") {
            parts = Array(parts[..<cut])
        }
        if parts.last == "latest" {
            parts.removeLast()
        }
        let name = parts.joined(separator: "/")
        return name.isEmpty ? nil : name
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resume(_ continuation: CheckedContinuation<Void, Error>, _ result: Result<Void, Error>) {
        lock.lock()
        let shouldResume = !done
        if shouldResume {
            done = true
        }
        lock.unlock()
        guard shouldResume else { return }
        continuation.resume(with: result)
    }
}

private final class StallClock: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date()
    private var poked = false

    var hasActivity: Bool {
        lock.lock()
        defer { lock.unlock() }
        return poked
    }

    func poke() {
        lock.lock()
        last = Date()
        poked = true
        lock.unlock()
    }

    func stalled(connect: TimeInterval, download: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let limit = poked ? download : connect
        return Date().timeIntervalSince(last) >= limit
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
