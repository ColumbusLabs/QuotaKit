import CodexBarCore
import Commander
import Darwin
import Foundation

@main
enum CodexBarCLI {
    static func main() async {
        let rawArgv = Array(CommandLine.arguments.dropFirst())
        let argv = Self.effectiveArgv(rawArgv)
        let outputPreferences = CLIOutputPreferences.from(argv: argv)
        let errorOutputPreferences: CLIOutputPreferences? = argv.first == "dashboard" ? nil : outputPreferences

        // Fast path: global help/version before building descriptors.
        if let helpIndex = argv.firstIndex(where: { $0 == "-h" || $0 == "--help" }) {
            let command = helpIndex == 0 ? argv.dropFirst().first : argv.first
            Self.printHelp(for: command)
        }
        if argv.contains("-V") || argv.contains("--version") {
            Self.printVersion()
        }

        let program = Program(descriptors: Self.commandDescriptors())

        do {
            let invocation = try program.resolve(argv: argv)
            Self.bootstrapLogging(path: invocation.path, values: invocation.parsedValues)
            switch invocation.path {
            case ["cards"], ["usage"]:
                await self.runUsageDisplay(path: invocation.path, values: invocation.parsedValues)
            case ["cost"]:
                await self.runCost(invocation.parsedValues)
            case ["sessions", "list"]:
                await self.runSessions(invocation.parsedValues)
            case ["sessions", "focus"]:
                await self.runSessionsFocus(invocation.parsedValues)
            case ["dashboard"]:
                await self.runDashboard(invocation.parsedValues)
            case ["serve"]:
                await self.runServe(invocation.parsedValues)
            case let path where path.first == "config":
                self.runConfig(path: path, values: invocation.parsedValues)
            case let path where path.first == "hooks":
                await self.runHooks(path: path, values: invocation.parsedValues)
            case ["cache", "clear"]:
                self.runCacheClear(invocation.parsedValues)
            case ["cookie", "refresh"]:
                await self.runCookieRefreshWithTermination(invocation.parsedValues)
            case ["diagnose"]:
                let signalMonitor = CLITerminationSignalMonitor { signalNumber in
                    CLITerminationSignalMonitor.terminateActiveHelpersAndReraise(signalNumber)
                }
                defer { signalMonitor.cancel() }
                await self.runDiagnose(invocation.parsedValues)
            case ["guard"]:
                await self.runGuard(invocation.parsedValues)
            default:
                Self.exit(
                    code: .failure,
                    message: "Unknown command",
                    output: outputPreferences,
                    kind: .args)
            }
        } catch let error as CommanderProgramError {
            let exitCode: ExitCode = argv.first == "guard" ? .usage : .failure
            Self.exit(code: exitCode, message: error.description, output: errorOutputPreferences, kind: .args)
        } catch {
            Self.exit(
                code: .failure,
                message: error.localizedDescription,
                output: errorOutputPreferences,
                kind: .runtime)
        }
    }

    private static func runUsageDisplay(path: [String], values: ParsedValues) async {
        let signalMonitor = CLITerminationSignalMonitor { signalNumber in
            CLITerminationSignalMonitor.terminateActiveHelpersAndReraise(signalNumber)
        }
        defer { signalMonitor.cancel() }
        switch path {
        case ["cards"]:
            await self.runCards(values)
        default:
            await self.runUsage(values)
        }
    }

    private static func runCookieRefreshWithTermination(_ values: ParsedValues) async {
        let signalMonitor = CLITerminationSignalMonitor { signalNumber in
            CLITerminationSignalMonitor.terminateActiveHelpersAndReraise(signalNumber)
        }
        defer { signalMonitor.cancel() }
        await self.runCookieRefresh(values)
    }

    private static func hooksCommandDescriptor() -> CommandDescriptor {
        let hooksSignature = CommandSignature.describe(HooksOptions())
        let hooksTestSignature = CommandSignature.describe(HooksTestOptions())
        let hooksWatchSignature = CommandSignature.describe(HooksWatchOptions())

        return CommandDescriptor(
            name: "hooks",
            abstract: "Run external commands on quota/provider events",
            discussion: nil,
            signature: CommandSignature(),
            subcommands: [
                CommandDescriptor(
                    name: "list",
                    abstract: "List configured hooks",
                    discussion: nil,
                    signature: hooksSignature),
                CommandDescriptor(
                    name: "enable",
                    abstract: "Enable hooks",
                    discussion: nil,
                    signature: hooksSignature),
                CommandDescriptor(
                    name: "disable",
                    abstract: "Disable hooks",
                    discussion: nil,
                    signature: hooksSignature),
                CommandDescriptor(
                    name: "test",
                    abstract: "Fire matching hooks for an event",
                    discussion: nil,
                    signature: hooksTestSignature),
                CommandDescriptor(
                    name: "watch",
                    abstract: "Poll providers and fire hooks on quota/status changes",
                    discussion: nil,
                    signature: hooksWatchSignature),
            ],
            defaultSubcommandName: "list")
    }

    static func commandDescriptors() -> [CommandDescriptor] {
        let cardsSignature = CommandSignature.describe(CardsOptions())
        let usageSignature = CommandSignature.describe(UsageOptions())
        let costSignature = CommandSignature.describe(CostOptions())
        let sessionsSignature = CommandSignature.describe(SessionsOptions())
        let sessionsFocusSignature = CommandSignature.describe(SessionsFocusOptions())
        let serveSignature = CommandSignature.describe(ServeOptions())
        let configSignature = CommandSignature.describe(ConfigOptions())
        let configDumpSignature = CommandSignature.describe(ConfigDumpOptions())
        let configProviderToggleSignature = CommandSignature.describe(ConfigProviderToggleOptions())
        let configSetAPIKeySignature = CommandSignature.describe(ConfigSetAPIKeyOptions())
        let cacheSignature = CommandSignature.describe(CacheOptions())
        let diagnoseSignature = CommandSignature.describe(DiagnoseOptions())
        let guardSignature = CommandSignature.describe(GuardOptions())

        return [
            CommandDescriptor(
                name: "cards",
                abstract: "Print usage as a terminal card grid",
                discussion: nil,
                signature: cardsSignature),
            CommandDescriptor(
                name: "usage",
                abstract: "Print usage as text or JSON",
                discussion: nil,
                signature: usageSignature),
            CommandDescriptor(
                name: "guard",
                abstract: "Exit non-zero when a provider lacks quota headroom (for gating scripts)",
                discussion: nil,
                signature: guardSignature),
            CommandDescriptor(
                name: "cost",
                abstract: "Print local cost usage as text or JSON",
                discussion: nil,
                signature: costSignature),
            CommandDescriptor(
                name: "sessions",
                abstract: "List live Codex, Claude Code, pi, and OMP sessions",
                discussion: nil,
                signature: CommandSignature(),
                subcommands: [
                    CommandDescriptor(
                        name: "list",
                        abstract: "List live Codex, Claude Code, pi, and OMP sessions",
                        discussion: nil,
                        signature: sessionsSignature),
                    CommandDescriptor(
                        name: "focus",
                        abstract: "Focus the window for a session",
                        discussion: nil,
                        signature: sessionsFocusSignature),
                ],
                defaultSubcommandName: "list"),
            CommandDescriptor(
                name: "serve",
                abstract: "Serve usage, cost, and dashboard JSON over HTTP",
                discussion: nil,
                signature: serveSignature),
            Self.dashboardCommandDescriptor(),
            CommandDescriptor(
                name: "config",
                abstract: "Config utilities",
                discussion: nil,
                signature: CommandSignature(),
                subcommands: [
                    CommandDescriptor(
                        name: "validate",
                        abstract: "Validate config file",
                        discussion: nil,
                        signature: configSignature),
                    CommandDescriptor(
                        name: "dump",
                        abstract: "Print normalized config JSON",
                        discussion: nil,
                        signature: configDumpSignature),
                    CommandDescriptor(
                        name: "providers",
                        abstract: "List provider enablement",
                        discussion: nil,
                        signature: configSignature),
                    CommandDescriptor(
                        name: "enable",
                        abstract: "Enable a provider",
                        discussion: nil,
                        signature: configProviderToggleSignature),
                    CommandDescriptor(
                        name: "disable",
                        abstract: "Disable a provider",
                        discussion: nil,
                        signature: configProviderToggleSignature),
                    CommandDescriptor(
                        name: "set-api-key",
                        abstract: "Store a provider API key",
                        discussion: nil,
                        signature: configSetAPIKeySignature),
                ],
                defaultSubcommandName: "validate"),
            Self.hooksCommandDescriptor(),
            CommandDescriptor(
                name: "cache",
                abstract: "Cache management",
                discussion: nil,
                signature: CommandSignature(),
                subcommands: [
                    CommandDescriptor(
                        name: "clear",
                        abstract: "Clear cached data (cookies, cost, or all)",
                        discussion: nil,
                        signature: cacheSignature),
                ],
                defaultSubcommandName: "clear"),
            Self.cookieCommandDescriptor(),
            CommandDescriptor(
                name: "diagnose",
                abstract: "Run provider diagnostic and emit safe JSON export",
                discussion: nil,
                signature: diagnoseSignature),
        ]
    }

    private static func dashboardCommandDescriptor() -> CommandDescriptor {
        CommandDescriptor(
            name: "dashboard",
            abstract: "Print a dashboard-v1 snapshot as JSON",
            discussion: nil,
            signature: CommandSignature.describe(DashboardOptions()))
    }

    private static func cookieCommandDescriptor() -> CommandDescriptor {
        CommandDescriptor(
            name: "cookie",
            abstract: "Cookie management",
            discussion: nil,
            signature: CommandSignature(),
            subcommands: [
                CommandDescriptor(
                    name: "refresh",
                    abstract: "Re-import browser cookie for a provider",
                    discussion: "Clears the provider cookie cache and re-imports through its browser-backed " +
                        "web strategy. Prompt-capable browsers require --allow-keychain-prompt.",
                    signature: CommandSignature.describe(CookieOptions())),
            ],
            defaultSubcommandName: "refresh")
    }

    // MARK: - Helpers

    private static func bootstrapLogging(path: [String], values: ParsedValues) {
        CodexBarLog.bootstrapIfNeeded(self.loggingConfiguration(path: path, values: values))
    }

    static func loggingConfiguration(path: [String], values: ParsedValues) -> CodexBarLog.Configuration {
        let isJSON = values.flags.contains("jsonOutput") || values.flags.contains("jsonOnly")
        let verbose = values.flags.contains("verbose")
        let rawLevel = values.options["logLevel"]?.last
        let level = Self.resolvedLogLevel(verbose: verbose, rawLevel: rawLevel)
        let destination: CodexBarLog.Destination = path == ["diagnose"] ? .discard : .stderr
        return .init(destination: destination, level: level, json: isJSON)
    }

    static func resolvedLogLevel(verbose: Bool, rawLevel: String?) -> CodexBarLog.Level {
        CodexBarLog.parseLevel(rawLevel) ?? (verbose ? .debug : .error)
    }

    static func effectiveArgv(_ argv: [String]) -> [String] {
        guard let first = argv.first else { return ["usage"] }
        if first.hasPrefix("-") {
            return ["usage"] + argv
        }
        return argv
    }
}
