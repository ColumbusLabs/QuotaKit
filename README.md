# QuotaKit

QuotaKit is a Columbus Labs app for tracking AI quota, usage, and spend across the tools you use. The Mac app gathers provider data locally, syncs it through iCloud, and the iPhone app turns that data into clear status views, alerts, share cards, and widgets.

This repository is the Columbus Labs QuotaKit codebase. It preserves upstream CodexBar history, but QuotaKit releases, bundle identifiers, iCloud containers, StoreKit products, and setup links are owned by Columbus Labs.

## Get QuotaKit

- Mac setup: [columbus-labs.com/quotakit/mac](https://columbus-labs.com/quotakit/mac)
- Mac releases: [github.com/ColumbusLabs/QuotaKit/releases/latest](https://github.com/ColumbusLabs/QuotaKit/releases/latest)
- Source repository: [github.com/ColumbusLabs/QuotaKit](https://github.com/ColumbusLabs/QuotaKit)

Install QuotaKit on your Mac first. After iCloud Sync is enabled on the Mac, the iPhone app can show synced quota data and send quota notifications.

## Highlights

- Multi-provider quota tracking for Codex, Claude, Cursor, Gemini, Grok, OpenAI, ClinePass, LongCat, Vertex AI, Mistral, Perplexity, OpenRouter, LiteLLM, ElevenLabs, Deepgram, and more.
- iCloud sync from Mac to iPhone, including quota windows, reset timing, provider status, spend, and account metadata.
- iPhone alerts when a provider runs out of quota or becomes available again.
- Cost dashboards with daily spend, model mix, provider share, and renewal-cycle progress.
- A unified Mac usage-and-spend dashboard plus optional external hooks for quota and provider-state events.
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

- [Codex](docs/codex.md) — OAuth API or local Codex CLI, plus optional OpenAI web dashboard extras.
- [OpenAI](docs/openai.md) — Admin API key usage/cost graphs with legacy credit-balance fallback.
- [Azure OpenAI](docs/azure-openai.md) — API key, endpoint, and deployment validation probe.
- [Claude](docs/claude.md) — OAuth API, browser cookies, or CLI PTY fallback; session and weekly usage where available.
- [Cursor](docs/cursor.md) — Browser session cookies for plan + usage + billing resets.
- [OpenCode](docs/opencode.md) — Browser cookies for workspace subscription usage.
- [OpenCode Go](docs/opencode.md) — Browser or local SQLite data for Go usage windows.
- [Alibaba Coding Plan](docs/alibaba-coding-plan.md) — Web cookies or API key for coding-plan quotas.
- [Alibaba Token Plan](docs/alibaba-token-plan.md) — Bailian browser/manual cookies for token-plan credits.
- [Gemini](docs/gemini.md) — OAuth-backed quota API using Gemini CLI credentials (no browser cookies).
- [Antigravity](docs/antigravity.md) — Local language server probe (experimental); no external auth.
- [Droid](docs/factory.md) — Browser cookies + WorkOS token flows for Factory usage + billing.
- [Copilot](docs/copilot.md) — GitHub device flow + Copilot internal usage API.
- [Devin](docs/devin.md) — Chrome localStorage session or manual Bearer token for daily and weekly quotas.
- [z.ai](docs/zai.md) — API token for personal/team quota, MCP, 5-hour, and hourly usage windows.
- [Manus](docs/manus.md) — Browser `session_id` auth for credit balance, monthly credits, and daily refresh tracking.
- [MiniMax](docs/minimax.md) — API token, cookie header, or browser cookies for coding-plan usage.
- [T3 Chat](docs/t3chat.md) — Browser cookies capture for Base and Overage usage buckets.
- [Kimi](docs/kimi.md) — Auth token (JWT from `kimi-auth` cookie) for weekly quota + 5‑hour rate limit.
- [Kilo](docs/kilo.md) — API token with CLI-auth fallback for Kilo Pass usage.
- [Kiro](docs/kiro.md) — CLI-based usage; monthly credits + bonus credits.
- [Vertex AI](docs/vertexai.md) — Google Cloud gcloud OAuth with token cost tracking from local Claude logs.
- [Augment](docs/augment.md) — Augment CLI or browser cookies for credits tracking and usage monitoring.
- [Amp](docs/amp.md) — Browser cookie-based authentication with Amp Free usage tracking.
- [Ollama](docs/ollama.md) — API key access plus browser cookies for Ollama Cloud usage windows.
- [Synthetic](docs/synthetic.md) — API key quota endpoint for rolling five-hour, weekly token, and search-hourly usage.
- [JetBrains AI](docs/jetbrains.md) — Local XML-based quota from JetBrains IDE configuration; monthly credits tracking.
- [Warp](docs/warp.md) — API token for GraphQL request limits and monthly credits.
- [ElevenLabs](docs/elevenlabs.md) — API key for character credits and voice slot usage.
- [OpenRouter](docs/openrouter.md) — API token for credit-based usage tracking across multiple AI providers.
- [Windsurf](docs/windsurf.md) — Browser localStorage session import or local SQLite cache for plan usage.
- [Zed](docs/zed.md) — Zed editor Keychain session for plan, edit-prediction quota, billing cycle, and overdue invoices.
- [Perplexity](docs/perplexity.md) — Account usage credits from Perplexity usage data.
- [Xiaomi MiMo](docs/mimo.md) — Browser cookies for balance and token-plan usage.
- [Doubao](docs/doubao.md) — API key for Volcengine Ark request-limit probes.
- [Sakana AI](docs/sakana.md) — Manual Cookie header for 5-hour and weekly quota windows.
- [Abacus AI](docs/abacus.md) — Browser cookie auth for ChatLLM/RouteLLM compute credit tracking.
- [Mistral](docs/mistral.md) — Browser cookies for API spend, credit balance, and monthly-plan usage.
- [DeepSeek](docs/deepseek.md) — API key for credit balance tracking (paid vs. granted breakdown).
- [Moonshot / Kimi API](docs/moonshot.md) — API key for Moonshot/Kimi API account balance tracking.
- [Venice](docs/venice.md) — API key for DIEM or USD balance tracking.
- [Codebuff](docs/codebuff.md) — API token (or `~/.config/manicode/credentials.json`) for credit balance + weekly rate limit.
- [Crof](docs/crof.md) — API key for dollar credit balance and request quota tracking.
- [Command Code](docs/command-code.md) — Browser or manual cookies for monthly USD credits from Command Code billing.
- [Qoder](docs/qoder.md) — Browser or manual cookies for Qoder big model credit usage.
- [StepFun](docs/stepfun.md) — Username + password login for Step Plan rate limits (5‑hour + weekly windows) and subscription plan name.
- [AWS Bedrock](docs/bedrock.md) — AWS access keys or a named AWS profile (SSO/assume-role via the AWS CLI) for Cost Explorer spend, monthly budgets, and optional CloudWatch Claude activity.
- [Grok](docs/grok.md) — Grok CLI billing RPC plus grok.com browser-session fallback.
- [GroqCloud](docs/groqcloud.md) — API key for Enterprise Prometheus request/token/cache-hit metrics.
- [LLM Proxy](docs/llm-proxy.md) — API key + base URL for aggregate proxy quota stats and provider breakdowns.
- [ClawRouter](docs/clawrouter.md) — API key for monthly budget, spend, requests, tokens, and routed-provider usage.
- [Wayfinder](docs/wayfinder.md) — Local router gateway polling for health, per-route breakdown, savings, and decision latency.
- [LiteLLM](docs/litellm.md) — Virtual key + proxy URL for personal and team budget/spend tracking.
- [Deepgram](docs/deepgram.md) — API key usage summaries across speech, agent, token, and TTS metrics.
- [Poe](docs/poe.md) — API key for current point balance and recent points history.
- [Chutes](docs/chutes.md) — API key for subscription usage, rolling and monthly quota windows, and pay-as-you-go quotas.
- [ClinePass](docs/providers.md) — API key usage for five-hour, weekly, and monthly plan limits.
- [LongCat](docs/providers.md) — Browser or manual-cookie usage for LongCat plan quotas.
- [Neuralwatt](docs/neuralwatt.md) — API key for subscription kWh usage and prepaid credit balance.
- [ZenMux](docs/zenmux.md) — Management API key for rolling five-hour and seven-day quota windows plus PAYG balance.
- Open to new providers: [provider authoring guide](docs/provider.md).

## Upstream And Credits

QuotaKit is derived from:

- [steipete/CodexBar](https://github.com/steipete/CodexBar)

Columbus Labs maintains QuotaKit as a product fork with its own releases, setup flow, bundle identifiers, and support surface.

The Git history intentionally preserves upstream commits and contributors. That is why GitHub may show thousands of historical commits and many contributors even though Columbus Labs owns the QuotaKit product boundary.

See [OPEN_SOURCE_CREDITS.md](OPEN_SOURCE_CREDITS.md) for recommended user-facing attribution copy and QuotaKit's product-boundary guidance.

## License

MIT. See [LICENSE](LICENSE).
