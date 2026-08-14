import AppKit
import SwiftUI

@main
struct DshApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("DeepSeek Harness", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 620)
                .containerBackground(.background, for: .window)
                .onReceive(NotificationCenter.default.publisher(for: .applicationWillTerminate)) { _ in
                    model.stop()
                }
        }
        .defaultSize(width: 1440, height: 920)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("关于 DeepSeek Harness", systemImage: "info.circle") {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                    let dsh = model.currentVersion ?? (try? DshResolver.resolveLaunchPlan())?.version
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationVersion: version,
                        .version: dsh.map { "DSH \($0)" } ?? "",
                    ])
                }
            }
            CommandGroup(after: .appInfo) {
                Button("检查 DSH 更新…", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await model.checkForUpdates(interactive: true) }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.isCheckingUpdate || model.isInstallingUpdate)

                if let update = model.pendingUpdate {
                    Button("更新到 \(update.latest)…", systemImage: "square.and.arrow.down") {
                        model.installUpdate(update)
                    }
                    .disabled(model.isInstallingUpdate)
                }

                Divider()

                Button("打开日志", systemImage: "doc.text") {
                    model.openLogs()
                }

                Button("打开 npm 缓存", systemImage: "folder") {
                    model.openNpmCache()
                }
            }
        }
    }
}

private extension Notification.Name {
    static let applicationWillTerminate = Notification.Name("NSApplicationWillTerminateNotification")
}
