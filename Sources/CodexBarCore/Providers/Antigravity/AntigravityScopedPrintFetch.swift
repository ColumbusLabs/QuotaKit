import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct AntigravityAgyFileTokenPayload: Codable, Equatable, Sendable {
    struct Token: Codable, Equatable, Sendable {
        let accessToken: String
        let tokenType: String
        let refreshToken: String
        let expiry: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case refreshToken = "refresh_token"
            case expiry
        }
    }

    let token: Token
    let authMethod: String
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case token
        case authMethod = "auth_method"
        case idToken = "id_token"
    }
}

extension AntigravityAgyFileTokenPayload {
    init?(credentials: AntigravityOAuthCredentials) {
        guard let accessToken = credentials.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty,
              let refreshToken = credentials.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !refreshToken.isEmpty,
              let expiryDate = credentials.expiryDate
        else {
            return nil
        }

        self.init(
            token: .init(
                accessToken: accessToken,
                tokenType: "Bearer",
                refreshToken: refreshToken,
                expiry: expiryDate.ISO8601Format()),
            authMethod: "consumer",
            idToken: credentials.idToken)
    }
}

enum AntigravityScopedStagingError: LocalizedError, Sendable, Equatable {
    case credentialsMissingRequiredFields
    case identityUnverifiable

    var errorDescription: String? {
        switch self {
        case .credentialsMissingRequiredFields:
            "Antigravity account credentials lack required token or expiry fields."
        case .identityUnverifiable:
            "Antigravity scoped credentials could not be verified against the selected account."
        }
    }
}

enum AntigravityScopedAgyStaging {
    static let tokenRelativePath = ".gemini/antigravity-cli/antigravity-oauth-token"

    static func childEnvironment(from environment: [String: String], home: URL) -> [String: String] {
        var child: [String: String] = [:]
        for key in [
            "PATH", "TMPDIR", "LANG", "LC_ALL", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy",
        ] {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                child[key] = value
            }
        }
        child["PATH"] = PathBuilder.effectivePATH(
            purposes: [.tty], env: child, loginPATH: LoginShellPathCache.shared.current)
        child["HOME"] = home.path
        child["PWD"] = home.path
        // agy prefers the OS keyring unless SSH_TTY is present. The private staged HOME
        // plus this marker makes its file token store the only credential source.
        child["SSH_TTY"] = "codexbar-scoped"
        return child
    }

    static func stage(
        credentials: AntigravityOAuthCredentials,
        expectedAccountEmail: String,
        fileManager: FileManager = .default) throws -> (stagingRoot: URL, home: URL)
    {
        guard let payload = AntigravityAgyFileTokenPayload(credentials: credentials) else {
            throw AntigravityScopedStagingError.credentialsMissingRequiredFields
        }
        try Self.validateClaim(credentials.idToken, expectedAccountEmail: expectedAccountEmail)
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("codexbar-agy-scoped-" + UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let tokenURL = root.appendingPathComponent(Self.tokenRelativePath)
            try fileManager.createDirectory(
                at: tokenURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try CredentialFileWriter.writePrivate(JSONEncoder().encode(payload), to: tokenURL)
            return (root, root)
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    static func validateClaim(_ idToken: String?, expectedAccountEmail: String) throws {
        if let email = self.normalizedEmail(AntigravityOAuthCredentials.email(fromIDToken: idToken)),
           email != self.normalizedEmail(expectedAccountEmail)
        {
            throw AntigravityScopedStagingError.identityUnverifiable
        }
    }

    static func normalizedEmail(_ email: String?) -> String? {
        guard let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }

    static func stagedTokenPayload(home: URL, fileManager: FileManager = .default) -> AntigravityAgyFileTokenPayload? {
        let tokenURL = home.appendingPathComponent(Self.tokenRelativePath)
        guard let data = fileManager.contents(atPath: tokenURL.path) else { return nil }
        return try? JSONDecoder().decode(AntigravityAgyFileTokenPayload.self, from: data)
    }

    static func refreshedCredentials(
        payload: AntigravityAgyFileTokenPayload,
        original: AntigravityOAuthCredentials) -> AntigravityOAuthCredentials?
    {
        guard let originalPayload = AntigravityAgyFileTokenPayload(credentials: original),
              payload != originalPayload
        else {
            return nil
        }
        var updated = original
        let accessToken = payload.token.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshToken = payload.token.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !accessToken.isEmpty { updated.accessToken = accessToken }
        if !refreshToken.isEmpty { updated.refreshToken = refreshToken }
        if let expiry = ISO8601DateParser.parse(payload.token.expiry) {
            updated.expiryDateMilliseconds = expiry.timeIntervalSince1970 * 1000
        }
        if let idToken = payload.idToken?.trimmingCharacters(in: .whitespacesAndNewlines), !idToken.isEmpty {
            updated.idToken = idToken
        }
        return updated
    }

    static func runEffectiveAccountEmail(
        payload: AntigravityAgyFileTokenPayload,
        timeout: TimeInterval,
        dataLoader: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?) async throws -> String?
    {
        let accessToken = payload.token.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else { return nil }
        var request = URLRequest(url: AntigravityOAuthConfig.userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = min(timeout, 15)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let session = ProviderHTTPClient.redirectGuardedSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            try Task.checkCancellation()
            let (data, response) = try await (dataLoader ?? { try await session.data(for: $0) })(request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return self.normalizedEmail(json["email"] as? String)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            return nil
        }
    }
}

#if os(macOS)
extension AntigravityCLIHTTPSFetchStrategy {
    private static let scopedPrintLog = CodexBarLog.logger(LogCategories.provider(.antigravity))

    func fetchScopedPrintUsage(
        binary: String,
        environment: [String: String],
        timeout: TimeInterval = 90,
        dataLoader: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil,
        credentialsUpdateHandler: (@Sendable (AntigravityOAuthCredentials) async throws -> Void)? = nil)
        async throws -> ProviderFetchResult
    {
        try Task.checkCancellation()
        guard let value = environment[AntigravityOAuthCredentialsStore.environmentCredentialsKey],
              let credentials = AntigravityOAuthCredentialsStore.credentials(fromTokenAccountValue: value),
              let expectedAccountEmail = credentials.resolvedAccountEmail
        else {
            throw AntigravityScopedStagingError.credentialsMissingRequiredFields
        }

        let staged = try AntigravityScopedAgyStaging.stage(
            credentials: credentials, expectedAccountEmail: expectedAccountEmail)
        defer { try? FileManager.default.removeItem(at: staged.stagingRoot) }
        let scopedEnvironment = AntigravityScopedAgyStaging.childEnvironment(
            from: environment, home: staged.home)

        let parsed = try await Self.runPrintUsage(
            binary: binary, environment: scopedEnvironment, directory: staged.home, timeout: timeout)
        if let reportedEmail = AntigravityScopedAgyStaging.normalizedEmail(parsed.accountEmail),
           reportedEmail != AntigravityScopedAgyStaging.normalizedEmail(expectedAccountEmail)
        {
            Self.scopedPrintLog.info("Scoped agy usage report rejected: report identity does not match selected account")
            throw AntigravityStatusProbeError.accountMismatch(expected: expectedAccountEmail, found: parsed.accountEmail)
        }
        guard let payload = AntigravityScopedAgyStaging.stagedTokenPayload(home: staged.home) else {
            throw AntigravityScopedStagingError.identityUnverifiable
        }
        try AntigravityScopedAgyStaging.validateClaim(payload.idToken, expectedAccountEmail: expectedAccountEmail)
        let effectiveEmail = try await AntigravityScopedAgyStaging.runEffectiveAccountEmail(
            payload: payload, timeout: timeout, dataLoader: dataLoader)
        guard let effectiveEmail else {
            Self.scopedPrintLog.info("Scoped agy usage report rejected: effective account could not be verified")
            throw AntigravityScopedStagingError.identityUnverifiable
        }
        guard effectiveEmail == AntigravityScopedAgyStaging.normalizedEmail(expectedAccountEmail) else {
            Self.scopedPrintLog.info("Scoped agy usage report rejected: effective account does not match selected account")
            throw AntigravityStatusProbeError.accountMismatch(expected: expectedAccountEmail, found: effectiveEmail)
        }

        if let credentialsUpdateHandler,
           let refreshed = AntigravityScopedAgyStaging.refreshedCredentials(payload: payload, original: credentials)
        {
            do {
                try await credentialsUpdateHandler(refreshed)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                Self.scopedPrintLog.warning("Scoped agy usage: could not persist refreshed credentials")
            }
        }
        try Task.checkCancellation()
        let snapshot = parsed.withIdentity(from: AntigravityStatusSnapshot(
            modelQuotas: [], accountEmail: expectedAccountEmail, accountPlan: nil, source: parsed.source))
        return try self.makeResult(usage: snapshot.toUsageSnapshot(), sourceLabel: Self.sourceLabel)
    }
}
#endif
