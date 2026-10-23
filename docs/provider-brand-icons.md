# Provider artwork in Usage & Spend

QuotaKit preserves original provider colors on provider-level Usage & Spend icons. Account, source, and model child rows keep the existing monochrome icons; menu and widget palette behavior is unchanged. Colored and monochrome images have separate caches.

Artwork adopted from the reviewed steipete/CodexBar source range retains its documented primary-source provenance:

| Provider | Artwork source |
| --- | --- |
| Soniox (monochrome) | [Soniox website](https://soniox.com/) | Official symbol path retained as a monochrome template; currentColor supports adaptive rendering. |
| Trae CN (monochrome) | [Trae CN website](https://www.trae.cn/) | Official symbol retained as a monochrome template; currentColor supports adaptive rendering. |
| Codex | [OpenAI Codex](https://openai.com/codex/) product artwork |
| Antigravity | [Google Antigravity homepage PNG](https://antigravity.google/assets/image/antigravity-logo.png), retained unchanged |
| Claude | Existing bundled silhouette with Anthropic’s documented accent `#D97757`; upstream records this as a palette-backed variant |
| Claude Platform | Same Anthropic silhouette under its own provider asset mapping; uses the Console provider accent `#CC7C5E` |
| Mistral | [Mistral brand resources](https://mistral.ai/brand/) |
| Muse / Meta | [Meta developer artwork](https://dev.meta.ai/logo/meta-logo-with-text.svg), symbol retained without wordmark |
| Bedrock | [AWS architecture icons](https://aws.amazon.com/architecture/icons/), padded square view box |
| Vertex AI | [Google Cloud icons](https://cloud.google.com/icons), original vector artwork |
| Replicate | [Official Replicate homepage header SVG](https://replicate.com/), verified 2026-10-10; preserved three polygon paths and `currentColor`, expanded the viewBox for transparent padding |
| Pi | [Official Pi favicon](https://pi.dev/favicon.svg), verified 2026-10-08 | Preserved the three block paths and `560×560` viewBox; use `currentColor` for adaptive template rendering across Mac, iPhone, and the CLI dashboard. |
| fal (monochrome) | [fal.ai](https://fal.ai/) site header mark, verified 2026-10-11 | Kept the evenodd mark path without the wordmark; `currentColor` and a padded square view box support adaptive template rendering. |
| FLORA (monochrome) | [Standalone Flower mark](https://www.flora.ai/marketing/brand/flower-display.svg) linked from the [FLORA brand page](https://www.flora.ai/brand), verified 2026-10-11 | Preserved the four-petal mark and replaced white fill with `currentColor` for adaptive template rendering. |
| Munito (monochrome) | [Official docs favicon](https://docs.munito.ai/favicon.svg), verified 2026-10-14 | Preserved the pixel-cube row paths and `32×32` geometry; dropped the lime eye pixels so the eyes read as template holes, replaced the face fills with `currentColor`, and kept the three faces readable through opacity. Square viewBox `-11.8 -11.8 55.6 55.6` pads the mark for the provider icon. |
| TypeSafe (monochrome) | Existing bundled TypeSafe mark from the provider integration (#3756) | Preserved the evenodd path and `currentColor`. Replaced the tall `96.9556 50 206.0894 300` viewBox, which AppKit stretched edge to edge across the square 18 pt slot, with the centered square viewBox `24.68 24.68 350.65 350.65`. The mark keeps its proportions at 15.4 pt tall and covers 296 lit px at 18 pt@2x (the stretched crop covered 589); app, website logo and generated CLI dashboard share the same SVG bytes. |

The colored Pi website logo is not bundled because its redistribution terms were not established. The monochrome official favicon is used consistently by QuotaKit's Mac, iPhone, and embedded CLI dashboard.

The retained assets are provider marks, not QuotaKit application icons. Source tests check cache separation and decoded colored pixels, and synthetic rendering fixtures cover light/dark and narrow layouts. Upstream packaged screenshots are historical evidence and are not QuotaKit runtime qualification.

| Resource | SHA-256 |
| --- | --- |
| `Brand-ProviderIcon-antigravity.png` | `193ba1805de11c23cd0c7a1df92aa0a886708e57350f6f7766100afe5befed73` |
| `Brand-ProviderIcon-bedrock.svg` | `6a0f3817d771064f3d4cb8687e415417c9abccb3930b049bb8c2643f787ec224` |
| `Brand-ProviderIcon-claude.svg` | `4cd39a3832c842390c21a6598dba20d4db91632a978cb34e39aa1659fe88fe5c` |
| `ProviderIcon-claudeplatform.svg` | `497a88a780831512317b6dd061285e2ec2608abf09a94a5f24ee9019a4d3ef8b` |
| `Brand-ProviderIcon-codex.png` | `8e82b26c98a10e45798ce48124515720657f7735fb8d0853b3f087eaa8a6b74e` |
| `Brand-ProviderIcon-mistral.svg` | `13e29ba8fa7a2a01a3086b1cf6601e72fd389ffaac3139ccd95f046cc6f53524` |
| `Brand-ProviderIcon-muse.svg` | `b49f20f0738c318be02177b1823bc702c6007fe9c0ec20bba8641454cff20bd3` |
| `Brand-ProviderIcon-vertexai.svg` | `17922247f3110026fd637c531d0604c67a00c9a58a6e152030f2242b9fd48a8e` |
| `docs/logos/soniox.svg` | `3811c11ff1f9794cddbe76ffdf83b69bb8f3245fa45332a983436b62d2bd6e0f` |
| `docs/logos/traecn.svg` | `567a5551a5204acbbfd4d89b5954c57128d605b64878169b1730b3a202067b97` |
