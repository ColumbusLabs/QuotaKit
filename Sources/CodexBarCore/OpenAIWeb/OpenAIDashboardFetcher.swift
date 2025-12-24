import AppKit
import Foundation
import WebKit

@MainActor
public struct OpenAIDashboardFetcher {
    public enum FetchError: LocalizedError {
        case loginRequired
        case noDashboardData(body: String)

        public var errorDescription: String? {
            switch self {
            case .loginRequired:
                "OpenAI web access requires login."
            case let .noDashboardData(body):
                "OpenAI dashboard data not found. Body sample: \(body.prefix(200))"
            }
        }
    }

    private let usageURL = URL(string: "https://chatgpt.com/codex/settings/usage")!

    public init() {}

    public nonisolated static func offscreenHostWindowFrame(for visibleFrame: CGRect) -> CGRect {
        let width: CGFloat = min(1200, visibleFrame.width)
        let height: CGFloat = min(1600, visibleFrame.height)

        // Keep the WebView "visible" for WebKit hydration, but never show it to the user.
        // Place the window almost entirely off-screen; leave only a 1×1 px intersection.
        let sliver: CGFloat = 1
        return CGRect(
            x: visibleFrame.maxX - sliver,
            y: visibleFrame.maxY - sliver,
            width: width,
            height: height)
    }

    public nonisolated static func offscreenHostAlphaValue() -> CGFloat {
        // Must be > 0 or WebKit can throttle hydration/timers on the Codex usage SPA.
        0.001
    }

    public struct ProbeResult: Sendable {
        public let href: String?
        public let loginRequired: Bool
        public let workspacePicker: Bool
        public let cloudflareInterstitial: Bool
        public let signedInEmail: String?
        public let bodyText: String?

        public init(
            href: String?,
            loginRequired: Bool,
            workspacePicker: Bool,
            cloudflareInterstitial: Bool,
            signedInEmail: String?,
            bodyText: String?)
        {
            self.href = href
            self.loginRequired = loginRequired
            self.workspacePicker = workspacePicker
            self.cloudflareInterstitial = cloudflareInterstitial
            self.signedInEmail = signedInEmail
            self.bodyText = bodyText
        }
    }

    public func loadLatestDashboard(
        accountEmail: String?,
        logger: ((String) -> Void)? = nil,
        debugDumpHTML: Bool = false,
        timeout: TimeInterval = 60) async throws -> OpenAIDashboardSnapshot
    {
        let store = OpenAIDashboardWebsiteDataStore.store(forAccountEmail: accountEmail)
        return try await self.loadLatestDashboard(
            websiteDataStore: store,
            logger: logger,
            debugDumpHTML: debugDumpHTML,
            timeout: timeout)
    }

    public func loadLatestDashboard(
        websiteDataStore: WKWebsiteDataStore,
        logger: ((String) -> Void)? = nil,
        debugDumpHTML: Bool = false,
        timeout: TimeInterval = 60) async throws -> OpenAIDashboardSnapshot
    {
        let lease = try await self.makeWebView(websiteDataStore: websiteDataStore, logger: logger)
        defer { lease.release() }
        let webView = lease.webView
        let log = lease.log

        let deadline = Date().addingTimeInterval(timeout)
        var lastBody: String?
        var lastHTML: String?
        var lastHref: String?
        var lastFlags: (loginRequired: Bool, workspacePicker: Bool, cloudflare: Bool)?
        var codeReviewFirstSeenAt: Date?
        var anyDashboardSignalAt: Date?
        var creditsHeaderVisibleAt: Date?
        var lastUsageBreakdownDebug: String?
        var lastCreditsPurchaseURL: String?

        while Date() < deadline {
            let scrape = try await self.scrape(webView: webView)
            lastBody = scrape.bodyText ?? lastBody
            lastHTML = scrape.bodyHTML ?? lastHTML

            if scrape.href != lastHref
                || lastFlags?.loginRequired != scrape.loginRequired
                || lastFlags?.workspacePicker != scrape.workspacePicker
                || lastFlags?.cloudflare != scrape.cloudflareInterstitial
            {
                lastHref = scrape.href
                lastFlags = (scrape.loginRequired, scrape.workspacePicker, scrape.cloudflareInterstitial)
                let href = scrape.href ?? "nil"
                log(
                    "href=\(href) login=\(scrape.loginRequired) " +
                        "workspace=\(scrape.workspacePicker) cloudflare=\(scrape.cloudflareInterstitial)")
            }

            if scrape.workspacePicker {
                try? await Task.sleep(for: .milliseconds(500))
                continue
            }

            // The page is a SPA and can land on ChatGPT UI or other routes; keep forcing the usage URL.
            if let href = scrape.href, !href.contains("/codex/settings/usage") {
                _ = webView.load(URLRequest(url: self.usageURL))
                try? await Task.sleep(for: .milliseconds(500))
                continue
            }

            if scrape.loginRequired {
                if debugDumpHTML, let html = scrape.bodyHTML {
                    Self.writeDebugArtifacts(html: html, bodyText: scrape.bodyText, logger: log)
                }
                throw FetchError.loginRequired
            }

            if scrape.cloudflareInterstitial {
                if debugDumpHTML, let html = scrape.bodyHTML {
                    Self.writeDebugArtifacts(html: html, bodyText: scrape.bodyText, logger: log)
                }
                throw FetchError.noDashboardData(body: "Cloudflare challenge detected in WebView.")
            }

            let bodyText = scrape.bodyText ?? ""
            let codeReview = OpenAIDashboardParser.parseCodeReviewRemainingPercent(bodyText: bodyText)
            let events = OpenAIDashboardParser.parseCreditEvents(rows: scrape.rows)
            let breakdown = OpenAIDashboardSnapshot.makeDailyBreakdown(from: events, maxDays: 30)
            let usageBreakdown = scrape.usageBreakdown

            if codeReview != nil, codeReviewFirstSeenAt == nil { codeReviewFirstSeenAt = Date() }
            if anyDashboardSignalAt == nil,
               codeReview != nil || !usageBreakdown.isEmpty || scrape.creditsHeaderPresent
            {
                anyDashboardSignalAt = Date()
            }
            if codeReview != nil, usageBreakdown.isEmpty,
               let debug = scrape.usageBreakdownDebug, !debug.isEmpty,
               debug != lastUsageBreakdownDebug
            {
                lastUsageBreakdownDebug = debug
                log("usage breakdown debug: \(debug)")
            }
            if let purchaseURL = scrape.creditsPurchaseURL, purchaseURL != lastCreditsPurchaseURL {
                lastCreditsPurchaseURL = purchaseURL
                log("credits purchase url: \(purchaseURL)")
            }
            if events.isEmpty, codeReview != nil || !usageBreakdown.isEmpty {
                log(
                    "credits header present=\(scrape.creditsHeaderPresent) " +
                        "inViewport=\(scrape.creditsHeaderInViewport) didScroll=\(scrape.didScrollToCredits) " +
                        "rows=\(scrape.rows.count)")
                if scrape.didScrollToCredits {
                    log("scrollIntoView(Credits usage history) requested; waiting…")
                    try? await Task.sleep(for: .milliseconds(600))
                    continue
                }

                // Avoid returning early when the usage breakdown chart hydrates before the (often virtualized)
                // credits table. When we detect a dashboard signal, give credits history a moment to appear.
                if scrape.creditsHeaderPresent, scrape.creditsHeaderInViewport, creditsHeaderVisibleAt == nil {
                    creditsHeaderVisibleAt = Date()
                }
                if Self.shouldWaitForCreditsHistory(.init(
                    now: Date(),
                    anyDashboardSignalAt: anyDashboardSignalAt,
                    creditsHeaderVisibleAt: creditsHeaderVisibleAt,
                    creditsHeaderPresent: scrape.creditsHeaderPresent,
                    creditsHeaderInViewport: scrape.creditsHeaderInViewport,
                    didScrollToCredits: scrape.didScrollToCredits))
                {
                    try? await Task.sleep(for: .milliseconds(400))
                    continue
                }
            }

            if codeReview != nil || !events.isEmpty || !usageBreakdown.isEmpty {
                // The usage breakdown chart is hydrated asynchronously. When code review is already present,
                // give it a moment to populate so the menu can show it.
                if codeReview != nil, usageBreakdown.isEmpty {
                    let elapsed = Date().timeIntervalSince(codeReviewFirstSeenAt ?? Date())
                    if elapsed < 6 {
                        try? await Task.sleep(for: .milliseconds(400))
                        continue
                    }
                }
                return OpenAIDashboardSnapshot(
                    signedInEmail: scrape.signedInEmail,
                    codeReviewRemainingPercent: codeReview,
                    creditEvents: events,
                    dailyBreakdown: breakdown,
                    usageBreakdown: usageBreakdown,
                    creditsPurchaseURL: scrape.creditsPurchaseURL,
                    updatedAt: Date())
            }

            try? await Task.sleep(for: .milliseconds(500))
        }

        if debugDumpHTML, let html = lastHTML {
            Self.writeDebugArtifacts(html: html, bodyText: lastBody, logger: log)
        }
        throw FetchError.noDashboardData(body: lastBody ?? "")
    }

    struct CreditsHistoryWaitContext: Sendable {
        let now: Date
        let anyDashboardSignalAt: Date?
        let creditsHeaderVisibleAt: Date?
        let creditsHeaderPresent: Bool
        let creditsHeaderInViewport: Bool
        let didScrollToCredits: Bool
    }

    nonisolated static func shouldWaitForCreditsHistory(_ context: CreditsHistoryWaitContext) -> Bool {
        if context.didScrollToCredits { return true }

        // When the header is visible but rows are still empty, wait briefly for the table to render.
        if context.creditsHeaderPresent, context.creditsHeaderInViewport {
            if let creditsHeaderVisibleAt = context.creditsHeaderVisibleAt {
                return context.now.timeIntervalSince(creditsHeaderVisibleAt) < 2.5
            }
            return true
        }

        // Header not in view yet: allow a short grace period after we first detect any dashboard signal so
        // a scroll (or hydration) can bring the credits section into the DOM.
        if let anyDashboardSignalAt = context.anyDashboardSignalAt {
            return context.now.timeIntervalSince(anyDashboardSignalAt) < 6.5
        }
        return false
    }

    public func clearSessionData(accountEmail: String?) async {
        let store = OpenAIDashboardWebsiteDataStore.store(forAccountEmail: accountEmail)
        OpenAIDashboardWebViewCache.shared.evict(websiteDataStore: store)
        await OpenAIDashboardWebsiteDataStore.clearStore(forAccountEmail: accountEmail)
    }

    public func probeUsagePage(
        websiteDataStore: WKWebsiteDataStore,
        logger: ((String) -> Void)? = nil,
        timeout: TimeInterval = 30) async throws -> ProbeResult
    {
        let lease = try await self.makeWebView(websiteDataStore: websiteDataStore, logger: logger)
        defer { lease.release() }
        let webView = lease.webView
        let log = lease.log

        let deadline = Date().addingTimeInterval(timeout)
        var lastBody: String?
        var lastHref: String?

        while Date() < deadline {
            let scrape = try await self.scrape(webView: webView)
            lastBody = scrape.bodyText ?? lastBody
            lastHref = scrape.href ?? lastHref

            if scrape.workspacePicker {
                try? await Task.sleep(for: .milliseconds(500))
                continue
            }

            if let href = scrape.href, !href.contains("/codex/settings/usage") {
                _ = webView.load(URLRequest(url: self.usageURL))
                try? await Task.sleep(for: .milliseconds(500))
                continue
            }

            if scrape.loginRequired { throw FetchError.loginRequired }
            if scrape.cloudflareInterstitial {
                throw FetchError.noDashboardData(body: "Cloudflare challenge detected in WebView.")
            }

            return ProbeResult(
                href: scrape.href,
                loginRequired: scrape.loginRequired,
                workspacePicker: scrape.workspacePicker,
                cloudflareInterstitial: scrape.cloudflareInterstitial,
                signedInEmail: scrape.signedInEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
                bodyText: scrape.bodyText)
        }

        log("Probe timed out (href=\(lastHref ?? "nil"))")
        return ProbeResult(
            href: lastHref,
            loginRequired: false,
            workspacePicker: false,
            cloudflareInterstitial: false,
            signedInEmail: nil,
            bodyText: lastBody)
    }

    // MARK: - JS scrape

    private struct ScrapeResult {
        let loginRequired: Bool
        let workspacePicker: Bool
        let cloudflareInterstitial: Bool
        let href: String?
        let bodyText: String?
        let bodyHTML: String?
        let signedInEmail: String?
        let creditsPurchaseURL: String?
        let rows: [[String]]
        let usageBreakdown: [OpenAIDashboardDailyBreakdown]
        let usageBreakdownDebug: String?
        let scrollY: Double
        let scrollHeight: Double
        let viewportHeight: Double
        let creditsHeaderPresent: Bool
        let creditsHeaderInViewport: Bool
        let didScrollToCredits: Bool
    }

    private func scrape(webView: WKWebView) async throws -> ScrapeResult {
        let any = try await webView.evaluateJavaScript(openAIDashboardScrapeScript)
        guard let dict = any as? [String: Any] else {
            return ScrapeResult(
                loginRequired: true,
                workspacePicker: false,
                cloudflareInterstitial: false,
                href: nil,
                bodyText: nil,
                bodyHTML: nil,
                signedInEmail: nil,
                creditsPurchaseURL: nil,
                rows: [],
                usageBreakdown: [],
                usageBreakdownDebug: nil,
                scrollY: 0,
                scrollHeight: 0,
                viewportHeight: 0,
                creditsHeaderPresent: false,
                creditsHeaderInViewport: false,
                didScrollToCredits: false)
        }

        var loginRequired = (dict["loginRequired"] as? Bool) ?? false
        let workspacePicker = (dict["workspacePicker"] as? Bool) ?? false
        let cloudflareInterstitial = (dict["cloudflareInterstitial"] as? Bool) ?? false
        let rows = (dict["rows"] as? [[String]]) ?? []
        let bodyHTML = dict["bodyHTML"] as? String

        var usageBreakdown: [OpenAIDashboardDailyBreakdown] = []
        let usageBreakdownDebug = dict["usageBreakdownDebug"] as? String
        if let raw = dict["usageBreakdownJSON"] as? String, !raw.isEmpty {
            do {
                let decoder = JSONDecoder()
                usageBreakdown = try decoder.decode([OpenAIDashboardDailyBreakdown].self, from: Data(raw.utf8))
            } catch {
                // Best-effort parse; ignore errors to avoid blocking other dashboard data.
                usageBreakdown = []
            }
        }

        var signedInEmail = dict["signedInEmail"] as? String
        if let bodyHTML,
           signedInEmail == nil || signedInEmail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        {
            signedInEmail = OpenAIDashboardParser.parseSignedInEmailFromClientBootstrap(html: bodyHTML)
        }

        if let bodyHTML, let authStatus = OpenAIDashboardParser.parseAuthStatusFromClientBootstrap(html: bodyHTML) {
            if authStatus.lowercased() != "logged_in" {
                // When logged out, the SPA can render a generic landing shell without obvious auth inputs,
                // so treat it as login-required and let the caller retry cookie import.
                loginRequired = true
            }
        }

        return ScrapeResult(
            loginRequired: loginRequired,
            workspacePicker: workspacePicker,
            cloudflareInterstitial: cloudflareInterstitial,
            href: dict["href"] as? String,
            bodyText: dict["bodyText"] as? String,
            bodyHTML: bodyHTML,
            signedInEmail: signedInEmail,
            creditsPurchaseURL: dict["creditsPurchaseURL"] as? String,
            rows: rows,
            usageBreakdown: usageBreakdown,
            usageBreakdownDebug: usageBreakdownDebug,
            scrollY: (dict["scrollY"] as? NSNumber)?.doubleValue ?? 0,
            scrollHeight: (dict["scrollHeight"] as? NSNumber)?.doubleValue ?? 0,
            viewportHeight: (dict["viewportHeight"] as? NSNumber)?.doubleValue ?? 0,
            creditsHeaderPresent: (dict["creditsHeaderPresent"] as? Bool) ?? false,
            creditsHeaderInViewport: (dict["creditsHeaderInViewport"] as? Bool) ?? false,
            didScrollToCredits: (dict["didScrollToCredits"] as? Bool) ?? false)
    }

    private func makeWebView(
        websiteDataStore: WKWebsiteDataStore,
        logger: ((String) -> Void)?) async throws -> OpenAIDashboardWebViewLease
    {
        try await OpenAIDashboardWebViewCache.shared.acquire(
            websiteDataStore: websiteDataStore,
            usageURL: self.usageURL,
            logger: logger)
    }

    private static func writeDebugArtifacts(html: String, bodyText: String?, logger: (String) -> Void) {
        let stamp = Int(Date().timeIntervalSince1970)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let htmlURL = dir.appendingPathComponent("codex-openai-dashboard-\(stamp).html")
        do {
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            logger("Dumped HTML: \(htmlURL.path)")
        } catch {
            logger("Failed to dump HTML: \(error.localizedDescription)")
        }

        if let bodyText, !bodyText.isEmpty {
            let textURL = dir.appendingPathComponent("codex-openai-dashboard-\(stamp).txt")
            do {
                try bodyText.write(to: textURL, atomically: true, encoding: .utf8)
                logger("Dumped text: \(textURL.path)")
            } catch {
                logger("Failed to dump text: \(error.localizedDescription)")
            }
        }
    }
}

private struct OpenAIDashboardWebViewLease {
    let webView: WKWebView
    let log: (String) -> Void
    let release: () -> Void
}

@MainActor
private final class OpenAIDashboardWebViewCache {
    static let shared = OpenAIDashboardWebViewCache()

    private final class Entry {
        let webView: WKWebView
        let host: OffscreenWebViewHost
        var lastUsedAt: Date
        var isBusy: Bool

        init(webView: WKWebView, host: OffscreenWebViewHost, lastUsedAt: Date, isBusy: Bool) {
            self.webView = webView
            self.host = host
            self.lastUsedAt = lastUsedAt
            self.isBusy = isBusy
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private let idleTimeout: TimeInterval = 10 * 60

    func acquire(
        websiteDataStore: WKWebsiteDataStore,
        usageURL: URL,
        logger: ((String) -> Void)?) async throws -> OpenAIDashboardWebViewLease
    {
        let now = Date()
        self.prune(now: now)

        let log: (String) -> Void = { message in
            logger?("[webview] \(message)")
        }
        let key = ObjectIdentifier(websiteDataStore)

        if let entry = self.entries[key] {
            if entry.isBusy {
                log("Cached WebView busy; using a temporary WebView.")
                let (webView, host) = self.makeWebView(websiteDataStore: websiteDataStore)
                host.show()
                do {
                    try await self.prepareWebView(webView, usageURL: usageURL)
                } catch {
                    host.close()
                    throw error
                }
                return OpenAIDashboardWebViewLease(
                    webView: webView,
                    log: log,
                    release: { host.close() })
            }

            entry.isBusy = true
            entry.lastUsedAt = now
            entry.host.show()
            do {
                try await self.prepareWebView(entry.webView, usageURL: usageURL)
            } catch {
                entry.isBusy = false
                entry.lastUsedAt = Date()
                entry.host.hide()
                throw error
            }

            return OpenAIDashboardWebViewLease(
                webView: entry.webView,
                log: log,
                release: { [weak self, weak entry] in
                    guard let self, let entry else { return }
                    entry.isBusy = false
                    entry.lastUsedAt = Date()
                    entry.host.hide()
                    self.prune(now: Date())
                })
        }

        let (webView, host) = self.makeWebView(websiteDataStore: websiteDataStore)
        let entry = Entry(webView: webView, host: host, lastUsedAt: now, isBusy: true)
        self.entries[key] = entry
        host.show()

        do {
            try await self.prepareWebView(webView, usageURL: usageURL)
        } catch {
            self.entries.removeValue(forKey: key)
            host.close()
            throw error
        }

        return OpenAIDashboardWebViewLease(
            webView: webView,
            log: log,
            release: { [weak self, weak entry] in
                guard let self, let entry else { return }
                entry.isBusy = false
                entry.lastUsedAt = Date()
                entry.host.hide()
                self.prune(now: Date())
            })
    }

    func evict(websiteDataStore: WKWebsiteDataStore) {
        let key = ObjectIdentifier(websiteDataStore)
        guard let entry = self.entries.removeValue(forKey: key) else { return }
        entry.host.close()
    }

    private func prune(now: Date) {
        let expired = self.entries.filter { _, entry in
            !entry.isBusy && now.timeIntervalSince(entry.lastUsedAt) > self.idleTimeout
        }
        for (key, entry) in expired {
            entry.host.close()
            self.entries.removeValue(forKey: key)
        }
    }

    private func makeWebView(websiteDataStore: WKWebsiteDataStore) -> (WKWebView, OffscreenWebViewHost) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = websiteDataStore

        let webView = WKWebView(frame: .zero, configuration: config)
        let host = OffscreenWebViewHost(webView: webView)
        return (webView, host)
    }

    private func prepareWebView(_ webView: WKWebView, usageURL: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let delegate = NavigationDelegate { result in
                cont.resume(with: result)
            }
            webView.navigationDelegate = delegate
            webView.codexNavigationDelegate = delegate
            _ = webView.load(URLRequest(url: usageURL))
        }
    }
}

// MARK: - Navigation helper (revived from the old credits scraper)

@MainActor
final class NavigationDelegate: NSObject, WKNavigationDelegate {
    private let completion: (Result<Void, Error>) -> Void
    private var hasCompleted: Bool = false
    static var associationKey: UInt8 = 0

    init(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.completeOnce(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.completeOnce(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.completeOnce(.failure(error))
    }

    private func completeOnce(_ result: Result<Void, Error>) {
        guard !self.hasCompleted else { return }
        self.hasCompleted = true
        self.completion(result)
    }
}

// MARK: - Offscreen WebKit host

@MainActor
private final class OffscreenWebViewHost {
    private let window: NSWindow

    init(webView: WKWebView) {
        // WebKit throttles timers/RAF aggressively when a WKWebView is not considered "visible".
        // The Codex usage page uses streaming SSR + client hydration; if RAF is throttled, the
        // dashboard never becomes part of the visible DOM and `document.body.innerText` stays tiny.
        //
        // Keep a transparent (mouse-ignoring) window technically "on-screen" while scraping, but
        // place it almost entirely off-screen so we never ghost-render dashboard UI over the desktop.
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let frame = OpenAIDashboardFetcher.offscreenHostWindowFrame(for: visibleFrame)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        // Keep it effectively invisible, but non-zero alpha so WebKit treats it as "visible" and doesn't
        // stall hydration (we've observed a head-only HTML shell for minutes at alpha=0).
        window.alphaValue = OpenAIDashboardFetcher.offscreenHostAlphaValue()
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isExcludedFromWindowsMenu = true
        window.contentView = webView

        self.window = window
    }

    func show() {
        self.window.orderFrontRegardless()
    }

    func hide() {
        self.window.orderOut(nil)
    }

    func close() {
        self.window.orderOut(nil)
        self.window.close()
    }
}

extension WKWebView {
    var codexNavigationDelegate: NavigationDelegate? {
        get {
            objc_getAssociatedObject(self, &NavigationDelegate.associationKey) as? NavigationDelegate
        }
        set {
            objc_setAssociatedObject(
                self,
                &NavigationDelegate.associationKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

private let openAIDashboardScrapeScript = """

    (() => {
      const textOf = el => {
        const raw = el && (el.innerText || el.textContent) ? String(el.innerText || el.textContent) : '';
        return raw.trim();
      };
      const parseHexColor = (color) => {
        if (!color) return null;
        const c = String(color).trim().toLowerCase();
        if (c.startsWith('#')) {
          if (c.length === 4) {
            return '#' + c[1] + c[1] + c[2] + c[2] + c[3] + c[3];
          }
          if (c.length === 7) return c;
          return c;
        }
        const m = c.match(/^rgba?\\(([^)]+)\\)$/);
        if (m) {
          const parts = m[1].split(',').map(x => parseFloat(x.trim())).filter(x => Number.isFinite(x));
          if (parts.length >= 3) {
            const r = Math.max(0, Math.min(255, Math.round(parts[0])));
            const g = Math.max(0, Math.min(255, Math.round(parts[1])));
            const b = Math.max(0, Math.min(255, Math.round(parts[2])));
            const toHex = n => n.toString(16).padStart(2, '0');
            return '#' + toHex(r) + toHex(g) + toHex(b);
          }
        }
        return c;
      };
      const reactPropsOf = (el) => {
        if (!el) return null;
        try {
          const keys = Object.keys(el);
          const propsKey = keys.find(k => k.startsWith('__reactProps$'));
          if (propsKey) return el[propsKey] || null;
          const fiberKey = keys.find(k => k.startsWith('__reactFiber$'));
          if (fiberKey) {
            const fiber = el[fiberKey];
            return (fiber && (fiber.memoizedProps || fiber.pendingProps)) || null;
          }
        } catch {}
        return null;
      };
      const reactFiberOf = (el) => {
        if (!el) return null;
        try {
          const keys = Object.keys(el);
          const fiberKey = keys.find(k => k.startsWith('__reactFiber$'));
          return fiberKey ? (el[fiberKey] || null) : null;
        } catch {
          return null;
        }
      };
      const nestedBarMetaOf = (root) => {
        if (!root || typeof root !== 'object') return null;
        const queue = [root];
        const seen = typeof WeakSet !== 'undefined' ? new WeakSet() : null;
        let steps = 0;
        while (queue.length && steps < 250) {
          const cur = queue.shift();
          steps++;
          if (!cur || typeof cur !== 'object') continue;
          if (seen) {
            if (seen.has(cur)) continue;
            seen.add(cur);
          }
          if (cur.payload && (cur.dataKey || cur.name || cur.value !== undefined)) return cur;
          const values = Array.isArray(cur) ? cur : Object.values(cur);
          for (const v of values) {
            if (v && typeof v === 'object') queue.push(v);
          }
        }
        return null;
      };
      const barMetaFromElement = (el) => {
        const direct = reactPropsOf(el);
        if (direct && direct.payload && (direct.dataKey || direct.name || direct.value !== undefined)) return direct;

        const fiber = reactFiberOf(el);
        if (fiber) {
          let cur = fiber;
          for (let i = 0; i < 10 && cur; i++) {
            const props = (cur.memoizedProps || cur.pendingProps) || null;
            if (props && props.payload && (props.dataKey || props.name || props.value !== undefined)) return props;
            const nested = props ? nestedBarMetaOf(props) : null;
            if (nested) return nested;
            cur = cur.return || null;
          }
        }

        if (direct) {
          const nested = nestedBarMetaOf(direct);
          if (nested) return nested;
        }
        return null;
      };
      const normalizeHref = (raw) => {
        if (!raw) return null;
        const href = String(raw).trim();
        if (!href) return null;
        if (href.startsWith('http://') || href.startsWith('https://')) return href;
        if (href.startsWith('//')) return window.location.protocol + href;
        if (href.startsWith('/')) return window.location.origin + href;
        return window.location.origin + '/' + href;
      };
      const isLikelyCreditsURL = (raw) => {
        if (!raw) return false;
        try {
          const url = new URL(raw, window.location.origin);
          if (!url.host || !url.host.includes('chatgpt.com')) return false;
          const path = url.pathname.toLowerCase();
          return (
            path.includes('settings') ||
            path.includes('usage') ||
            path.includes('billing') ||
            path.includes('credits')
          );
        } catch {
          return false;
        }
      };
      const purchaseTextMatches = (text) => {
        const lower = String(text || '').trim().toLowerCase();
        if (!lower) return false;
        if (lower.includes('add more')) return true;
        if (!lower.includes('credit')) return false;
        return (
          lower.includes('buy') ||
          lower.includes('add') ||
          lower.includes('purchase') ||
          lower.includes('top up') ||
          lower.includes('top-up')
        );
      };
      const elementLabel = (el) => {
        if (!el) return '';
        return (
          textOf(el) ||
          el.getAttribute('aria-label') ||
          el.getAttribute('title') ||
          ''
        );
      };
      const urlFromProps = (props) => {
        if (!props || typeof props !== 'object') return null;
        const candidates = [
          props.href,
          props.to,
          props.url,
          props.link,
          props.destination,
          props.navigateTo
        ];
        for (const candidate of candidates) {
          if (typeof candidate === 'string' && candidate.trim()) {
            return normalizeHref(candidate);
          }
        }
        return null;
      };
      const purchaseURLFromElement = (el) => {
        if (!el) return null;
        const isAnchor = el.tagName && el.tagName.toLowerCase() === 'a';
        const anchor = isAnchor ? el : (el.closest ? el.closest('a') : null);
        const anchorHref = anchor ? anchor.getAttribute('href') : null;
        const dataHref = el.getAttribute
          ? (el.getAttribute('data-href') ||
            el.getAttribute('data-url') ||
            el.getAttribute('data-link') ||
            el.getAttribute('data-destination'))
          : null;
        const propHref = urlFromProps(reactPropsOf(el)) || urlFromProps(reactPropsOf(anchor));
        const normalized = normalizeHref(anchorHref || dataHref || propHref);
        return normalized && isLikelyCreditsURL(normalized) ? normalized : null;
      };
      const pickLikelyPurchaseButton = (buttons) => {
        if (!buttons || buttons.length === 0) return null;
        const labeled = buttons.find(btn => {
          const label = elementLabel(btn);
          if (purchaseTextMatches(label)) return true;
          const aria = String(btn.getAttribute('aria-label') || '').toLowerCase();
          return aria.includes('credit') || aria.includes('buy') || aria.includes('add');
        });
        return labeled || buttons[0];
      };
      const findCreditsPurchaseButton = () => {
        const nodes = Array.from(document.querySelectorAll('h1,h2,h3,div,span,p'));
        const labelMatch = nodes.find(node => {
          const lower = textOf(node).toLowerCase();
          return lower === 'credits remaining' || (lower.includes('credits') && lower.includes('remaining'));
        });
        if (!labelMatch) return null;
        let cur = labelMatch;
        for (let i = 0; i < 6 && cur; i++) {
          const buttons = Array.from(cur.querySelectorAll('button, a'));
          const picked = pickLikelyPurchaseButton(buttons);
          if (picked) return picked;
          cur = cur.parentElement;
        }
        return null;
      };
      const dayKeyFromPayload = (payload) => {
        if (!payload || typeof payload !== 'object') return null;
        const keys = ['day', 'date', 'name', 'label', 'x', 'time', 'timestamp'];
        for (const k of keys) {
          const v = payload[k];
          if (typeof v === 'string') {
            const s = v.trim();
            if (/^\\d{4}-\\d{2}-\\d{2}$/.test(s)) return s;
            const iso = s.match(/^(\\d{4}-\\d{2}-\\d{2})/);
            if (iso) return iso[1];
          }
          if (typeof v === 'number' && Number.isFinite(v) && (k === 'timestamp' || k === 'time' || k === 'x')) {
            try {
              const d = new Date(v);
              if (!isNaN(d.getTime())) return d.toISOString().slice(0, 10);
            } catch {}
          }
        }
        return null;
      };
      const displayNameForUsageServiceKey = (raw) => {
        const key = raw === null || raw === undefined ? '' : String(raw).trim();
        if (!key) return key;
        if (key.toUpperCase() === key && key.length <= 6) return key;
        const lower = key.toLowerCase();
        if (lower === 'cli') return 'CLI';
        if (lower.includes('github') && lower.includes('review')) return 'GitHub Code Review';
        const words = lower.replace(/[_-]+/g, ' ').split(' ').filter(Boolean);
        return words.map(w => w.length <= 2 ? w.toUpperCase() : w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
      };
      const usageBreakdownJSON = (() => {
        try {
          if (window.__codexbarUsageBreakdownJSON) return window.__codexbarUsageBreakdownJSON;

          const sections = Array.from(document.querySelectorAll('section'));
          const usageSection = sections.find(s => {
            const h2 = s.querySelector('h2');
            return h2 && textOf(h2).toLowerCase().startsWith('usage breakdown');
          });
          if (!usageSection) return null;

          const legendMap = {};
          try {
            const legendItems = Array.from(usageSection.querySelectorAll('div[title]'));
            for (const item of legendItems) {
              const title = item.getAttribute('title') ? String(item.getAttribute('title')).trim() : '';
              const square = item.querySelector('div[style*=\"background-color\"]');
              const color = (square && square.style && square.style.backgroundColor)
                ? square.style.backgroundColor
                : null;
              const hex = parseHexColor(color);
              if (title && hex) legendMap[hex] = title;
            }
          } catch {}

          const totalsByDay = {}; // day -> service -> value
          const paths = Array.from(usageSection.querySelectorAll('g.recharts-bar-rectangle path.recharts-rectangle'));
          let debug = {
            pathCount: paths.length,
            sampleReactKeys: null,
            sampleMetaKeys: null,
            samplePayloadKeys: null,
            sampleValuesKeys: null,
            sampleDayKey: null
          };
          try {
            const sample = paths[0] || null;
            if (sample) {
              const names = Object.getOwnPropertyNames(sample);
              debug.sampleReactKeys = names.filter(k => k.includes('react')).slice(0, 10);
              const metaSample = barMetaFromElement(sample) || barMetaFromElement(sample.parentElement) || null;
              if (metaSample) {
                debug.sampleMetaKeys = Object.keys(metaSample).slice(0, 12);
                const payload = metaSample.payload || null;
                if (payload && typeof payload === 'object') {
                  debug.samplePayloadKeys = Object.keys(payload).slice(0, 12);
                  debug.sampleDayKey = dayKeyFromPayload(payload);
                  const values = payload.values || null;
                  if (values && typeof values === 'object') {
                    debug.sampleValuesKeys = Object.keys(values).slice(0, 12);
                  }
                }
              }
            }
          } catch {}
          for (const path of paths) {
            const meta = barMetaFromElement(path) || barMetaFromElement(path.parentElement) || null;
            if (!meta) continue;

            const payload = meta.payload || null;
            const day = dayKeyFromPayload(payload);
            if (!day) continue;

            const valuesObj = (payload && payload.values && typeof payload.values === 'object') ? payload.values : null;
            if (valuesObj) {
              if (!totalsByDay[day]) totalsByDay[day] = {};
              for (const [k, v] of Object.entries(valuesObj)) {
                if (typeof v !== 'number' || !Number.isFinite(v) || v <= 0) continue;
                const service = displayNameForUsageServiceKey(k);
                if (!service) continue;
                totalsByDay[day][service] = (totalsByDay[day][service] || 0) + v;
              }
              continue;
            }

            let value = null;
            if (typeof meta.value === 'number' && Number.isFinite(meta.value)) value = meta.value;
            if (value === null && typeof meta.value === 'string') {
              const v = parseFloat(meta.value.replace(/,/g, ''));
              if (Number.isFinite(v)) value = v;
            }
            if (value === null) continue;

            const fill = parseHexColor(meta.fill || path.getAttribute('fill'));
            const service =
              (fill && legendMap[fill]) ||
              (typeof meta.name === 'string' && meta.name) ||
              null;
            if (!service) continue;

            if (!totalsByDay[day]) totalsByDay[day] = {};
            totalsByDay[day][service] = (totalsByDay[day][service] || 0) + value;
          }

          const dayKeys = Object.keys(totalsByDay).sort((a, b) => b.localeCompare(a)).slice(0, 30);
          const breakdown = dayKeys.map(day => {
            const servicesMap = totalsByDay[day] || {};
            const services = Object.keys(servicesMap).map(service => ({
              service,
              creditsUsed: servicesMap[service]
            })).sort((a, b) => {
              if (a.creditsUsed === b.creditsUsed) return a.service.localeCompare(b.service);
              return b.creditsUsed - a.creditsUsed;
            });
            const totalCreditsUsed = services.reduce((sum, s) => sum + (Number(s.creditsUsed) || 0), 0);
            return { day, services, totalCreditsUsed };
          });

          const json = (breakdown.length > 0) ? JSON.stringify(breakdown) : null;
          window.__codexbarUsageBreakdownJSON = json;
          window.__codexbarUsageBreakdownDebug = json ? null : JSON.stringify(debug);
          return json;
        } catch {
          return null;
        }
      })();
      const usageBreakdownDebug = (() => {
        try {
          return window.__codexbarUsageBreakdownDebug || null;
        } catch {
          return null;
        }
      })();
      const bodyText = document.body ? String(document.body.innerText || '').trim() : '';
      const href = window.location ? String(window.location.href || '') : '';
      const workspacePicker = bodyText.includes('Select a workspace');
      const title = document.title ? String(document.title || '') : '';
      const cloudflareInterstitial =
        title.toLowerCase().includes('just a moment') ||
        bodyText.toLowerCase().includes('checking your browser') ||
        bodyText.toLowerCase().includes('cloudflare');
      const authSelector = [
        'input[type="email"]',
        'input[type="password"]',
        'input[name="username"]'
      ].join(', ');
      const hasAuthInputs = !!document.querySelector(authSelector);
      const lower = bodyText.toLowerCase();
      const loginCTA =
        lower.includes('sign in') ||
        lower.includes('log in') ||
        lower.includes('continue with google') ||
        lower.includes('continue with apple') ||
        lower.includes('continue with microsoft');
      const loginRequired =
        href.includes('/auth/') ||
        href.includes('/login') ||
        (hasAuthInputs && loginCTA) ||
        (!hasAuthInputs && loginCTA && href.includes('chatgpt.com'));
      const scrollY = (typeof window.scrollY === 'number') ? window.scrollY : 0;
      const scrollHeight = document.documentElement ? (document.documentElement.scrollHeight || 0) : 0;
      const viewportHeight = (typeof window.innerHeight === 'number') ? window.innerHeight : 0;

      let creditsHeaderPresent = false;
      let creditsHeaderInViewport = false;
      let didScrollToCredits = false;
      let rows = [];
      try {
        const headings = Array.from(document.querySelectorAll('h1,h2,h3'));
        const header = headings.find(h => textOf(h).toLowerCase() === 'credits usage history');
        if (header) {
          creditsHeaderPresent = true;
          const rect = header.getBoundingClientRect();
          creditsHeaderInViewport = rect.top >= 0 && rect.top <= viewportHeight;

          // Only scrape rows from the *credits usage history* table. The page can contain other tables,
          // and treating any <table> as credits history can prevent our scroll-to-load logic from running.
          const container = header.closest('section') || header.parentElement || document;
          const table = container.querySelector('table') || null;
          const scope = table || container;
          rows = Array.from(scope.querySelectorAll('tbody tr')).map(tr => {
            const cells = Array.from(tr.querySelectorAll('td')).map(td => textOf(td));
            return cells;
          }).filter(r => r.length >= 3);
          if (rows.length === 0 && !window.__codexbarDidScrollToCredits) {
            window.__codexbarDidScrollToCredits = true;
            // If the table is virtualized/lazy-loaded, we need to scroll to trigger rendering even if the
            // header is already in view.
            header.scrollIntoView({ block: 'start', inline: 'nearest' });
            if (creditsHeaderInViewport) {
              window.scrollBy(0, Math.max(220, viewportHeight * 0.6));
            }
            didScrollToCredits = true;
          }
        } else if (rows.length === 0 && !window.__codexbarDidScrollToCredits && scrollHeight > viewportHeight * 1.5) {
          // The credits history section often isn't part of the DOM until you scroll down. Nudge the page
          // once so subsequent scrapes can find the header and rows.
          window.__codexbarDidScrollToCredits = true;
          window.scrollTo(0, Math.max(0, scrollHeight - viewportHeight - 40));
          didScrollToCredits = true;
        }
      } catch {}

      let creditsPurchaseURL = null;
      try {
        const creditsButton = findCreditsPurchaseButton();
        if (creditsButton) {
          const url = purchaseURLFromElement(creditsButton);
          if (url) creditsPurchaseURL = url;
        }
        const candidates = Array.from(document.querySelectorAll('a, button'));
        for (const node of candidates) {
          const label = elementLabel(node);
          if (!purchaseTextMatches(label)) continue;
          const url = purchaseURLFromElement(node);
          if (url) {
            creditsPurchaseURL = url;
            break;
          }
        }
        if (!creditsPurchaseURL) {
          const anchors = Array.from(document.querySelectorAll('a[href]'));
          for (const anchor of anchors) {
            const label = elementLabel(anchor);
            const href = anchor.getAttribute('href') || '';
            const hrefLooksRelevant = /credits|billing/i.test(href);
            if (!hrefLooksRelevant && !purchaseTextMatches(label)) continue;
            const url = normalizeHref(href);
            if (url) {
              creditsPurchaseURL = url;
              break;
            }
          }
        }
      } catch {}

      let signedInEmail = null;
      try {
        const next = window.__NEXT_DATA__ || null;
        const props = (next && next.props && next.props.pageProps) ? next.props.pageProps : null;
        const userEmail = (props && props.user) ? props.user.email : null;
        const sessionEmail = (props && props.session && props.session.user) ? props.session.user.email : null;
        signedInEmail = userEmail || sessionEmail || null;
      } catch {}

      if (!signedInEmail) {
        try {
          const node = document.getElementById('__NEXT_DATA__');
          const raw = node && node.textContent ? String(node.textContent) : '';
          if (raw) {
            const obj = JSON.parse(raw);
            const queue = [obj];
            let seen = 0;
            while (queue.length && seen < 2000 && !signedInEmail) {
              const cur = queue.shift();
              seen++;
              if (!cur) continue;
              if (typeof cur === 'string') {
                if (cur.includes('@')) signedInEmail = cur;
                continue;
              }
              if (typeof cur !== 'object') continue;
              for (const [k, v] of Object.entries(cur)) {
                if (signedInEmail) break;
                if (k === 'email' && typeof v === 'string' && v.includes('@')) {
                  signedInEmail = v;
                  break;
                }
                if (typeof v === 'object' && v) queue.push(v);
              }
            }
          }
        } catch {}
      }

      if (!signedInEmail) {
        try {
          const emailRe = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}/ig;
          const found = (bodyText.match(emailRe) || []).map(x => String(x).trim().toLowerCase());
          const unique = Array.from(new Set(found));
          if (unique.length === 1) {
            signedInEmail = unique[0];
          } else if (unique.length > 1) {
            signedInEmail = unique[0];
          }
        } catch {}
      }

      if (!signedInEmail) {
        // Last resort: open the account menu so the email becomes part of the DOM text.
        try {
          const emailRe = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}/ig;
          const hasMenu = Boolean(document.querySelector('[role="menu"]'));
          if (!hasMenu) {
            const button =
              document.querySelector('button[aria-haspopup="menu"]') ||
              document.querySelector('button[aria-expanded]');
            if (button && !button.disabled) {
              button.click();
            }
          }
          const afterText = document.body ? String(document.body.innerText || '').trim() : '';
          const found = (afterText.match(emailRe) || []).map(x => String(x).trim().toLowerCase());
          const unique = Array.from(new Set(found));
          if (unique.length === 1) {
            signedInEmail = unique[0];
          } else if (unique.length > 1) {
            signedInEmail = unique[0];
          }
        } catch {}
      }

      return {
        loginRequired,
        workspacePicker,
        cloudflareInterstitial,
        href,
        bodyText,
        bodyHTML: document.documentElement ? String(document.documentElement.outerHTML || '') : '',
        signedInEmail,
        creditsPurchaseURL,
        rows,
        usageBreakdownJSON,
        usageBreakdownDebug,
        scrollY,
        scrollHeight,
        viewportHeight,
        creditsHeaderPresent,
        creditsHeaderInViewport,
        didScrollToCredits
      };
    })();
    
"""
