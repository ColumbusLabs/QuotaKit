import CodexBarCore
import Commander
import Foundation

struct UsageCommandContext {
    let format: OutputFormat
    let includeCredits: Bool
    let sourceMode: ProviderSourceMode
    let antigravityPlanDebug: Bool
    let augmentDebug: Bool
    let webDebugDumpHTML: Bool
    let webTimeout: TimeInterval
    let verbose: Bool
    let useColor: Bool
    let resetStyle: ResetTimeDisplayStyle
    let fetcher: UsageFetcher
    let claudeFetcher: ClaudeUsageFetcher
    let browserDetection: BrowserDetection
}

struct UsageCommandOutput {
    var sections: [String] = []
    var payload: [ProviderPayload] = []
    var exitCode: ExitCode = .success
}

extension CodexBarCLI {
    static func fetchUsageOutputs(
        provider: UsageProvider,
        status: ProviderStatusPayload?,
        tokenContext: TokenAccountCLIContext,
        command: UsageCommandContext) async -> UsageCommandOutput
    {
        var output = UsageCommandOutput()
        let accounts: [ProviderTokenAccount]
        do {
            accounts = try tokenContext.resolvedAccounts(for: provider)
        } catch {
            Self.exit(code: .failure, message: "Error: \(error.localizedDescription)")
        }

        let accountSelections: [ProviderTokenAccount?] = accounts.isEmpty
            ? [nil]
            : accounts.map { Optional($0) }

        for account in accountSelections {
            var antigravityPlanInfo: AntigravityPlanInfoSummary?
            let env = tokenContext.environment(
                base: ProcessInfo.processInfo.environment,
                provider: provider,
                account: account)
            let settings = tokenContext.settingsSnapshot(for: provider, account: account)
            let effectiveSourceMode = tokenContext.effectiveSourceMode(
                base: command.sourceMode,
                provider: provider,
                account: account)
            let fetchContext = ProviderFetchContext(
                runtime: .cli,
                sourceMode: effectiveSourceMode,
                includeCredits: command.includeCredits,
                webTimeout: command.webTimeout,
                webDebugDumpHTML: command.webDebugDumpHTML,
                verbose: command.verbose,
                env: env,
                settings: settings,
                fetcher: command.fetcher,
                claudeFetcher: command.claudeFetcher,
                browserDetection: command.browserDetection)
            let outcome = await Self.fetchProviderUsage(
                provider: provider,
                context: fetchContext)
            if command.verbose {
                Self.printFetchAttempts(provider: provider, attempts: outcome.attempts)
            }

            switch outcome.result {
            case let .success(result):
                var dashboard = result.dashboard
                if command.antigravityPlanDebug, provider == .antigravity {
                    antigravityPlanInfo = try? await AntigravityStatusProbe().fetchPlanInfoSummary()
                    if command.format == .text, let info = antigravityPlanInfo {
                        Self.printAntigravityPlanInfo(info)
                    }
                }

                if command.augmentDebug, provider == .augment {
                    #if os(macOS)
                    let dump = await AugmentStatusProbe.latestDumps()
                    if command.format == .text, !dump.isEmpty {
                        Self.writeStderr("Augment API responses:\n\(dump)\n")
                    }
                    #endif
                }

                var usage = result.usage.scoped(to: provider)
                if let account {
                    usage = tokenContext.applyAccountLabel(usage, provider: provider, account: account)
                }

                if dashboard == nil, command.format == .json, provider == .codex {
                    dashboard = Self.loadOpenAIDashboardIfAvailable(usage: usage, fetcher: command.fetcher)
                }

                let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
                let shouldDetectVersion = descriptor.cli.versionDetector != nil
                    && result.strategyKind != ProviderFetchKind.webDashboard
                let version = Self.normalizeVersion(
                    raw: shouldDetectVersion
                        ? Self.detectVersion(for: provider, browserDetection: command.browserDetection)
                        : nil)
                let source = result.sourceLabel
                let header = Self.makeHeader(provider: provider, version: version, source: source)

                switch command.format {
                case .text:
                    var text = CLIRenderer.renderText(
                        provider: provider,
                        snapshot: usage,
                        credits: result.credits,
                        context: RenderContext(
                            header: header,
                            status: status,
                            useColor: command.useColor,
                            resetStyle: command.resetStyle))
                    if let dashboard, provider == .codex, command.sourceMode.usesWeb {
                        text += "\n" + Self.renderOpenAIWebDashboardText(dashboard)
                    }
                    output.sections.append(text)
                case .json:
                    output.payload.append(ProviderPayload(
                        provider: provider,
                        account: account?.label,
                        version: version,
                        source: source,
                        status: status,
                        usage: usage,
                        credits: result.credits,
                        antigravityPlanInfo: antigravityPlanInfo,
                        openaiDashboard: dashboard))
                }
            case let .failure(error):
                output.exitCode = Self.mapError(error)
                if let account {
                    Self.writeStderr("Error (\(provider.rawValue) - \(account.label)): \(error.localizedDescription)\n")
                } else {
                    Self.printError(error)
                }
            }
        }

        return output
    }
}
