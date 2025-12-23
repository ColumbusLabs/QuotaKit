import AppKit
import CodexBarCore
import OSLog
import WebKit

@MainActor
final class OpenAICreditsPurchaseWindowController: NSWindowController, WKNavigationDelegate {
    private static let defaultSize = NSSize(width: 980, height: 760)
    private static let autoStartScript = """
    (() => {
      if (window.__codexbarAutoBuyCreditsStarted) return 'already';
      const textOf = el => {
        const raw = el && (el.innerText || el.textContent) ? String(el.innerText || el.textContent) : '';
        return raw.trim();
      };
      const matches = text => {
        const lower = String(text || '').toLowerCase();
        if (!lower.includes('credit')) return false;
        return (
          lower.includes('buy') ||
          lower.includes('add') ||
          lower.includes('purchase') ||
          lower.includes('top up') ||
          lower.includes('top-up')
        );
      };
      const labelFor = el => {
        if (!el) return '';
        return textOf(el) || el.getAttribute('aria-label') || el.getAttribute('title') || '';
      };
      const pickLikelyButton = (buttons) => {
        if (!buttons || buttons.length === 0) return null;
        const labeled = buttons.find(btn => {
          const label = labelFor(btn);
          if (matches(label)) return true;
          const aria = String(btn.getAttribute('aria-label') || '').toLowerCase();
          return aria.includes('credit') || aria.includes('buy') || aria.includes('add');
        });
        return labeled || buttons[0];
      };
      const findCreditsCardButton = () => {
        const nodes = Array.from(document.querySelectorAll('h1,h2,h3,div,span,p'));
        const labelMatch = nodes.find(node => {
          const lower = textOf(node).toLowerCase();
          return lower === 'credits remaining' || (lower.includes('credits') && lower.includes('remaining'));
        });
        if (!labelMatch) return null;
        let cur = labelMatch;
        for (let i = 0; i < 6 && cur; i++) {
          const buttons = Array.from(cur.querySelectorAll('button, a'));
          const picked = pickLikelyButton(buttons);
          if (picked) return picked;
          cur = cur.parentElement;
        }
        return null;
      };
      const findAndClick = () => {
        const cardButton = findCreditsCardButton();
        if (cardButton) {
          cardButton.click();
          return true;
        }
        const candidates = Array.from(document.querySelectorAll('button, a'));
        for (const node of candidates) {
          const label = labelFor(node);
          if (!matches(label)) continue;
          node.click();
          return true;
        }
        return false;
      };
      if (findAndClick()) {
        window.__codexbarAutoBuyCreditsStarted = true;
        return 'clicked';
      }
      let attempts = 0;
      const maxAttempts = 14;
      const timer = setInterval(() => {
        attempts += 1;
        if (findAndClick() || attempts >= maxAttempts) {
          clearInterval(timer);
        }
      }, 500);
      window.__codexbarAutoBuyCreditsStarted = true;
      return 'scheduled';
    })();
    """

    private let logger = Logger(subsystem: "com.steipete.codexbar", category: "creditsPurchase")
    private var webView: WKWebView?
    private var accountEmail: String?
    private var pendingAutoStart = false

    init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(purchaseURL: URL, accountEmail: String?, autoStartPurchase: Bool) {
        let normalizedEmail = Self.normalizeEmail(accountEmail)
        if self.window == nil || normalizedEmail != self.accountEmail {
            self.accountEmail = normalizedEmail
            self.buildWindow()
        }
        self.pendingAutoStart = autoStartPurchase
        self.load(url: purchaseURL)
        self.window?.center()
        self.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = OpenAIDashboardWebsiteDataStore.store(forAccountEmail: self.accountEmail)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: .zero)
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: Self.defaultFrame(),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Buy Credits"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentView = container
        window.center()

        self.window = window
        self.webView = webView
    }

    private func load(url: URL) {
        guard let webView else { return }
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.pendingAutoStart else { return }
        self.pendingAutoStart = false
        webView.evaluateJavaScript(Self.autoStartScript) { [logger] result, error in
            if let error {
                logger.debug("Auto-start purchase failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            if let result {
                logger.debug("Auto-start purchase result: \(String(describing: result), privacy: .public)")
            }
        }
    }

    private static func normalizeEmail(_ email: String?) -> String? {
        guard let raw = email?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.lowercased()
    }

    private static func defaultFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let width = min(Self.defaultSize.width, visible.width * 0.92)
        let height = min(Self.defaultSize.height, visible.height * 0.88)
        let origin = NSPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }
}
