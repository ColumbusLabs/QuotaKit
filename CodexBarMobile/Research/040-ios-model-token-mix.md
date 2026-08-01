# iOS Model Token Mix

Status: done

The iPhone Cost dashboard previously displayed only a cost-ranked Model Mix,
despite the shared sync contract already carrying Codex standard/priority model
token counts. This change adds a Cost / Tokens control directly in the iOS
Model Mix header. It preserves the current cost view as the default and uses
the stored choice on later launches.

The sync envelope now also carries optional `totalTokens` for every model
breakdown. Older payloads remain compatible: iOS derives a Codex total from
the existing standard and priority token fields. Token mode intentionally
shows only model rows with an attributable token total instead of inventing a
proportional allocation from dollar cost.

Verification: shared sync contract tests; iPhone 17 Pro simulator dashboard
tests (23 passed); Cost Window Ledger equivalence tests (3 passed); repository
lint and full test suite. Build 174 is prepared for TestFlight upload.
