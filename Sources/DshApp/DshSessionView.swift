import SwiftUI
import WebKit

enum AppChrome {
    static let titlebarHeight: CGFloat = 20
}

struct DshSessionView: View {
    let url: URL
    @Binding var isPainted: Bool
    @State private var page: WebPage

    init(url: URL, openURL: OpenURLAction, isPainted: Binding<Bool>) {
        self.url = url
        _isPainted = isPainted
        var configuration = WebPage.Configuration()
        configuration.defaultNavigationPreferences.preferredContentMode = .desktop
        configuration.applicationNameForUserAgent = "DeepSeekHarness"
        AppDownload.install(on: configuration.userContentController)
        configuration.userContentController.addUserScript(Self.titlebarInsetScript)
        _page = State(
            initialValue: WebPage(
                configuration: configuration,
                navigationDecider: DshNavigationPolicy(origin: url.origin, openURL: openURL)
            )
        )
    }

    var body: some View {
        WebView(page)
            .webViewElementFullscreenBehavior(.enabled)
            .webViewMagnificationGestures(.enabled)
            .webViewBackForwardNavigationGestures(.disabled)
            .webViewContentBackground(.hidden)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                TitlebarDragRegion()
            }
            .task(id: url) {
                isPainted = false
                TitlebarChrome.clear()
                page.isInspectable = true
                await loadUntilPainted()
                await Self.syncTitlebar(from: page)
                isPainted = true
                while !Task.isCancelled {
                    await Self.syncTitlebar(from: page)
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
    }

    private func loadUntilPainted() async {
        do {
            for try await event in page.load(url) {
                if event == .finished {
                    break
                }
            }
        } catch {
            return
        }

        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline, !Task.isCancelled {
            if await Self.sidebarWidth(from: page) > 0 {
                try? await Task.sleep(for: .milliseconds(80))
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func sidebarWidth(from page: WebPage) async -> CGFloat {
        guard let body = await chromeSnapshot(from: page) else { return 0 }
        return numericWidth(body["width"])
    }

    private static func syncTitlebar(from page: WebPage) async {
        guard let body = await chromeSnapshot(from: page) else { return }
        let width = numericWidth(body["width"])
        guard width > 0, let sidebar = color(from: body["sidebar"] as? String) else { return }
        TitlebarChrome.update(width: width, sidebar: sidebar)
    }

    private static func chromeSnapshot(from page: WebPage) async -> [String: Any]? {
        let result = try? await page.callJavaScript(
            Self.chromeJavaScript,
            contentWorld: .page
        )
        return (result as? [String: Any]) ?? (result as? NSDictionary as? [String: Any])
    }

    private static func numericWidth(_ value: Any?) -> CGFloat {
        if let number = value as? NSNumber {
            return CGFloat(truncating: number)
        }
        if let value = value as? Double {
            return CGFloat(value)
        }
        if let value = value as? Int {
            return CGFloat(value)
        }
        return 0
    }

    private static func color(from css: String?) -> Color? {
        guard let value = css?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty, value != "transparent" else { return nil }
        guard let open = value.firstIndex(of: "("),
              let close = value.lastIndex(of: ")") else { return nil }
        let inner = value[value.index(after: open)..<close]
        let parts = inner.split { $0 == "," || $0 == "/" || $0 == " " }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap(Double.init)
        guard parts.count >= 3 else { return nil }
        let r = parts[0]
        let g = parts[1]
        let b = parts[2]
        let a = parts.count >= 4 ? parts[3] : 1
        let scaled = r > 1 || g > 1 || b > 1
        return Color(
            red: scaled ? r / 255 : r,
            green: scaled ? g / 255 : g,
            blue: scaled ? b / 255 : b,
            opacity: a > 1 ? a / 255 : a
        )
    }

    private static var chromeJavaScript: String {
        let inset = Int(AppChrome.titlebarHeight)
        return """
        const styleId = 'dsh-app-titlebar-inset';
        let style = document.getElementById(styleId);
        if (!style) {
          style = document.createElement('style');
          style.id = styleId;
          (document.head || document.documentElement).appendChild(style);
        }
        style.textContent = '[class*="_logoRow"]{margin-top:\(inset)px !important;}';
        const sidebarProbe = document.createElement('div');
        sidebarProbe.style.background = 'var(--dsw-specific-sidebar-fill)';
        document.documentElement.appendChild(sidebarProbe);
        const sidebar = getComputedStyle(sidebarProbe).backgroundColor;
        sidebarProbe.remove();
        const column = document.querySelector('[class*="_sidebarCol"]')
          || document.querySelector('[class*="sidebarCol"]');
        const width = column ? Math.round(column.getBoundingClientRect().width) : 0;
        return { width, sidebar };
        """
    }

    private static var titlebarInsetScript: WKUserScript {
        let inset = Int(AppChrome.titlebarHeight)
        return WKUserScript(
            source: """
            (function () {
              const apply = () => {
                let style = document.getElementById('dsh-app-titlebar-inset');
                if (!style) {
                  style = document.createElement('style');
                  style.id = 'dsh-app-titlebar-inset';
                  (document.head || document.documentElement).appendChild(style);
                }
                style.textContent = '[class*="_logoRow"]{margin-top:\(inset)px !important;}';
              };
              apply();
              new MutationObserver(apply).observe(document.documentElement, { childList: true });
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }
}

private struct TitlebarDragRegion: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 78)
                .allowsHitTesting(false)
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
        .frame(height: AppChrome.titlebarHeight)
    }
}

private struct DshNavigationPolicy: WebPage.NavigationDeciding {
    let origin: String?
    let openURL: OpenURLAction

    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        preferences.preferredContentMode = .desktop
        guard let target = action.request.url else {
            return .allow
        }
        if action.shouldPerformDownload || AppDownload.isExportURL(target) {
            AppDownload.enqueue(action.request)
            return .cancel
        }
        if shouldOpenExternally(target) {
            openURL(target)
            return .cancel
        }
        return .allow
    }

    func decidePolicy(
        for response: WebPage.NavigationResponse
    ) async -> WKNavigationResponsePolicy {
        if AppDownload.shouldDownload(response) {
            AppDownload.enqueue(from: response.response)
            return .cancel
        }
        return .allow
    }

    private func shouldOpenExternally(_ url: URL) -> Bool {
        if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
            return false
        }
        if url.origin == origin {
            return false
        }
        if url.host == "127.0.0.1" || url.host == "localhost" {
            return false
        }
        return isWebURL(url)
    }

    private func isWebURL(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }
}

extension URL {
    var origin: String? {
        guard let scheme, let host else { return nil }
        if let port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
}
