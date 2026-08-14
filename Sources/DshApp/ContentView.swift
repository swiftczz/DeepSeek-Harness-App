import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var sessionPainted = false
    @State private var splashSettled = false

    var body: some View {
        ZStack {
            switch model.phase {
            case .failed(let message):
                StatusScreen(message: message, isError: true) {
                    Task { await model.retry() }
                }
            case .ready(let url):
                DshSessionView(url: url, openURL: openURL, isPainted: $sessionPainted)
                    .id(url)
            case .starting:
                Color.clear
            case .installing(let message):
                InstallProgressScreen(status: message, detail: model.installProgress)
            }
        }
        .ignoresSafeArea()
        .background(TitlebarChromeHost())
        .overlay {
            ZStack {
                if showsSplash {
                    LaunchSplash(settled: $splashSettled)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.5), value: showsSplash)
        }
        .alert(
            "DSH 已是最新版本",
            isPresented: Binding(
                get: { if case .upToDate = model.updateAlert { true } else { false } },
                set: { if !$0 { model.dismissUpdateAlert() } }
            ),
            presenting: upToDateVersion
        ) { _ in
            Button("好") { model.updateAlert = nil }
        } message: { version in
            Text("当前运行的本地 DSH 是 \(version)。桌面应用本身不会通过这里更新。")
        }
        .alert(
            "发现 DSH 更新",
            isPresented: Binding(
                get: { if case .available = model.updateAlert { true } else { false } },
                set: { if !$0 { model.dismissUpdateAlert() } }
            ),
            presenting: availableUpdate
        ) { info in
            Button("更新") {
                model.installUpdate(info)
            }
            .keyboardShortcut(.defaultAction)
            Button("稍后", role: .cancel) {
                model.skipPendingUpdate()
            }
        } message: { info in
            Text("本地 DSH \(info.latest) 可用，当前为 \(info.current)。点更新会装到 \(AppPaths.runtimeDisplayPath) 并重启本地服务，不会重装桌面应用。")
        }
        .onChange(of: model.phase) { _, phase in
            if case .ready = phase { return }
            sessionPainted = false
            splashSettled = false
            TitlebarChrome.clear()
        }
        .task {
            await model.startIfNeeded()
        }
    }

    private var showsSplash: Bool {
        switch model.phase {
        case .failed:
            false
        case .starting:
            true
        case .installing:
            false
        case .ready:
            if model.skipLaunchSplash {
                false
            } else {
                !sessionPainted || !splashSettled
            }
        }
    }

    private var upToDateVersion: String? {
        if case .upToDate(let version) = model.updateAlert { return version }
        return nil
    }

    private var availableUpdate: DshUpdateInfo? {
        if case .available(let info) = model.updateAlert { return info }
        return nil
    }
}
