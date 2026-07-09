# QuotaKit

QuotaKit is a Columbus Labs app for tracking AI quota, usage, and spend across the tools you use. The Mac app gathers provider data locally, syncs it through iCloud, and the iPhone app turns that data into clear status views, alerts, share cards, and widgets.

This repository is the Columbus Labs QuotaKit codebase. It preserves upstream CodexBar history, but QuotaKit releases, bundle identifiers, iCloud containers, StoreKit products, and setup links are owned by Columbus Labs.

## Get QuotaKit

- Mac setup: [columbus-labs.com/quotakit/mac](https://columbus-labs.com/quotakit/mac)
- Mac releases: [github.com/ColumbusLabs/QuotaKit/releases/latest](https://github.com/ColumbusLabs/QuotaKit/releases/latest)
- Source repository: [github.com/ColumbusLabs/QuotaKit](https://github.com/ColumbusLabs/QuotaKit)

Install QuotaKit on your Mac first. After iCloud Sync is enabled on the Mac, the iPhone app can show synced quota data and send quota notifications.

## Highlights

- Multi-provider quota tracking for Codex, Claude, Cursor, Gemini, Grok, OpenAI, Vertex AI, Mistral, Perplexity, OpenRouter, LiteLLM, ElevenLabs, Deepgram, and more.
- iCloud sync from Mac to iPhone, including quota windows, reset timing, provider status, spend, and account metadata.
- iPhone alerts when a provider runs out of quota or becomes available again.
- Cost dashboards with daily spend, model mix, provider share, and renewal-cycle progress.
- QuotaKit Pro widgets for Home Screen and Lock Screen status at a glance.
- Share cards for usage and cost views.

## How It Works

1. Install QuotaKit on your Mac.
2. Enable the providers you use in Mac settings.
3. Turn on iCloud Sync.
4. Open QuotaKit on iPhone with the same iCloud account.

The Mac app does the provider-side work. The iPhone app is a companion that reads synced data, displays it clearly, and sends notifications.

## Privacy

QuotaKit is designed around local collection and private sync. Provider credentials, browser sessions, local logs, and account data are read only for the providers you enable. Synced quota data stays in your iCloud account.

Some providers may require local permissions on macOS, such as access to browser cookies, provider CLI credentials, or Keychain items. Those permissions are used for quota collection and are not a general disk scan.

## Development

This repo contains both the Mac app and the iOS companion app. iOS-specific work lives under `CodexBarMobile/`.

Common checks:

```bash
./Scripts/lint.sh lint

xcodebuild -project CodexBarMobile/CodexBarMobile.xcodeproj \
  -scheme CodexBarMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

Generate the iOS project after editing `CodexBarMobile/project.yml`:

```bash
cd CodexBarMobile
xcodegen generate
```

## Documentation

Provider setup notes and Mac provider internals live in [docs/providers.md](docs/providers.md).

Selected provider guides include [Claude](docs/claude.md), [Gemini](docs/gemini.md),
[Mistral](docs/mistral.md), [Perplexity](docs/perplexity.md),
[Qoder](docs/qoder.md), and [Synthetic](docs/synthetic.md). New provider work
should start with the [provider authoring guide](docs/provider.md).

## Upstream And Credits

QuotaKit is derived from:

- [steipete/CodexBar](https://github.com/steipete/CodexBar)

Columbus Labs maintains QuotaKit as a product fork with its own releases, setup flow, bundle identifiers, and support surface.

The Git history intentionally preserves upstream commits and contributors. That is why GitHub may show thousands of historical commits and many contributors even though Columbus Labs owns the QuotaKit product boundary.

See [OPEN_SOURCE_CREDITS.md](OPEN_SOURCE_CREDITS.md) for recommended user-facing attribution copy and QuotaKit's product-boundary guidance.

## License

MIT. See [LICENSE](LICENSE).
