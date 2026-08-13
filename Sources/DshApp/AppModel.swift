import AppKit
import Foundation

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case starting(String)
        case installing(String)
        case ready(URL)
        case failed(String)
    }

    var phase: Phase = .starting("正在启动本地 Agent 服务…")
    var currentVersion: String?
    var pendingUpdate: DshUpdateInfo?
    var updateAlert: UpdateAlert?
    var isCheckingUpdate = false
    var isInstallingUpdate: Bool {
        if case .installing = phase { return true }
        return false
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

    func startIfNeeded() async {
        guard !started else { return }
        started = true
        DshLog.prepare()
        server.onCrash { [weak self] error in
            Task { @MainActor in
                self?.phase = .failed(error.localizedDescription)
            }
        }
        await start()
        Task { await checkForUpdates(interactive: false) }
        startPeriodicUpdateCheck()
    }

    func retry() async {
        await start()
    }

    func updateManagedRuntime(to version: String? = nil) async {
        pendingUpdate = nil
        updateAlert = nil
        phase = .installing(version.map { "正在更新 DSH 到 \($0)…" } ?? "正在更新 DSH…")
        server.stop()
        do {
            try await DshInstaller.install(version: version) { [weak self] chunk in
                Task { @MainActor in
                    let line = chunk.split(whereSeparator: \.isNewline).last.map(String.init) ?? "正在更新 DSH…"
                    self?.phase = .installing(line)
                }
            }
            await start(preferManaged: true)
            Task { await checkForUpdates(interactive: false) }
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

    func showAbout() {
        let dsh = currentVersion
            ?? (try? DshResolver.resolveLaunchPlan())?.version
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .version: dsh.map { "DSH \($0)" } ?? "",
        ])
    }

    func stop() {
        server.stop()
    }

    func openLogs() {
        DshLog.revealInFinder()
    }

    private func start(preferManaged: Bool = false) async {
        guard !launching else { return }
        launching = true
        defer { launching = false }

        phase = .starting("正在启动本地 Agent 服务…")
        server.stop()

        do {
            var plan = try DshResolver.resolveLaunchPlan(preferManaged: preferManaged)
            if plan == nil {
                phase = .installing("未找到 DSH，正在安装到应用目录…")
                try await DshInstaller.install { [weak self] chunk in
                    Task { @MainActor in
                        let line = chunk.split(whereSeparator: \.isNewline).last.map(String.init) ?? "正在安装 DSH…"
                        self?.phase = .installing(line)
                    }
                }
                plan = try DshResolver.resolveLaunchPlan(preferManaged: true)
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
