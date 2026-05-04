<!-- ⚠ This template is required. Delete sections that don't apply, but
     don't delete the headers — reviewers depend on the consistent
     structure. -->

## What

<!-- One-paragraph summary of what this PR changes. -->

## Why

<!-- Why is this change needed? Link to Todoist task / issue / Research
     doc when relevant. -->

## Mock-first quality (Mac 0.23.5+)

<!--
This section is a *blocking* checklist. CodexBar's mock-first
infrastructure (`Sources/CodexBar/Sync/MockProviderInjector.swift`)
exists so every change can be tested without real provider
subscriptions. PRs that skip this section will be requested back.

Tick the appropriate boxes:
-->

- [ ] **Mock data covers the change.** If this PR introduces a new
  provider behavior, error state, multi-account scenario, or cost
  dashboard surface, a corresponding mock is added/updated in
  `Sources/CodexBar/Sync/MockProviderInjector.swift` (or a comment
  here explains why no mock is needed).
- [ ] **Mock tests pass locally.** `swift test --filter
  "MockProviderInjector"` shows ≥55 tests passing.
- [ ] **No regression in existing mocks.** `swift test --filter
  "Sync|MockProviderInjector"` shows ≥136 tests passing.
- [ ] **Mock toggle still safe to flip.** Activating + deactivating
  the mock toggle (Settings → Mobile → Debug · Mock Provider Data)
  doesn't pollute real data.

## Other Quality Gates

- [ ] `swift test` passes (full suite).
- [ ] `./Scripts/lint.sh lint` passes (0 violations).
- [ ] `./Scripts/lint.sh format` shows no changes (or commits the
  format result).
- [ ] If touching iOS, `xcodebuild build` and full iOS test suite
  pass on iPhone 17 Pro simulator.
- [ ] If touching the cost JSONL parser, `parserLogicVersion` was
  bumped (CI lint enforces this).

## Risk + Rollback

- **Blast radius**: <!-- single function / one provider / sync layer / cross-cutting -->
- **Rollback plan**: <!-- "revert this PR" is fine for most changes;
                       call out manual cleanup steps for migrations
                       or CloudKit schema changes -->

## Screenshots / Logs (if UI / behavior change)

<!-- Drag screenshots here for UI changes. For behavior changes,
     attach `swift test` output, log excerpts, or
     `./Scripts/install_app.sh release` smoke-test confirmation. -->

🤖 Generated with [Claude Code](https://claude.com/claude-code)
