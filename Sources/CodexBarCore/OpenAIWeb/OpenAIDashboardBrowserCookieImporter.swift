import Foundation
import WebKit

@MainActor
public struct OpenAIDashboardBrowserCookieImporter {
    public enum ImportError: LocalizedError {
        case noCookiesFound
        case dashboardStillRequiresLogin
        case noMatchingAccount(found: [String])

        public var errorDescription: String? {
            switch self {
            case .noCookiesFound:
                return "No browser cookies found."
            case .dashboardStillRequiresLogin:
                return "Browser cookies imported, but dashboard still requires login."
            case let .noMatchingAccount(found):
                if found.isEmpty { return "No matching OpenAI web session found in browsers." }
                return "OpenAI web session does not match Codex account. Found: \(found.joined(separator: ", "))."
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

        let candidates = try await self.loadCandidates(logger: log)
        if candidates.isEmpty { throw ImportError.noCookiesFound }

        var matches: [(candidate: Candidate, signedInEmail: String)] = []
        var mismatches: [(candidate: Candidate, signedInEmail: String)] = []
        var unknown: [Candidate] = []

        for candidate in candidates {
            log("Trying candidate \(candidate.label) (\(candidate.cookies.count) cookies)")
            let scratch = WKWebsiteDataStore.nonPersistent()
            await self.setCookies(candidate.cookies, into: scratch)

            do {
                let apiEmail = await self.fetchSignedInEmailFromAPI(cookies: candidate.cookies, logger: log)
                if let apiEmail {
                    log("Candidate \(candidate.label) API email: \(apiEmail)")
                }

                let probe = try await OpenAIDashboardFetcher().probeUsagePage(
                    websiteDataStore: scratch,
                    logger: log,
                    timeout: 15)
                let signedInEmail = probe.signedInEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
                log("Candidate \(candidate.label) DOM email: \(signedInEmail ?? "unknown")")

                let resolvedEmail = (apiEmail ?? signedInEmail)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let resolvedEmail, !resolvedEmail.isEmpty {
                    if resolvedEmail.lowercased() == targetEmail.lowercased() {
                        matches.append((candidate, resolvedEmail))
                    } else {
                        mismatches.append((candidate, resolvedEmail))
                    }
                } else {
                    unknown.append(candidate)
                }

            } catch OpenAIDashboardFetcher.FetchError.loginRequired {
                log("Candidate \(candidate.label) requires login.")
            } catch {
                log("Candidate \(candidate.label) probe error: \(error.localizedDescription)")
            }
        }

        if let selected = matches.first {
            log("Selected \(selected.candidate.label) (matches Codex: \(selected.signedInEmail))")
            return try await self.persist(
                candidate: selected.candidate,
                targetEmail: targetEmail,
                logger: log)
        }

        if !mismatches.isEmpty {
            let found = Array(Set(mismatches.map(\.signedInEmail))).sorted()
            log("No matching browser session found. Candidates signed in as: \(found.joined(separator: ", "))")
            throw ImportError.noMatchingAccount(found: found)
        }

        if !unknown.isEmpty {
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
                let found = signed?.isEmpty == false ? [signed!] : []
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

    private func loadCandidates(logger: (String) -> Void) async throws -> [Candidate] {
        var out: [Candidate] = []

        // Prefer Chrome first: most users are logged in there; also triggers Keychain prompt early if needed.
        do {
            let chromeSources = try ChromeCookieImporter.loadChatGPTCookiesFromAllProfiles()
            for source in chromeSources {
                let cookies = ChromeCookieImporter.makeHTTPCookies(source.records)
                if !cookies.isEmpty {
                    logger("Loaded \(cookies.count) cookies from \(source.label) (\(self.cookieSummary(cookies)))")
                    out.append(Candidate(label: source.label, cookies: cookies))
                } else {
                    logger("Chrome source \(source.label) produced 0 HTTPCookies.")
                }
            }
        } catch {
            logger("Chrome cookie load failed: \(error.localizedDescription)")
        }

        do {
            let safari = try SafariCookieImporter.loadChatGPTCookies()
            if !safari.isEmpty {
                let cookies = SafariCookieImporter.makeHTTPCookies(safari)
                if !cookies.isEmpty {
                    logger("Loaded \(cookies.count) cookies from Safari (\(self.cookieSummary(cookies)))")
                    out.append(Candidate(label: "Safari", cookies: cookies))
                } else {
                    logger("Safari produced 0 HTTPCookies.")
                }
            } else {
                logger("Safari contained 0 matching records.")
            }
        } catch {
            logger("Safari cookie load failed: \(error.localizedDescription)")
        }

        logger("Candidates: \(out.map(\.label).joined(separator: ", "))")
        return out
    }

    // MARK: - WebKit cookie store

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
