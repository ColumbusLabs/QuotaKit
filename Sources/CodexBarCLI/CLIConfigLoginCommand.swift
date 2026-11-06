import CodexBarCore
import Commander
import Foundation

extension CodexBarCLI {
    static func runConfigLogin(_ values: ParsedValues) async {
        let output = CLIOutputPreferences.from(values: values)
        let cookieHeader: String?
        do {
            _ = try Self.configLoginProvider(
                values.options["provider"]?.last, readFromStdin: values.flags.contains("stdin"))
            cookieHeader = values.flags.contains("stdin")
                ? try Self.claudePlatformLoginCookie(String(
                    data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)) : nil
        } catch {
            Self.exit(code: .failure, message: error.localizedDescription, output: output, kind: .args)
        }

        let task = Task {
            let emit: (ConfigLoginEvent) -> Void = { event in
                let line = if output.format == .json {
                    Self.encodeJSON(event, pretty: false) ?? ""
                } else if let url = event.verificationURI, let code = event.userCode {
                    "\(url)\n\(code)"
                } else {
                    cookieHeader == nil ? "Connected"
                        : UsageFormatter.localized("Claude Platform session validated and saved.")
                }
                FileHandle.standardOutput.write(Data("\(line)\n".utf8))
            }
            if let cookieHeader {
                try await Self.loginClaudePlatform(cookieHeader: cookieHeader, store: CodexBarConfigStore(), emit: emit)
            } else {
                try await Self.loginCopilot(store: CodexBarConfigStore(), emit: emit)
            }
        }
        let monitor = CLITerminationSignalMonitor { _ in task.cancel() }
        defer { monitor.cancel() }

        do {
            try await task.value
        } catch {
            let message = error is CancellationError
                ? URLError(.userCancelledAuthentication).localizedDescription
                : error.localizedDescription
            if output.format == .json {
                Self.printJSON(ConfigLoginEvent(status: "failed", error: message), pretty: false)
                Self.exit(code: .failure)
            }
            Self.exit(code: .failure, message: message, output: output)
        }
    }

    static func configLoginProvider(_ raw: String?, readFromStdin: Bool) throws -> UsageProvider {
        // Provider-specific by design: only Copilot device login and explicit Console-session import are supported.
        guard let raw, let provider = ProviderDescriptorRegistry.cliNameMap[raw.lowercased()],
              provider == .copilot || provider == .claudeplatform
        else { throw CLIArgumentError(self.configLoginProviderInstructions) }
        // Provider-specific by design: Console imports accept secrets only over stdin; Copilot keeps its device flow.
        if provider == .claudeplatform, !readFromStdin {
            throw CLIArgumentError(Self.claudePlatformLoginInstructions)
        }
        // Provider-specific by design: the existing Copilot flow has no stdin credential contract.
        if provider == .copilot, readFromStdin {
            throw CLIArgumentError(Self.configLoginProviderInstructions)
        }
        return provider
    }

    private static var configLoginProviderInstructions: String {
        String(
            format: UsageFormatter.localized("Use %@ or %@."),
            "--provider copilot",
            "--provider claudeplatform --stdin")
    }

    private static var claudePlatformLoginInstructions: String {
        String(
            format: UsageFormatter.localized(
                "Sign in at %@. Supply its Cookie header containing sessionKey privately to %@. Then run %@."),
            "https://platform.claude.com",
            "quotakit config login --provider claudeplatform --stdin",
            "quotakit usage --provider claudeplatform --source web --json")
    }

    static func claudePlatformLoginCookie(_ raw: String?) throws -> String {
        guard SettingsValue.cleaned(raw) != nil else {
            throw CLIArgumentError(self.claudePlatformLoginInstructions)
        }
        let input = try Self.resolveConfigCookieInput(cookie: raw, readFromStdin: false)
        guard let header = CookieHeaderNormalizer.normalize(input), CookieHeaderNormalizer.pairs(from: header)
            .contains(where: { $0.name == "sessionKey" && !$0.value.isEmpty })
        else {
            throw CLIArgumentError(UsageFormatter.localized(
                "Paste a platform.claude.com Cookie header containing sessionKey."))
        }
        return header
    }

    static func loginClaudePlatform(
        cookieHeader: String,
        store: CodexBarConfigStore,
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared,
        emit: (ConfigLoginEvent) -> Void) async throws
    {
        let header = try Self.claudePlatformLoginCookie(cookieHeader)
        let original = try store.load()
        let originalBytes = try original?.encodedData()
        // Provider-specific by design: run the bundled Console plugin with one in-memory candidate and no fallback.
        let runtime = try ProviderPluginRuntime(
            bundledPlugin: "claudeplatform", transport: transport, timeout: ClaudePlatformProviderDescriptor.webTimeout)
        _ = try await runtime.fetchUsage(
            sourceMode: .web,
            cookieSource: .manual,
            cookieSessionResolver: ProviderPluginCookieSession.manualResolver(
                header: header, domain: "platform.claude.com"))
        // Provider-specific by design: validation authorizes only the Console manual-cookie configuration.
        let config = Self.configSettingCookie(
            original ?? .makeDefault(), provider: .claudeplatform, cookieHeader: header, enableProvider: true)
        let data = try store.encodedData(for: config)
        try store.saveEncodedData(data) {
            try Task.checkCancellation()
            guard try store.load()?.encodedData() == originalBytes else {
                throw CLIArgumentError(UsageFormatter.localized("Config changed during login. Please try again."))
            }
        }
        emit(ConfigLoginEvent(status: "authorized"))
    }

    static func loginCopilot(
        store: CodexBarConfigStore,
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared,
        emit: (ConfigLoginEvent) -> Void) async throws
    {
        let original = try store.load()
        let originalBytes = try original?.encodedData()
        var config = original ?? .makeDefault()
        var provider = config.providerConfig(for: .copilot) ?? ProviderConfig(id: .copilot)
        let enterpriseHost = provider.sanitizedEnterpriseHost
        let flow = CopilotDeviceFlow(enterpriseHost: enterpriseHost, transport: transport)
        let code = try await flow.requestDeviceCode()
        emit(ConfigLoginEvent(
            status: "authorization_pending",
            verificationURI: code.verificationUri,
            userCode: code.userCode,
            expiresIn: code.expiresIn))

        let token = try await flow.pollForToken(
            deviceCode: code.deviceCode,
            interval: code.interval,
            expiresIn: code.expiresIn)
        let identity = try await CopilotUsageFetcher.fetchGitHubIdentity(
            token: token,
            enterpriseHost: enterpriseHost,
            transport: transport)
        let issuer = CopilotUsageFetcher.apiHost(enterpriseHost: enterpriseHost)
        let accounts = provider.tokenAccounts?.accounts ?? []
        let match = await CopilotAccountIdentity.resolveExistingAccount(
            existingAccounts: accounts,
            identity: identity,
            label: identity.login,
            issuer: issuer,
            enterpriseHost: enterpriseHost,
            legacyIdentityResolver: { account, configuredHost in
                try? await CopilotUsageFetcher.fetchGitHubIdentity(
                    token: account.token,
                    enterpriseHost: configuredHost,
                    transport: transport)
            })
        guard case let .resolved(existing) = match else {
            throw CLIArgumentError("Could not safely match this GitHub login to a saved Copilot account.")
        }

        let account = ProviderTokenAccount(
            id: existing?.id ?? UUID(),
            label: existing?.label ?? identity.login,
            token: token,
            addedAt: existing?.addedAt ?? Date().timeIntervalSince1970,
            lastUsed: existing?.lastUsed,
            externalIdentifier: CopilotAccountIdentity.externalIdentifier(for: identity, issuer: issuer),
            usageScope: existing?.usageScope,
            organizationID: existing?.organizationID,
            workspaceID: existing?.workspaceID,
            claudeConfigDirectory: existing?.claudeConfigDirectory,
            seatCreditEntitlement: existing?.seatCreditEntitlement,
            modelRateLimits: existing?.modelRateLimits)
        let accountIndex = accounts.firstIndex(where: { $0.id == account.id }) ?? accounts.count
        var updatedAccounts = accounts
        if accountIndex == updatedAccounts.count {
            updatedAccounts.append(account)
        } else {
            updatedAccounts[accountIndex] = account
        }
        provider.tokenAccounts = ProviderTokenAccountData(
            version: provider.tokenAccounts?.version ?? 1,
            accounts: updatedAccounts,
            activeIndex: accountIndex)
        provider.apiKey = nil
        provider.enabled = true
        config.setProviderConfig(provider)

        let data = try store.encodedData(for: config)
        try store.saveEncodedData(data) {
            try Task.checkCancellation()
            guard try store.load()?.encodedData() == originalBytes else {
                throw CLIArgumentError(UsageFormatter.localized("Config changed during login. Please try again."))
            }
        }
        emit(ConfigLoginEvent(status: "authorized"))
    }
}

struct ConfigLoginEvent: Encodable {
    let status: String
    var verificationURI: String?
    var userCode: String?
    var expiresIn: Int?
    var error: String?
}

struct ConfigLoginOptions: CommanderParsable {
    @Flag(names: [.short("v"), .long("verbose")], help: "Enable verbose logging")
    var verbose: Bool = false

    @Flag(name: .long("json-output"), help: "Emit machine-readable logs")
    var jsonOutput: Bool = false

    @Option(name: .long("log-level"), help: "Set log level (trace|verbose|debug|info|warning|error|critical)")
    var logLevel: String?

    @Option(name: .long("format"), help: "Output format: text | json")
    var format: OutputFormat?

    @Flag(name: .long("json"), help: "")
    var jsonShortcut: Bool = false

    @Flag(name: .long("json-only"), help: "Emit JSON only (suppress non-JSON output)")
    var jsonOnly: Bool = false

    @Flag(name: .long("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Option(name: .long("provider"), help: ProviderHelp.concreteOptionHelp)
    var provider: String?

    @Flag(name: .long("stdin"), help: UsageFormatter.localized("Read cookie header from stdin"))
    var stdin: Bool = false
}
