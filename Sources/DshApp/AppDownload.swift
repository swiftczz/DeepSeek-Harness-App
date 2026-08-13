import AppKit
import Foundation
import WebKit

@MainActor
enum AppDownload {
    private static var inFlight = Set<String>()

    static func enqueue(_ request: URLRequest, suggestedFilename: String? = nil) {
        guard let url = request.url else { return }
        let key = url.absoluteString
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)

        Task {
            defer { inFlight.remove(key) }
            await save(request, suggestedFilename: suggestedFilename)
        }
    }

    static func enqueue(from response: URLResponse) {
        guard let url = response.url else { return }
        enqueue(URLRequest(url: url), suggestedFilename: response.suggestedFilename)
    }

    static func install(on controller: WKUserContentController) {
        controller.removeScriptMessageHandler(forName: "dshDownload")
        controller.add(Bridge(), name: "dshDownload")
        controller.addUserScript(
            WKUserScript(
                source: interceptorSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
    }

    static func isExportURL(_ url: URL) -> Bool {
        url.path == "/api/session.export"
    }

    static func shouldDownload(_ response: WebPage.NavigationResponse) -> Bool {
        if !response.canShowMimeType {
            return true
        }
        if let url = response.response.url, isExportURL(url) {
            return true
        }
        guard let http = response.response as? HTTPURLResponse,
              let disposition = http.value(forHTTPHeaderField: "Content-Disposition") else {
            return false
        }
        return disposition.lowercased().contains("attachment")
    }

    private static let interceptorSource = """
    (function () {
      document.addEventListener('click', function (event) {
        const anchor = event.target && event.target.closest && event.target.closest('a[download]');
        if (!anchor || !anchor.href) return;
        if (anchor.origin && location.origin && anchor.origin !== location.origin) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dshDownload;
        if (!handler) return;
        handler.postMessage({
          url: anchor.href,
          filename: anchor.getAttribute('download') || ''
        });
      }, true);
    })();
    """

    private static func save(_ original: URLRequest, suggestedFilename: String?) async {
        var request = original
        if request.httpMethod?.uppercased() == "HEAD" {
            request.httpMethod = "GET"
        }
        await copyCookies(into: &request)

        do {
            let (temp, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                DshLog.append("[download] HTTP \(http.statusCode) \(request.url?.absoluteString ?? "")\n")
                try? FileManager.default.removeItem(at: temp)
                return
            }

            let name = sanitizedFilename(
                suggestedFilename
                    ?? response.suggestedFilename
                    ?? request.url.flatMap(filenameFromExportURL)
                    ?? "download"
            )
            let destination = uniqueURL(in: downloadsDirectory(), name: name)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temp, to: destination)
            DshLog.append("[download] \(destination.path)\n")
            reveal(destination)
        } catch {
            DshLog.append("[download] \(error.localizedDescription)\n")
        }
    }

    private static func copyCookies(into request: inout URLRequest) async {
        guard let url = request.url else { return }
        let cookies = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        let matching = cookies.filter { cookieMatches($0, url: url) }
        guard !matching.isEmpty else { return }
        let fields = HTTPCookie.requestHeaderFields(with: matching)
        if let cookie = fields["Cookie"] {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
    }

    private static func cookieMatches(_ cookie: HTTPCookie, url: URL) -> Bool {
        guard let host = url.host else { return false }
        let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
        return host == cookie.domain || host == domain || host.hasSuffix(".\(domain)")
    }

    private static func filenameFromExportURL(_ url: URL) -> String? {
        guard isExportURL(url) else { return nil }
        let sessionId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "sessionId" })?
            .value
        guard let sessionId, !sessionId.isEmpty else { return "dsh-session.zip" }
        let safe = sessionId.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        return "dsh-session-\(safe).zip"
    }

    private static func sanitizedFilename(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = URL(fileURLWithPath: trimmed).lastPathComponent
        if name.isEmpty || name == "." || name == ".." {
            return "download"
        }
        return name
    }

    private static func downloadsDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    private static func uniqueURL(in directory: URL, name: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: name).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
            index += 1
        }
        return candidate
    }

    private static func reveal(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-R", url.path]
        try? process.run()
    }
}

@MainActor
private final class Bridge: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let urlString = body["url"] as? String,
              let url = URL(string: urlString) else { return }
        let filename = (body["filename"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        AppDownload.enqueue(URLRequest(url: url), suggestedFilename: filename)
    }
}
