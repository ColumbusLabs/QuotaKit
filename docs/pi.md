---
summary: "Pi and OMP local token history, source selection, and cost accounting."
read_when:
  - Configuring the Pi provider
  - Debugging Pi or OMP session discovery and incomplete history
---

# Pi

Enable Pi in Settings → Providers to show Pi and OMP token history as a separate local source in the menu, Usage & Spend, Overview, and widgets. Pi has no subscription quota or account balance. Costs are API-rate estimates from recorded assistant usage, not a billing statement. No provider login or credential is required to read the transcripts.

The scanner supports the `openai-codex`, `anthropic`, and `amazon-bedrock` backends. Bedrock sessions stay in standalone Pi history and use the exact model ID in the cached models.dev Bedrock catalog, preserving regional and global prices. They are never mirrored into native Claude or Codex history. Other backends keep standalone Pi history incomplete; they do not become measured zero or invalidate supported partitions. Supported usage with an unknown model retains its recorded tokens and is marked unpriced. Mixed priced and unpriced history preserves the known subtotal without presenting it as a complete cost.

The `cacheWrite1h` counter (`cttl.ephemeral1h` on OMP) is the one-hour subset of `cacheWrite`, priced at twice the input rate; remaining writes use the default cache-write tariff. QuotaKit accepts `cacheWrite1h`, `cache_write_1h`, `cttl.ephemeral1h`, and `cttl.ephemeral_1h` in that order. Missing counters retain the default tariff. Invalid counts, including a one-hour count larger than total writes, keep history incomplete; a malformed first-present value does not fall through to another spelling. Pi's recorded `usage.cost` is not used to replace the independent estimate.

Cost collection can refresh the public [models.dev pricing catalog](model-pricing.md). Transcript contents stay local; the catalog request needs no credential. Existing cached prices and bundled rates remain available when a pricing refresh fails.

## Session discovery

Default session roots include `~/.pi/agent/sessions` and the supported OMP agent/profile stores. Discovery honors `PI_CODING_AGENT_DIR`, `PI_CODING_AGENT_SESSION_DIR`, OMP configuration/XDG roots, and `OMP_PROFILE` (or `PI_PROFILE` when absent). A named profile limits discovery to that profile. Invalid or unresolved explicit selectors produce incomplete history.

Running Pi/OMP processes also contribute their environment, profile, `--session-dir`, and project settings. Relative paths resolve against that process's working directory. A missing working directory cannot turn an unresolved relative selector into a successful empty scan. Retained roots from explicit command-line or settings selectors survive process exit; settings are revalidated before reuse. Removing a setting from an accessible project drops its former root, while an inaccessible project or broken settings symlink preserves the previous scoped report and its original age.

If a live process has an unreadable environment and no explicit command-line root/profile selector, QuotaKit skips that optional process during cost-root discovery and logs one summary count without exposing arguments, paths, or environment values. Default and readable process roots still contribute history on the first and later scans. Explicit selections that remain unresolved keep the history incomplete; an absolute `--session-dir` remains usable without a process environment or working directory.

Assistant turns are bucketed by their own timestamp in the selected cost time zone. Matching entry IDs within the same session count once across overlapping roots. Distinct turns remain separate. The scanner retains per-message prices and token classes rather than repricing a daily aggregate.

## Count each source once

With Pi disabled, unscoped Claude and Codex history can include their supported Pi/OMP backend partitions. With Pi and local cost tracking enabled, the app shows native Claude/Codex history alongside standalone Pi. Combined CLI selections follow the same rule. Account-scoped Codex history always remains native because machine-local Pi history does not establish account ownership. Overview and Usage & Spend use the same source accounting, including during cached hydration and completed Codex catch-up.

```bash
quotakit cost --provider pi --format json --pretty
quotakit cost --provider both --format json --pretty
quotakit cost --provider codex --provider-native-only
```

For a combined report, enable Claude, Codex, and Pi in the config, then run `quotakit cost --format json --pretty` without a provider override. Selecting Pi with Claude/Codex excludes mirrored Pi rows from those native providers. A standalone Claude/Codex selection (including `--provider both`) retains its existing inclusive behavior unless `--provider-native-only` is supplied. The same selection rule applies to dashboard and HTTP cost collection.

## Cache and incomplete history

The cache remains at the legacy `~/Library/Caches/CodexBar/cost-usage/pi-sessions-v9.json` path on macOS to preserve existing local history. It records source scope, coverage, and unsupported-history evidence, and is replaced atomically on macOS and Linux. Version 8 is rebuilt once from transcripts because it did not record sufficient scope and completeness evidence for safe reuse. An unavailable source during this upgrade leaves history unavailable until a valid scan can complete; it does not borrow an old cache's timestamp or totals.

Incomplete refreshes can preserve a previously valid report with its original source scope and scan time. If no completed scan time exists, the partial result has unknown age; it must not inherit the refresh time. Malformed records, truncated tails, inaccessible roots, and unrepresentable aggregate totals cannot advance cache freshness. Cached and debounced reads check the recorded file inventory and metadata before declaring coverage complete, without reparsing transcripts. Failed root transitions never combine old and new datasets. Incomplete Pi history leaves available rows explicitly incomplete and eligible for another refresh on the next tick, without waiting for the normal token-history TTL. A verified empty source remains distinct from an uninspected source.

Files replaced while being read leave the refresh incomplete. A pricing-catalog change requires a complete reparse before new estimates replace the prior report. An explicit refresh reparses Pi history even when file size and modification time are unchanged, including Pi usage shown under Claude or Codex.

The one-hour counter correction invalidates the Pi pricing key once, including estimates mirrored into Claude or Codex reports. Existing Pi cache rows do not retain the one-hour split, so all Pi sessions in the scan window must be reparsed before publishing corrected prices. The cache schema and native Claude/Codex caches are unchanged; subsequent refreshes resume normal cache reuse.
