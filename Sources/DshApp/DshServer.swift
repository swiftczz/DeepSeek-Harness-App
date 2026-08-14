import Darwin
import Foundation

final class DshServer: @unchecked Sendable {
    static let urlPattern = try! NSRegularExpression(
        pattern: #"dsh web:\s*(http://127\.0\.0\.1:\d+)"#,
        options: []
    )

    private let lock = NSLock()
    private var process: Process?
    private var buffer = ""
    private var didDeliverURL = false
    private var stopping = false
    private var timeoutWork: DispatchWorkItem?
    private var crashHandler: (@Sendable (Error) -> Void)?

    func onCrash(_ handler: @escaping @Sendable (Error) -> Void) {
        lock.lock()
        crashHandler = handler
        lock.unlock()
    }

    func start(plan: DshLaunchPlan, timeout: TimeInterval = 45) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let once = OnceBox(continuation)
            do {
                try launch(
                    plan: plan,
                    timeout: timeout,
                    onURL: { once.resume(returning: $0) },
                    onFailure: { [weak self] error in
                        if once.resume(throwing: error) {
                            return
                        }
                        self?.forwardCrash(error)
                    }
                )
            } catch {
                _ = once.resume(throwing: error)
            }
        }
    }

    private func forwardCrash(_ error: Error) {
        lock.lock()
        let handler = crashHandler
        lock.unlock()
        handler?(error)
    }

    private func launch(
        plan: DshLaunchPlan,
        timeout: TimeInterval,
        onURL: @escaping @Sendable (URL) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) throws {
        stop()

        DshLog.append("[dsh] node=\(plan.nodeURL.path) entry=\(plan.entryURL.path) version=\(plan.version ?? "unknown")\n")

        let process = Process()
        process.executableURL = plan.nodeURL
        process.arguments = [
            "--expose-internals",
            plan.entryURL.path,
            "web",
            "--host",
            "127.0.0.1",
            "--port",
            "0",
        ]
        process.environment = ShellPath.processEnvironment()
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.qualityOfService = .userInitiated

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        lock.lock()
        stopping = false
        didDeliverURL = false
        buffer = ""
        lock.unlock()

        let deliverURL: @Sendable (URL) -> Void = { [weak self] url in
            guard let self else { return }
            self.lock.lock()
            let already = self.didDeliverURL
            self.didDeliverURL = true
            self.timeoutWork?.cancel()
            self.lock.unlock()
            if !already {
                onURL(url)
            }
        }

        let fail: @Sendable (Error) -> Void = { [weak self] error in
            guard let self else { return }
            self.lock.lock()
            if self.stopping {
                self.lock.unlock()
                return
            }
            let already = self.didDeliverURL
            self.didDeliverURL = true
            self.timeoutWork?.cancel()
            self.lock.unlock()
            if !already {
                onFailure(error)
            } else {
                self.forwardCrash(error)
            }
        }

        let consume: @Sendable (String, String) -> Void = { prefix, chunk in
            DshLog.append("\(prefix)\(chunk)")
            self.lock.lock()
            self.buffer = String((self.buffer + chunk).suffix(16_384))
            let snapshot = self.buffer
            self.lock.unlock()

            let range = NSRange(snapshot.startIndex..., in: snapshot)
            if let match = Self.urlPattern.firstMatch(in: snapshot, options: [], range: range),
               match.numberOfRanges > 1,
               let swiftRange = Range(match.range(at: 1), in: snapshot),
               let url = URL(string: String(snapshot[swiftRange])) {
                deliverURL(url)
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            consume("[dsh] ", text)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            consume("[dsh:error] ", text)
        }

        process.terminationHandler = { [weak self] finished in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            self?.lock.lock()
            self?.process = nil
            let stopping = self?.stopping ?? true
            self?.lock.unlock()
            if !stopping {
                fail(DshError.exited(finished.terminationStatus))
            }
        }

        do {
            try process.run()
        } catch {
            throw DshError.spawnFailed(error.localizedDescription)
        }

        let pid = process.processIdentifier
        setpgid(pid, pid)

        lock.lock()
        self.process = process
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let ready = self.didDeliverURL
            let stoppingNow = self.stopping
            self.lock.unlock()
            if !ready && !stoppingNow {
                fail(DshError.timedOut)
            }
        }
        timeoutWork = work
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func stop() {
        lock.lock()
        stopping = true
        timeoutWork?.cancel()
        timeoutWork = nil
        let running = process
        process = nil
        lock.unlock()

        guard let running, running.isRunning else { return }
        let pid = running.processIdentifier
        kill(-pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if running.isRunning {
                kill(-pid, SIGKILL)
                running.terminate()
            }
        }
    }
}

private final class OnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func resume(returning url: URL) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: url)
    }

    @discardableResult
    func resume(throwing error: Error) -> Bool {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        guard let cont else { return false }
        cont.resume(throwing: error)
        return true
    }
}
