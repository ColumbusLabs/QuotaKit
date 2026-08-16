---
summary: "Current and historical engineering notes for CodexBar Keychain prompt containment."
read_when:
  - Auditing Keychain access boundaries
  - Investigating legacy secret migration
  - Comparing old startup-migration guidance with the current architecture
---

# Keychain prompt containment: engineering note

The current design treats Keychain access as an interaction boundary, not as a property that can be fixed by changing
an item's accessibility class. Background work should fail closed, user-initiated work may acknowledge deliberate
interactive access, and all first-party Security.framework item operations route through `KeychainSecurity`.

User-facing behavior and troubleshooting live in [Keychain prompts](keychain-prompts.md).

## Current boundaries

| Previous statement in this doc | Current behavior |
| --- | --- |
| CodexBar stores provider credentials only in keychain | Manual/provider settings are config-file backed (`~/.codexbar/config.json`), while keychain is still used for runtime caches and Claude OAuth bootstrap fallback. |
| `ClaudeOAuthCredentials.swift` migrated CodexBar-owned Claude OAuth keychain items | Claude OAuth primary source is Claude CLI keychain service (`Claude Code-credentials`), with CodexBar cache in `com.steipete.codexbar.cache` (`oauth.claude`). |
| Migration runs in `CodexBarApp.init()` | Migration runs in `HiddenWindowView` `.task` via detached task (`KeychainMigration.migrateIfNeeded()`). |
| Post-migration prompts should be zero in all Claude paths | Legacy-store migration uses no-UI reads; Claude OAuth launch/background refresh never prompts. Promptable Claude CLI keychain reads are limited to explicit user actions. |
| Log category is `KeychainMigration` | Category is `keychain-migration` (kebab-case). |

## Unified legacy migration

`CodexBarConfigMigrator` is the single migration owner for retired token, cookie, MiniMax, Kimi, OpenCode, and token-
account stores. It reads every legacy source before cleanup, persists successfully read values idempotently, and only
clears legacy stores after config persistence succeeds and every loader was readable. A loader failure records the
provider/store identity without secret data, blocks all cleanup for that launch, and leaves
`codexbar.legacySecretsMigrationCompleted` unset so the next launch retries.

This ordering matters: “not found” is a successful read with no value, while “unreadable” is a migration failure. The
latter must never be collapsed into absence because doing so could mark migration complete or clear another store
whose value was recovered successfully.

## Retired accessibility migration

Load order for credentials:
1. Environment override (`CODEXBAR_CLAUDE_OAUTH_TOKEN`, scopes env key).
2. In-memory cache.
3. CodexBar keychain cache (`com.steipete.codexbar.cache`, account `oauth.claude`).
4. `~/.claude/.credentials.json`.
5. Claude CLI keychain service: `Claude Code-credentials` (promptable only during explicit user actions).

Prompt mitigation:
- Non-interactive keychain probes use `KeychainNoUIQuery` with `LAContext.interactionNotAllowed`.
- Pre-alert is shown only for user-action reads when preflight suggests interaction may be required.
- Denials are cooled down in the background via `claudeOAuthKeychainDeniedUntil`
  (`ClaudeOAuthKeychainAccessGate`). User actions (menu open / manual refresh) clear this cooldown.
- Auto-mode availability checks use non-interactive loads with prompt cooldown respected.
- Background cache-sync-on-change also performs non-interactive Claude keychain probes (`syncWithClaudeKeychainIfChanged`)
  and can update cached OAuth data when the token changes.
- The experimental `/usr/bin/security` reader is skipped outside user actions because it can trigger macOS Keychain UI.

### Why two Claude keychain prompts can still happen after a user action
When QuotaKit does not have usable OAuth credentials in its own cache (`com.steipete.codexbar.cache` / `oauth.claude`),
an explicit user action can fall through to Claude CLI keychain reads.

That user-action flow can perform up to two interactive reads:
1. Interactive read of the newest discovered keychain candidate.
2. If that does not return usable data, interactive legacy service-level fallback read.

Routine tests run with `CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1` through `Scripts/test.sh`. Tests use task overrides,
query construction checks, source audits, and store doubles. No test source except the audit itself may contain a
direct Security item API call, and routine verification must not query the real Keychain, import browser cookies, or
launch live provider probes.

Relevant implementation files:

- `Sources/CodexBarCore/KeychainSecurity.swift`
- `Sources/CodexBarCore/KeychainAccessGate.swift`
- `Sources/CodexBarCore/KeychainNoUIQuery.swift`
- `Sources/CodexBarCore/BrowserCookieAccessGate.swift`
- `Sources/CodexBar/Config/CodexBarConfigMigrator.swift`
- `Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentials.swift`
