# Upstream integration: November 5, 2026

Status: source implementation ready; done only when the [authoritative issue #268 completion record](https://github.com/ColumbusLabs/QuotaKit/issues/268) confirms independent review, exact-head hosted qualification and merge.

Review `897bff31731bb4b21b105f6e8bf4c32a8a8bf095..6f72afa7b378f4b2325afe71421946ebabb821b6` as one coherent batch. Preserve QuotaKit identity, complete provider catalog, shared/mobile/persistence and credential contracts, appcast/release ownership and version/build metadata.

Use current plus legacy Cursor encryption-key account lookup through guarded queries. Share the user-plugin HTTP session while keeping each task's state, response-byte cap and completion independent. Publish bounded outcomes before asynchronous transport cancellation; guard delayed admission after cancellation. Retain QuotaKit's no-argument admission seam and its stricter rule that background Claude CLI children cannot be made noninteractive and must remain prohibited. Adapt CLI Keychain documentation to the public QuotaKit identity.

Hosted CI covers auth fixtures, portable cancellation/transport/serve tests on Linux x64/ARM, Mac inventory, lint and compatibility gates. Independent adversarial review is required for authentication and shared HTTP lifetime/cancellation. No local builds/tests or live accounts, Keychain, cookies, CloudKit, installation or distribution. Per-commit classification is in `docs/upstream-sync-2026-11-05.md`; final receipts belong to issue #268.
