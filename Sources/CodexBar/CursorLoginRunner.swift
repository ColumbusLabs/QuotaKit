import AppKit
import CodexBarCore
import Foundation
import WebKit

/// Handles Cursor login flow using a WebKit-based browser window.
/// Captures session cookies after successful authentication.
@MainActor
final class CursorLoginRunner: NSObject {
    override nonisolated(unsafe) var hash: Int {
        ObjectIdentifier(self).hashValue
    }

    override nonisolated(unsafe) func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CursorLoginRunner else { return false }
        return ObjectIdentifier(self) == ObjectIdentifier(other)
    }
    enum Phase: Sendable {
        case loading
        case waitingLogin
        case success
        case failed(String)
    }

    struct Result: Sendable {
        enum Outcome: Sendable {
            case success
            case cancelled
            case failed(String)
        }

        let outcome: Outcome
        let email: String?
    }

    private var webView: WKWebView?
    private var window: NSWindow?
    private var continuation: CheckedContinuation<Result, Never>?
    private var phaseCallback: ((Phase) -> Void)?
    private var hasCompletedLogin = false
    private var cleanupScheduled = false

    // Keep runners alive until after cleanup to avoid x86_64 autorelease crashes
    private static var activeRunners: Set<CursorLoginRunner> = []
#if arch(x86_64)
    private static let retainRunnersAfterCleanup = true
#else
    private static let retainRunnersAfterCleanup = false
#endif
    private static let cleanupDelay: TimeInterval = 0.25
    private static let releasePollInterval: TimeInterval = 0.2
    private static let releaseMinimumDelay: TimeInterval = 2.0
#if arch(x86_64)
    private static let releaseMaximumDelay: TimeInterval = 8.0
#else
    private static let releaseMaximumDelay: TimeInterval = 2.0
#endif

    private static let dashboardURL = URL(string: "https://cursor.com/dashboard")!
    private static let loginURLPattern = "authenticator.cursor.sh"

    /// Runs the Cursor login flow in a browser window.
    /// Returns the result after the user completes login or cancels.
    func run(onPhaseChange: @escaping @Sendable (Phase) -> Void) async -> Result {
        // Keep this instance alive during the flow
        Self.activeRunners.insert(self)

        self.phaseCallback = onPhaseChange
        onPhaseChange(.loading)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.setupWindow()
        }
    }

    private func setupWindow() {
        // Use a non-persistent store for the login flow; cookies are persisted explicitly.
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Cursor Login"
        window.contentView = webView
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window

        // Navigate to dashboard (will redirect to login if not authenticated)
        let request = URLRequest(url: Self.dashboardURL)
        webView.load(request)
    }

    private func complete(with result: Result) {
        guard let continuation = self.continuation else { return }
        self.continuation = nil
        self.scheduleCleanup()
        continuation.resume(returning: result)
    }

    private func scheduleCleanup() {
        guard !self.cleanupScheduled else { return }
        self.cleanupScheduled = true
        Task { @MainActor in
            // Let WebKit unwind delegate callbacks before teardown on Intel.
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.nanoseconds(Self.cleanupDelay))
            self.cleanup()
        }
    }

    private func cleanup() {
        // Stop any pending WebView operations
        self.webView?.stopLoading()

        // Clear delegates to prevent callbacks during teardown
        self.webView?.navigationDelegate = nil
        self.window?.delegate = nil

        // Hide the window; Intel builds retain runners to avoid WebKit teardown crashes.
        if Self.retainRunnersAfterCleanup {
            self.window?.orderOut(nil)
        } else {
            self.window?.close()
        }

        // DON'T nil the references - let ARC clean them up when this instance is deallocated
        // This avoids autorelease pool over-release crashes on x86_64

        // Release the strong reference once the window is no longer in play,
        // with a minimum delay and a safety maximum to avoid leaks.
        self.scheduleRelease()
    }

    private func scheduleRelease() {
        Task { @MainActor in
            let start = Date()
            while true {
                let elapsed = Date().timeIntervalSince(start)
                let windowVisible = self.window?.isVisible ?? false
                let webViewLoading = self.webView?.isLoading ?? false
                let inPlay = windowVisible || webViewLoading
                if elapsed >= Self.releaseMaximumDelay || (!inPlay && elapsed >= Self.releaseMinimumDelay) {
                    break
                }
                try? await Task.sleep(nanoseconds: Self.nanoseconds(Self.releasePollInterval))
            }
            Self.activeRunners.remove(self)
        }
    }

    private static func nanoseconds(_ interval: TimeInterval) -> UInt64 {
        UInt64(interval * 1_000_000_000)
    }

    private func captureSessionCookies() async {
        guard let webView = self.webView else { return }

        let dataStore = webView.configuration.websiteDataStore
        let cookies = await dataStore.httpCookieStore.allCookies()

        // Filter for cursor.com cookies
        let cursorCookies = cookies.filter { cookie in
            cookie.domain.contains("cursor.com") || cookie.domain.contains("cursor.sh")
        }

        guard !cursorCookies.isEmpty else {
            self.phaseCallback?(.failed("No session cookies found"))
            self.complete(with: Result(outcome: .failed("No session cookies found"), email: nil))
            return
        }

        // Save cookies to the session store
        await CursorSessionStore.shared.setCookies(cursorCookies)

        // Try to get user email
        let email = await self.fetchUserEmail()

        self.hasCompletedLogin = true
        self.phaseCallback?(.success)
        self.complete(with: Result(outcome: .success, email: email))
    }

    private func fetchUserEmail() async -> String? {
        do {
            let probe = CursorStatusProbe()
            let snapshot = try await probe.fetch()
            return snapshot.accountEmail
        } catch {
            return nil
        }
    }
}

// MARK: - WKNavigationDelegate

extension CursorLoginRunner: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let url = webView.url else { return }

            let urlString = url.absoluteString

            // Check if on login page
            if urlString.contains(Self.loginURLPattern) {
                self.phaseCallback?(.waitingLogin)
                return
            }

            // Check if on dashboard (login successful)
            if urlString.contains("cursor.com/dashboard"), !self.hasCompletedLogin {
                await self.captureSessionCookies()
            }
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!)
    {
        Task { @MainActor in
            guard let url = webView.url else { return }
            let urlString = url.absoluteString

            // Detect redirect to dashboard after login
            if urlString.contains("cursor.com/dashboard"), !self.hasCompletedLogin {
                // Wait a moment for cookies to be set, then capture
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self.captureSessionCookies()
            }
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error)
    {
        Task { @MainActor in
            self.phaseCallback?(.failed(error.localizedDescription))
            self.complete(with: Result(outcome: .failed(error.localizedDescription), email: nil))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error)
    {
        Task { @MainActor in
            // Ignore cancelled navigations (common during redirects)
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return
            }
            self.phaseCallback?(.failed(error.localizedDescription))
            self.complete(with: Result(outcome: .failed(error.localizedDescription), email: nil))
        }
    }
}

// MARK: - NSWindowDelegate

extension CursorLoginRunner: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            if !self.hasCompletedLogin {
                self.complete(with: Result(outcome: .cancelled, email: nil))
            }
        }
    }
}
