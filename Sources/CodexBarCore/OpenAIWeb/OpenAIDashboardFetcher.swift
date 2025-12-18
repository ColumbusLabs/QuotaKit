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
        let (webView, host, log) = try await self.makeWebView(websiteDataStore: websiteDataStore, logger: logger)
        defer { host.close() }

        let deadline = Date().addingTimeInterval(timeout)
        var lastBody: String?
        var lastHTML: String?
        var lastHref: String?
        var lastFlags: (loginRequired: Bool, workspacePicker: Bool, cloudflare: Bool)?
        var codeReviewFirstSeenAt: Date?
        var creditsHeaderVisibleAt: Date?
        var lastUsageBreakdownDebug: String?

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
            if codeReview != nil, usageBreakdown.isEmpty,
               let debug = scrape.usageBreakdownDebug, !debug.isEmpty,
               debug != lastUsageBreakdownDebug
            {
                lastUsageBreakdownDebug = debug
                log("usage breakdown debug: \(debug)")
            }
            if codeReview != nil, events.isEmpty {
                log(
                    "credits header present=\(scrape.creditsHeaderPresent) " +
                        "inViewport=\(scrape.creditsHeaderInViewport) didScroll=\(scrape.didScrollToCredits) " +
                        "rows=\(scrape.rows.count)")
                if scrape.didScrollToCredits {
                    log("scrollIntoView(Credits usage history) requested; waiting…")
                    try? await Task.sleep(for: .milliseconds(600))
                    continue
                }

                // Give the (often virtualized) credits table a moment to render after hydration/scroll.
                let elapsed = Date().timeIntervalSince(codeReviewFirstSeenAt ?? Date())
                if scrape.creditsHeaderPresent, scrape.creditsHeaderInViewport {
                    if creditsHeaderVisibleAt == nil { creditsHeaderVisibleAt = Date() }
                    if Date().timeIntervalSince(creditsHeaderVisibleAt ?? Date()) < 2.5 {
                        try? await Task.sleep(for: .milliseconds(400))
                        continue
                    }
                } else if elapsed < 8 {
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
                    updatedAt: Date())
            }

            try? await Task.sleep(for: .milliseconds(500))
        }

        if debugDumpHTML, let html = lastHTML {
            Self.writeDebugArtifacts(html: html, bodyText: lastBody, logger: log)
        }
        throw FetchError.noDashboardData(body: lastBody ?? "")
    }

    public func clearSessionData(accountEmail: String?) async {
        await OpenAIDashboardWebsiteDataStore.clearStore(forAccountEmail: accountEmail)
    }

    public func probeUsagePage(
        websiteDataStore: WKWebsiteDataStore,
        logger: ((String) -> Void)? = nil,
        timeout: TimeInterval = 30) async throws -> ProbeResult
    {
        let (webView, host, log) = try await self.makeWebView(websiteDataStore: websiteDataStore, logger: logger)
        defer { host.close() }

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
        let any = try await webView.evaluateJavaScript(Self.scrapeScript)
        guard let dict = any as? [String: Any] else {
            return ScrapeResult(
                loginRequired: true,
                workspacePicker: false,
                cloudflareInterstitial: false,
                href: nil,
                bodyText: nil,
                bodyHTML: nil,
                signedInEmail: nil,
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

    private static let scrapeScript = """
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
      const rows = Array.from(document.querySelectorAll('table tbody tr')).map(tr => {
        const cells = Array.from(tr.querySelectorAll('td')).map(td => textOf(td));
        return cells;
      }).filter(r => r.length >= 3);
      const scrollY = (typeof window.scrollY === 'number') ? window.scrollY : 0;
      const scrollHeight = document.documentElement ? (document.documentElement.scrollHeight || 0) : 0;
      const viewportHeight = (typeof window.innerHeight === 'number') ? window.innerHeight : 0;

      let creditsHeaderPresent = false;
      let creditsHeaderInViewport = false;
      let didScrollToCredits = false;
      try {
        const headings = Array.from(document.querySelectorAll('h1,h2,h3'));
        const header = headings.find(h => textOf(h).toLowerCase() === 'credits usage history');
        if (header) {
          creditsHeaderPresent = true;
          const rect = header.getBoundingClientRect();
          creditsHeaderInViewport = rect.top >= 0 && rect.top <= viewportHeight;
          if (!creditsHeaderInViewport && rows.length === 0 && !window.__codexbarDidScrollToCredits) {
            window.__codexbarDidScrollToCredits = true;
            header.scrollIntoView({ block: 'start', inline: 'nearest' });
            didScrollToCredits = true;
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

    private func makeWebView(
        websiteDataStore: WKWebsiteDataStore,
        logger: ((String) -> Void)?) async throws -> (WKWebView, OffscreenWebViewHost, (String) -> Void)
    {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = websiteDataStore

        let webView = WKWebView(frame: .zero, configuration: config)
        let host = OffscreenWebViewHost(webView: webView)
        let log: (String) -> Void = { message in
            logger?("[webview] \(message)")
        }
        _ = webView.load(URLRequest(url: self.usageURL))

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let delegate = NavigationDelegate { result in
                cont.resume(with: result)
            }
            webView.navigationDelegate = delegate
            webView.codexNavigationDelegate = delegate
        }

        return (webView, host, log)
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
        // Keep a transparent (mouse-ignoring) window *on-screen* for a short time while scraping.
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let width: CGFloat = min(1200, visibleFrame.width)
        let height: CGFloat = min(1600, visibleFrame.height)
        let frame = NSRect(x: visibleFrame.maxX - width, y: visibleFrame.minY, width: width, height: height)
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
        window.alphaValue = 0.01
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isExcludedFromWindowsMenu = true
        window.contentView = webView
        window.orderFrontRegardless()

        self.window = window
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
