import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case starting(String)
        case installing(String)
        case ready(URL)
        case failed(String)
    }

    var phase: Phase
    var currentVersion: String?
    var pendingUpdate: DshUpdateInfo?
    var updateAlert: UpdateAlert?
    var isCheckingUpdate = false
    var installProgress = DshInstallProgress.empty
    var skipLaunchSplash: Bool
    var isInstallingUpdate: Bool {
        if case .installing = phase { true } else { false }
    }

    enum UpdateAlert: Equatable {
        case upToDate(String)
        case available(DshUpdateInfo)
    }

    private let server = DshServer()
    private var started = false
    private var launching = false
    private var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: "dsh.skippedVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "dsh.skippedVersion") }
    }

    init() {
        DshLog.prepare()
        if DshResolver.hasManagedRuntime {
            phase = .starting("正在启动本地 Agent 服务…")
            skipLaunchSplash = false
        } else {
            phase = .starting("正在检查运行环境…")
            skipLaunchSplash = true
        }
    }

    func startIfNeeded() async {
        guard !started else { return }
        started = true
        server.onCrash { [weak self] error in
            Task { @MainActor in
                self?.phase = .failed(error.localizedDescription)
            }
        }
        await start()
        startPeriodicUpdateCheck()
    }

    func retry() async {
        await start()
    }

    func updateManagedRuntime(to version: String? = nil) async {
        pendingUpdate = nil
        updateAlert = nil
        phase = .installing(version.map { "正在更新 DSH 到 \($0)…" } ?? "正在更新 DSH…")
        skipLaunchSplash = true
        installProgress = .indeterminate
        server.stop()
        do {
            try await installRuntime(version: version)
            await start()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func checkForUpdates(interactive: Bool) async {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }

        if let info = await DshUpdater.latestRelease(current: currentVersion) {
            if skippedVersion == info.latest, !interactive {
                return
            }
            skippedVersion = nil
            pendingUpdate = info
            updateAlert = .available(info)
            return
        }

        pendingUpdate = nil
        if interactive {
            updateAlert = .upToDate(currentVersion ?? "未知")
        }
    }

    func installUpdate(_ info: DshUpdateInfo) {
        pendingUpdate = nil
        updateAlert = nil
        skippedVersion = nil
        Task { await updateManagedRuntime(to: info.latest) }
    }

    func skipPendingUpdate() {
        if let latest = pendingUpdate?.latest {
            skippedVersion = latest
        }
        pendingUpdate = nil
        updateAlert = nil
    }

    func dismissUpdateAlert() {
        updateAlert = nil
    }

    func stop() {
        server.stop()
    }

    func openLogs() {
        DshLog.revealInFinder()
    }

    func openNpmCache() {
        AppPaths.revealDirectory(AppPaths.npmCacheDirectory)
    }

    private func installRuntime(version: String? = nil) async throws {
        try await DshInstaller.install(version: version) { [weak self] progress in
            Task { @MainActor in
                self?.applyInstallProgress(progress)
            }
        }
    }

    private func applyInstallProgress(_ progress: DshInstallProgress) {
        installProgress = progress
        if !progress.message.isEmpty {
            phase = .installing(progress.message)
        }
    }

    private func start() async {
        guard !launching else { return }
        launching = true
        defer { launching = false }

        server.stop()

        do {
            var plan = try DshResolver.resolveLaunchPlan()
            if plan == nil {
                _ = try DshResolver.findInstaller()
                skipLaunchSplash = true
                installProgress = .empty
                phase = .installing(
                    DshResolver.hasIncompleteRuntime
                        ? "上次安装未完成，正在重新安装到 \(AppPaths.runtimeDisplayPath)…"
                        : "未找到 DSH，正在安装到 \(AppPaths.runtimeDisplayPath)…"
                )
                try await installRuntime()
                plan = try DshResolver.resolveLaunchPlan()
            } else {
                skipLaunchSplash = false
                phase = .starting("正在启动本地 Agent 服务…")
            }

            guard let plan else {
                throw DshError.missingEntry
            }

            currentVersion = plan.version
            phase = .ready(try await server.start(plan: plan))
            Task { await checkForUpdates(interactive: false) }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func startPeriodicUpdateCheck() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
                await self?.checkForUpdates(interactive: false)
            }
        }
    }
}
