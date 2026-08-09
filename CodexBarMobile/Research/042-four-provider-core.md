# Four-provider core teardown

Status: done

## Objective

Reduce QuotaKit to the four services used by its owner: Codex, Claude, Cursor,
and consumer Grok. Keep the Mac app, macOS CLI, iPhone companion, widgets, push
notifications, CloudKit synchronization, history, and account grouping.

## Product boundary

- `UsageProvider` is exactly `codex`, `claude`, `cursor`, and `grok`.
- Retired provider configuration and stale CloudKit data decode safely but are
  operationally inert and invisible.
- No live configuration, Keychain item, CloudKit zone, or production schema is
  deleted by this source migration. The mobile app does not delete retired
  provider records; after the next four-provider Mac publish, the Mac's
  established reconciliation path removes those stale whole-provider records
  so they cannot linger on dynamic clients.
- Transition-notification subscriptions for retired providers receive an
  explicit, idempotent cleanup path; the current set is twelve subscriptions
  (four providers by three transition states).
- Codex keeps its OpenAI web/dashboard infrastructure. Standalone OpenAI API,
  xAI developer billing, Groq, and every other provider are retired.
- Generic provider descriptors, fetch abstractions, cost/history storage,
  SweetCookieKit, Crypto, SQLite, and adaptive refresh remain where the four
  providers still use them.

## Removed surfaces

- Fifty-six retired provider identities and their first-party implementations, tests, fixtures,
  icons, documentation, and provider-specific model/card fields.
- Custom/user provider plugins, bundled JavaScript providers, and QuickJS.
- Linux-only products/tests/workflows and adaptive replay tools. The macOS CLI
  and `AdaptiveRefreshCore` remain.
- StoreKit/Pro entitlement gates and remote product configuration. Retained
  local features become directly available.
- Non-English localization resources after the retained UI is stable and the
  localization audit is updated for an English-only product.

## Compatibility and safety

- Keep bundle identifiers and CloudKit container, zone, record, and schema
  identifiers unchanged.
- Keep string-backed provider IDs on persisted and wire boundaries so unknown
  historical IDs can be ignored without crashes.
- New Mac sync writes publish only the four retained providers. Existing Mac
  reconciliation removes stale whole-provider records through the established
  sync path; the mobile app also filters historical retired records before
  presentation.
- Preserve the scheduled Codex automation, its prompt/memory/schedule, the
  upstream-monitor workflow, `version.env` cursor fields,
  `Scripts/check_upstreams.sh`, and `Scripts/review_upstream.sh` exactly.
- No release, upload, deployment, build-number bump, or live account probe is
  part of this implementation.

## Mobile implementation notes

- `QuotaKitProviderCatalog` is the shared four-ID allowlist used at the
  CloudKit merge, in-memory cache, SwiftData hydrate/write, cost-ledger,
  provider-list, widget decode/publication, and presentation boundaries.
- The allowlist is intentionally not a decoding enum. Existing payload fields,
  record types, container ID, zone names, and record-name formats remain intact
  so data written by older Macs still decodes before retired rows are ignored.
- Subscription cleanup uses the frozen 56-provider retirement inventory to
  select exactly 168 transition subscription IDs. It does not delete by prefix
  and therefore preserves the 12 live IDs and unrelated CloudKit subscriptions.
- The mobile layer never deletes retired provider records from production.
  Mac reconciliation remains responsible for publishing only the live provider
  set and removing stale whole-provider records through its existing sync path.
- A pre-upgrade widget snapshot or SwiftData cache is filtered when decoded or
  hydrated, so retired providers cannot reappear while waiting for a new Mac
  publication.
- Provider-specific compatibility fields remain in shared Codable payloads for
  this migration release. Removing those wire fields is a later schema cleanup,
  after all supported Mac versions have stopped writing them.

## Verification gates

1. Generated provider manifests and documentation agree on the exact four.
2. Configuration migration tests cover historical and unknown provider IDs.
3. Mac build, lint, focused provider/sync/widget tests, and `make test` pass
   with test Keychain access suppressed.
4. Mobile generation, unsigned simulator build/tests, CloudKit merge tests,
   widget tests, and notification subscription cleanup tests pass.
5. Package/resource audits find no shipped retired provider or plugin payload.
6. An independent review confirms the protected automation files are unchanged
   and no release operation occurred.

## Final verification

- Repository lint passes, including SwiftFormat, SwiftLint, exact-four provider
  manifests and palettes, localization completeness, customer branding, package
  scripts, documentation links, and CI path gates.
- The macOS core, CLI, widget, and app targets build. `make test` passes all 537
  discovered selections across 45 shards with no retry or timeout.
- The complete mobile unit target passed after the four-provider migration (83
  XCTest plus 474 Swift Testing tests). Focused post-prune provider,
  subscription, CloudKit/cache, widget, and localization suites also pass.
- The final mobile catalog compiles with `xcstringstool` and contains every one
  of the 179 localized source keys. A same-state final Xcode rerun was blocked
  before compilation by an unrelated hung build service from another project;
  no QuotaKit compiler or test failure was emitted.
- Protected Codex/upstream automation files remain unchanged. No live account
  probe, release, upload, deployment, or build-number bump was performed.
