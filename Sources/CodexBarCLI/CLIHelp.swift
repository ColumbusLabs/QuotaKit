import CodexBarCore
import Foundation

extension CodexBarCLI {
    static func cardsHelp(version: String) -> String {
        """
        QuotaKit \(version)

        Usage:
          quotakit cards [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>] [-v|--verbose]
                        [--provider \(ProviderHelp.list)]
                        [--account <label>] [--account-index <index>] [--all-accounts]
                        [--no-credits] [--no-color] [--status] [--source <auto|web|cli|oauth|api>]
                        [--web-timeout <seconds>] [--web-debug-dump-html] [--antigravity-plan-debug] [--augment-debug]
                        [--brief]

        Description:
          Print a one-shot usage snapshot as a responsive card grid in the terminal.
          Honors enabled providers from config and reuses the same fetch flags as quotakit usage.
          Failed providers are summarized in a footer instead of error cards.
          Enabled claude-swap lists with 2+ accounts replace Claude cards unless an account or
          explicit non-auto `--source` CLI flag is selected.
          Sentinel accounts remain visible without metrics; claude-swap adapter failures use a separate footer entry.
          Use --brief for a compact table layout (Provider / Usage / Reset).
          Stdout is always the rendered card/table text; --json-output only affects stderr logs.

        Global flags:
          -h, --help      Show help
          -V, --version   Show version
          -v, --verbose   Enable verbose logging
          --no-color      Disable ANSI colors in text output
          --log-level <trace|verbose|debug|info|warning|error|critical>
          --json-output   Emit machine-readable logs (JSONL) to stderr

        Examples:
          quotakit cards
          quotakit cards --provider codex
          quotakit cards --provider all --status
          quotakit cards --brief
          quotakit cards --no-color
        """
    }

    static func usageHelp(version: String) -> String {
        """
        QuotaKit \(version)

        Usage:
          quotakit usage [--format text|json]
                       [--json]
                       [--json-only]
                       [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>] [-v|--verbose]
                       [--provider \(ProviderHelp.list)]
                       [--account <label>] [--account-index <index>] [--all-accounts]
                       [--no-credits] [--no-color] [--pretty] [--status] [--source <auto|web|cli|oauth|api>]
                       [--web-timeout <seconds>] [--web-debug-dump-html] [--antigravity-plan-debug] [--augment-debug]

        Description:
          Print usage from enabled providers as text (default) or JSON. Honors your in-app toggles.
          Output format: use --json (or --format json) for JSON on stdout; use --json-output for JSON logs on stderr.
          Source behavior is provider-specific:
          - Codex: OpenAI web dashboard (usage limits, credits remaining, code review remaining, usage breakdown).
            Auto falls back to Codex CLI only when cookies are missing.
          - Claude: claude.ai API.
            Auto falls back to Claude CLI only when cookies are missing.
          - Kilo: app.kilo.ai API.
            Auto falls back to Kilo CLI when API credentials are missing or unauthorized.
          Token accounts are loaded from the resolved QuotaKit config file.
          Use --account or --account-index to select a specific token account.
          Use --all-accounts to fetch every token account, or every visible Codex account for Codex.
          Account selection requires a single provider.

        Global flags:
          -h, --help      Show help
          -V, --version   Show version
          -v, --verbose   Enable verbose logging
          --no-color      Disable ANSI colors in text output
          --log-level <trace|verbose|debug|info|warning|error|critical>
          --json-output   Emit machine-readable logs (JSONL) to stderr

        Examples:
          quotakit usage
          quotakit usage --provider claude
          quotakit usage --provider gemini
          quotakit usage --format json --provider all --pretty
          quotakit usage --provider all --json
          quotakit usage --status
          quotakit usage --provider codex --source web --format json --pretty
        """
    }

    static func costHelp(version: String) -> String {
        """
        QuotaKit \(version)

        Usage:
          quotakit cost [--format text|json]
                       [--json]
                       [--json-only]
                       [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>] [-v|--verbose]
                       [--provider \(ProviderHelp.list)]
                       [--no-color] [--pretty] [--refresh] [--days <days>] [--group-by project]

        Description:
          Print local token cost usage from Claude/Codex native logs plus supported pi sessions.
          This does not require web or CLI access and uses cached scan results unless --refresh is provided.

        Examples:
          quotakit cost
          quotakit cost --provider codex --group-by project
          quotakit cost --provider claude --format json --pretty
        """
    }

    static func sessionsHelp(version: String) -> String {
        """
        QuotaKit \(version)

        Usage:
          quotakit sessions [--json] [--pretty]
          quotakit sessions focus <id>

        Description:
          List live local Codex and Claude Code agent sessions.
          JSON uses stable AgentSession field names and ISO-8601 dates.
          Focus activates the owning terminal or desktop app on macOS.

        Examples:
          quotakit sessions
          quotakit sessions --json
          quotakit sessions focus 019f3497-73bf-7df3-a173-4f67d968914a
        """
    }

    static func serveHelp(version: String) -> String {
        """
        QuotaKit \(version)

        Usage:
          quotakit serve [--host <host>] [--port <port>] [--refresh-interval <seconds>]
                         [--request-timeout <seconds>]
                         [--dashboard-token <token>] [--allow-plain-http]
                         [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>]
                         [-v|--verbose]

        Description:
          Start a foreground HTTP server that exposes existing CLI JSON payloads and a
          token-gated dashboard snapshot. The server binds to 127.0.0.1 by default;
          `localhost` is normalized to 127.0.0.1.
          GET /dashboard/v1/snapshot requires "Authorization: Bearer YOUR_TOKEN" and fails
          closed (401) when no token is configured. Set the token with --dashboard-token or,
          preferably, the QUOTAKIT_DASHBOARD_TOKEN environment variable (argv leaks via ps).
          Transport is plain HTTP: the token crosses the network in cleartext on every
          request. A non-loopback --host therefore requires both a dashboard token and
          --allow-plain-http, which records that you accept that trade-off. On a
          non-loopback host the token also gates /usage and /cost (account data);
          /health is always open. Use a TLS-terminating reverse proxy for anything
          beyond a trusted network segment.

        Endpoints:
          GET /health
          GET /usage
          GET /usage?provider=claude
          GET /usage?provider=all
          GET /cost
          GET /cost?provider=codex
          GET /dashboard/v1/snapshot

        Examples:
          quotakit serve
          quotakit serve --port 8080 --refresh-interval 60 --request-timeout 30
          QUOTAKIT_DASHBOARD_TOKEN=YOUR_TOKEN quotakit serve
          QUOTAKIT_DASHBOARD_TOKEN=... quotakit serve --host 0.0.0.0 --allow-plain-http
          curl http://127.0.0.1:8080/usage?provider=all
          curl -H "Authorization: Bearer $QUOTAKIT_DASHBOARD_TOKEN" \\
            http://127.0.0.1:8080/dashboard/v1/snapshot
        """
    }

    static func configHelp(version: String) -> String {
        """
        QuotaKit \(version)

        Usage:
          quotakit config validate [--format text|json]
                                 [--json]
                                 [--json-only]
                                 [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>]
                                 [-v|--verbose]
                                 [--pretty]
          quotakit config dump [--format text|json]
                             [--json]
                             [--json-only]
                             [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>]
                             [-v|--verbose]
                             [--pretty]
          quotakit config providers [--format text|json] [--json] [--json-only] [--pretty]
          quotakit config enable --provider <name> [--format text|json] [--json] [--json-only] [--pretty]
          quotakit config disable --provider <name> [--format text|json] [--json] [--json-only] [--pretty]
          quotakit config set-api-key --provider <name> (--api-key <key>|--stdin)
                                    [--label <label>] [--usage-scope team]
                                    [--organization-id <org>] [--workspace-id <project>]
                                    [--no-enable]
                                    [--format text|json] [--json] [--json-only] [--pretty]

        Description:
          Validate or print the QuotaKit config file (default: validate).
          providers lists persistent provider enablement.
          enable/disable updates the same provider toggle used by Settings.
          set-api-key stores a provider API key in the resolved config file and enables that provider by default.
          For z.ai team usage, add --usage-scope team with BigModel organization and project IDs; this stores
          the key as a token account instead of a provider-level personal key.

        Examples:
          quotakit config validate --format json --pretty
          quotakit config dump --pretty
          quotakit config providers
          quotakit config enable --provider grok
          quotakit config disable --provider cursor
          printf '%s' "$ELEVENLABS_API_KEY" | quotakit config set-api-key --provider elevenlabs --stdin
          printf '%s' "$Z_AI_API_KEY" | quotakit config set-api-key --provider zai --stdin \\
            --label Team --usage-scope team --organization-id org_... --workspace-id proj_...
        """
    }

    static func cacheHelp(version: String) -> String {
        """
        QuotaKit \(version)

        Usage:
          quotakit cache clear <--cookies|--cost|--all>
                              [--provider <name>]
                              [--format text|json]
                              [--json]
                              [--json-only]
                              [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>]
                              [-v|--verbose]
                              [--pretty]

        Description:
          Clear cached data. Use --cookies to clear browser cookie caches (stored in Keychain),
          --cost to clear cost usage scan caches, or --all for both.
          Optionally specify --provider with --cookies to clear cookies for a single provider only.

        Examples:
          quotakit cache clear --cookies
          quotakit cache clear --cookies --provider claude
          quotakit cache clear --cost
          quotakit cache clear --all
          quotakit cache clear --all --format json --pretty
        """
    }

    static func hooksHelp(version: String) -> String {
        """
        QuotaKit \(version)

        Usage:
          quotakit hooks list [--format text|json] [--pretty]
          quotakit hooks enable
          quotakit hooks disable
          quotakit hooks test <event> --provider <name>

        Description:
          Run external commands when quota/provider events occur. Rules are stored in the
          shared config file and are disabled by default. Events:
          quota_low, quota_reached, quota_reset, provider_unavailable, provider_recovered,
          refresh_failed.

          Commands run directly (no shell), receive event metadata via CODEXBAR_* environment
          variables and a JSON payload on stdin, and are timed out. Only configure commands you trust.

        Examples:
          quotakit hooks list
          quotakit hooks enable
          quotakit hooks test quota_reached --provider codex
          quotakit hooks test quota_low --provider claude
        """
    }

    static func diagnoseHelp(version: String) -> String {
        """
        QuotaKit \(version)

        Usage:
          quotakit diagnose --provider <name|all> --format json
                           [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>]
                           [-v|--verbose]
                           [--redact] [--output <path>]
                           [--pretty]

        Description:
          Run provider diagnostic fetches and print a safe JSON export for issue reporting.
          The export is redacted and omits raw API tokens, cookies, auth headers, emails,
          account IDs, org IDs, raw responses, and billing-history records.

        Examples:
          quotakit diagnose --provider minimax --format json --redact --output diagnostic.json
          quotakit diagnose --provider minimax --format json --pretty
          quotakit diagnose --provider claude --format json --pretty
          quotakit diagnose --provider all --format json
        """
    }

    static func rootHelp(version: String) -> String {
        """
        QuotaKit \(version)

        Usage:
          quotakit [--format text|json]
                  [--json]
                  [--json-only]
                  [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>] [-v|--verbose]
                  [--provider \(ProviderHelp.list)]
                  [--account <label>] [--account-index <index>] [--all-accounts]
                  [--no-credits] [--no-color] [--pretty] [--status] [--source <auto|web|cli|oauth|api>]
                  [--web-timeout <seconds>] [--web-debug-dump-html] [--antigravity-plan-debug] [--augment-debug]
          quotakit cards [--provider \(ProviderHelp.list)] [--brief] [--no-color] [--status]
          quotakit cost [--format text|json]
                       [--json]
                       [--json-only]
                       [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>] [-v|--verbose]
                       [--provider \(ProviderHelp.list)] [--no-color] [--pretty] [--refresh]
                       [--days <days>] [--group-by project]
          quotakit sessions [--json] [--pretty]
          quotakit sessions focus <id>
          quotakit serve [--host <host>] [--port <port>] [--refresh-interval <seconds>]
                       [--request-timeout <seconds>]
                       [--dashboard-token <token>] [--allow-plain-http]
                       [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>] [-v|--verbose]
          quotakit config <validate|dump|providers> [--format text|json]
                                        [--json]
                                        [--json-only]
                                        [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>]
                                        [-v|--verbose]
                                        [--pretty]
          quotakit config enable --provider <name>
          quotakit config disable --provider <name>
          quotakit config set-api-key --provider <name> (--api-key <key>|--stdin)
          quotakit config set-api-key --provider zai --stdin --usage-scope team
                                   --organization-id <org> --workspace-id <project>
          quotakit hooks <list|enable|disable> [--format text|json] [--pretty]
          quotakit hooks test <event> --provider <name>
          quotakit cache clear <--cookies|--cost|--all> [--provider <name>]
          quotakit diagnose --provider <name|all> --format json [--redact] [--output <path>] [--pretty]

        Global flags:
          -h, --help      Show help
          -V, --version   Show version
          -v, --verbose   Enable verbose logging
          --no-color      Disable ANSI colors in text output
          --log-level <trace|verbose|debug|info|warning|error|critical>
          --json-output   Emit machine-readable logs (JSONL) to stderr

        Examples:
          quotakit
          quotakit --format json --provider all --pretty
          quotakit --provider all --json
          quotakit --provider gemini
          quotakit cards --provider all --status
          quotakit cards --brief
          quotakit cost --provider claude --format json --pretty
          quotakit sessions --json
          quotakit serve --port 8080
          quotakit config validate --format json --pretty
          quotakit config enable --provider grok
          quotakit config set-api-key --provider elevenlabs --stdin
          quotakit hooks test quota_reached --provider codex
          quotakit cache clear --cookies
          quotakit diagnose --provider minimax --format json --redact --output diagnostic.json
          quotakit diagnose --provider minimax --format json --pretty
          quotakit diagnose --provider all --format json
        """
    }
}
