import Foundation
import WebKit

@MainActor
public struct OpenAIDashboardBrowserCookieImporter {
    public struct FoundAccount: Sendable, Hashable {
        public let sourceLabel: String
        public let email: String

        public init(sourceLabel: String, email: String) {
            self.sourceLabel = sourceLabel
            self.email = email
        }
    }

    public enum ImportError: LocalizedError {
        case noCookiesFound
        case dashboardStillRequiresLogin
        case noMatchingAccount(found: [FoundAccount])

        public var errorDescription: String? {
            switch self {
            case .noCookiesFound:
                return "No browser cookies found."
            case .dashboardStillRequiresLogin:
                return "Browser cookies imported, but dashboard still requires login."
            case let .noMatchingAccount(found):
                if found.isEmpty { return "No matching OpenAI web session found in browsers." }
                let display = found
                    .sorted { lhs, rhs in
                        if lhs.sourceLabel == rhs.sourceLabel { return lhs.email < rhs.email }
                        return lhs.sourceLabel < rhs.sourceLabel
                    }
                    .map { "\($0.sourceLabel)=\($0.email)" }
                    .joined(separator: ", ")
                return "OpenAI web session does not match Codex account. Found: \(display)."
            }
        }
    }

    public struct ImportResult: Sendable {
        public let sourceLabel: String
        public let cookieCount: Int
        public let signedInEmail: String?
        public let matchesCodexEmail: Bool
    }

    public init() {}

    public func importBestCookies(
        intoAccountEmail targetEmail: String?,
        logger: ((String) -> Void)? = nil) async throws -> ImportResult
    {
        let log: (String) -> Void = { message in
            logger?("[web] \(message)")
        }

        guard let targetEmail = targetEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !targetEmail.isEmpty
        else {
            throw ImportError.noCookiesFound
        }

        log("Codex email: \(targetEmail)")

        var mismatches: [FoundAccount] = []
        var foundAnyCookies = false
        var foundUnknownEmail = false

        enum CandidateEvaluation {
            case match(candidate: Candidate, signedInEmail: String)
            case mismatch(candidate: Candidate, signedInEmail: String)
            case unknown(candidate: Candidate)
            case loginRequired(candidate: Candidate)
        }

        func evaluateCandidate(_ candidate: Candidate) async -> CandidateEvaluation {
            log("Trying candidate \(candidate.label) (\(candidate.cookies.count) cookies)")

            let apiEmail = await self.fetchSignedInEmailFromAPI(cookies: candidate.cookies, logger: log)
            if let apiEmail {
                log("Candidate \(candidate.label) API email: \(apiEmail)")
            }

            // Prefer the API email when available (fast; avoids WebKit hydration/timeout risks).
            if let apiEmail, !apiEmail.isEmpty {
                if apiEmail.lowercased() == targetEmail.lowercased() {
                    return .match(candidate: candidate, signedInEmail: apiEmail)
                }
                return .mismatch(candidate: candidate, signedInEmail: apiEmail)
            }

            let scratch = WKWebsiteDataStore.nonPersistent()
            await self.setCookies(candidate.cookies, into: scratch)

            do {
                let probe = try await OpenAIDashboardFetcher().probeUsagePage(
                    websiteDataStore: scratch,
                    logger: log,
                    timeout: 25)
                let signedInEmail = probe.signedInEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
                log("Candidate \(candidate.label) DOM email: \(signedInEmail ?? "unknown")")

                let resolvedEmail = signedInEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let resolvedEmail, !resolvedEmail.isEmpty {
                    if resolvedEmail.lowercased() == targetEmail.lowercased() {
                        return .match(candidate: candidate, signedInEmail: resolvedEmail)
                    }
                    return .mismatch(candidate: candidate, signedInEmail: resolvedEmail)
                }

                return .unknown(candidate: candidate)
            } catch OpenAIDashboardFetcher.FetchError.loginRequired {
                log("Candidate \(candidate.label) requires login.")
                return .loginRequired(candidate: candidate)
            } catch {
                log("Candidate \(candidate.label) probe error: \(error.localizedDescription)")
                return .unknown(candidate: candidate)
            }
        }

        func handleMismatch(candidate: Candidate, signedInEmail: String) async {
            mismatches.append(FoundAccount(sourceLabel: candidate.label, email: signedInEmail))
            // Mismatch still means we found a valid signed-in session. Persist it keyed by its email so if
            // the user switches Codex accounts later, we can reuse this session immediately without another
            // Keychain prompt.
            await self.persistCookies(candidate: candidate, accountEmail: signedInEmail, logger: log)
        }

        // Safari first: avoids touching Keychain ("Chrome Safe Storage") when Safari already matches.
        do {
            let safari = try SafariCookieImporter.loadChatGPTCookies(logger: log)
            if !safari.isEmpty {
                let cookies = SafariCookieImporter.makeHTTPCookies(safari)
                if !cookies.isEmpty {
                    foundAnyCookies = true
                    log("Loaded \(cookies.count) cookies from Safari (\(self.cookieSummary(cookies)))")
                    let candidate = Candidate(label: "Safari", cookies: cookies)
                    switch await evaluateCandidate(candidate) {
                    case let .match(candidate, signedInEmail):
                        log("Selected \(candidate.label) (matches Codex: \(signedInEmail))")
                        return try await self.persist(candidate: candidate, targetEmail: targetEmail, logger: log)
                    case let .mismatch(candidate, signedInEmail):
                        await handleMismatch(candidate: candidate, signedInEmail: signedInEmail)
                    case .unknown:
                        foundUnknownEmail = true
                    case .loginRequired:
                        break
                    }
                } else {
                    log("Safari produced 0 HTTPCookies.")
                }
            } else {
                log("Safari contained 0 matching records.")
            }
        } catch {
            log("Safari cookie load failed: \(error.localizedDescription)")
        }

        // Chrome fallback: may trigger Keychain prompt. Only do this if Safari didn't match.
        do {
            let chromeSources = try ChromeCookieImporter.loadChatGPTCookiesFromAllProfiles()
            for source in chromeSources {
                let cookies = ChromeCookieImporter.makeHTTPCookies(source.records)
                if !cookies.isEmpty {
                    foundAnyCookies = true
                    log("Loaded \(cookies.count) cookies from \(source.label) (\(self.cookieSummary(cookies)))")
                    let candidate = Candidate(label: source.label, cookies: cookies)
                    switch await evaluateCandidate(candidate) {
                    case let .match(candidate, signedInEmail):
                        log("Selected \(candidate.label) (matches Codex: \(signedInEmail))")
                        return try await self.persist(candidate: candidate, targetEmail: targetEmail, logger: log)
                    case let .mismatch(candidate, signedInEmail):
                        await handleMismatch(candidate: candidate, signedInEmail: signedInEmail)
                    case .unknown:
                        foundUnknownEmail = true
                    case .loginRequired:
                        break
                    }
                } else {
                    log("Chrome source \(source.label) produced 0 HTTPCookies.")
                }
            }
        } catch {
            log("Chrome cookie load failed: \(error.localizedDescription)")
        }

        if !mismatches.isEmpty {
            let found = Array(Set(mismatches)).sorted { lhs, rhs in
                if lhs.sourceLabel == rhs.sourceLabel { return lhs.email < rhs.email }
                return lhs.sourceLabel < rhs.sourceLabel
            }
            let emails = Array(Set(found.map(\.email))).sorted()
            log("No matching browser session found. Candidates signed in as: \(emails.joined(separator: ", "))")
            throw ImportError.noMatchingAccount(found: found)
        }

        if foundUnknownEmail || foundAnyCookies {
            log("No matching browser session found (email unknown).")
            throw ImportError.noMatchingAccount(found: [])
        }

        throw ImportError.noCookiesFound
    }

    private func fetchSignedInEmailFromAPI(
        cookies: [HTTPCookie],
        logger: (String) -> Void) async -> String?
    {
        let chatgptCookies = cookies.filter { $0.domain.lowercased().contains("chatgpt.com") }
        guard !chatgptCookies.isEmpty else { return nil }

        let cookieHeader = chatgptCookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        let endpoints = [
            "https://chatgpt.com/backend-api/me",
            "https://chatgpt.com/api/auth/session",
        ]

        for urlString in endpoints {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger("API \(url.host ?? "chatgpt.com") \(url.path) status=\(status)")
                guard status >= 200, status < 300 else { continue }
                if let email = Self.findFirstEmail(inJSONData: data) {
                    return email.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                logger("API request failed: \(error.localizedDescription)")
            }
        }

        return nil
    }

    private static func findFirstEmail(inJSONData data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        var queue: [Any] = [json]
        var seen = 0
        while !queue.isEmpty, seen < 2000 {
            let cur = queue.removeFirst()
            seen += 1
            if let str = cur as? String, str.contains("@") {
                return str
            }
            if let dict = cur as? [String: Any] {
                for (k, v) in dict {
                    if k.lowercased() == "email", let s = v as? String, s.contains("@") { return s }
                    queue.append(v)
                }
            } else if let arr = cur as? [Any] {
                queue.append(contentsOf: arr)
            }
        }
        return nil
    }

    private func persist(
        candidate: Candidate,
        targetEmail: String,
        logger: @escaping (String) -> Void) async throws -> ImportResult
    {
        let persistent = OpenAIDashboardWebsiteDataStore.store(forAccountEmail: targetEmail)
        await self.clearChatGPTCookies(in: persistent)
        await self.setCookies(candidate.cookies, into: persistent)

        // Validate against the persistent store (login + email sync).
        do {
            let probe = try await OpenAIDashboardFetcher().probeUsagePage(
                websiteDataStore: persistent,
                logger: logger,
                timeout: 20)
            let signed = probe.signedInEmail?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let matches = signed?.lowercased() == targetEmail.lowercased()
            logger("Persistent session signed in as: \(signed ?? "unknown")")
            if signed != nil, matches == false {
                let found = signed?.isEmpty == false
                    ? [FoundAccount(sourceLabel: candidate.label, email: signed!)]
                    : []
                throw ImportError.noMatchingAccount(found: found)
            }
            return ImportResult(
                sourceLabel: candidate.label,
                cookieCount: candidate.cookies.count,
                signedInEmail: signed,
                matchesCodexEmail: matches)
        } catch OpenAIDashboardFetcher.FetchError.loginRequired {
            logger("Selected \(candidate.label) but dashboard still requires login.")
            throw ImportError.dashboardStillRequiresLogin
        }
    }

    // MARK: - Candidates

    private struct Candidate: Sendable {
        let label: String
        let cookies: [HTTPCookie]
    }

    // MARK: - WebKit cookie store

    private func persistCookies(candidate: Candidate, accountEmail: String, logger: (String) -> Void) async {
        let store = OpenAIDashboardWebsiteDataStore.store(forAccountEmail: accountEmail)
        await self.clearChatGPTCookies(in: store)
        await self.setCookies(candidate.cookies, into: store)
        logger("Persisted cookies for \(accountEmail) (source=\(candidate.label))")
    }

    private func clearChatGPTCookies(in store: WKWebsiteDataStore) async {
        await withCheckedContinuation { cont in
            store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                let filtered = records.filter { record in
                    let name = record.displayName.lowercased()
                    return name.contains("chatgpt.com") || name.contains("openai.com")
                }
                store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: filtered) {
                    cont.resume()
                }
            }
        }
    }

    private func setCookies(_ cookies: [HTTPCookie], into store: WKWebsiteDataStore) async {
        for cookie in cookies {
            await withCheckedContinuation { cont in
                store.httpCookieStore.setCookie(cookie) { cont.resume() }
            }
        }
    }

    private func cookieSummary(_ cookies: [HTTPCookie]) -> String {
        let nameCounts = Dictionary(grouping: cookies, by: \.name).mapValues { $0.count }
        let important = [
            "__Secure-next-auth.session-token",
            "__Secure-next-auth.session-token.0",
            "__Secure-next-auth.session-token.1",
            "_account",
            "oai-did",
            "cf_clearance",
        ]
        let parts: [String] = important.compactMap { name -> String? in
            guard let c = nameCounts[name], c > 0 else { return nil }
            return "\(name)=\(c)"
        }
        if parts.isEmpty { return "no key cookies detected" }
        return parts.joined(separator: ", ")
    }
}
