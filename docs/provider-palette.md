# Provider palette

This selective refresh applies the 16 source-supported accents adopted by the
final upstream palette audit at `25bba9b7fd9ce83c33053958f7366e23b2dc8a82`.
Mac app accents and matching iOS app swatches changed, and Mac widgets now use
those accents for the reviewed providers. The final upstream audit covered 36
providers: 9 proposals were retained after contrast review, and 11 remained
unverified. QuotaKit keeps its current values for those 20 providers.

## Adopted app accents

The source links and contrast figures below are copied from the final upstream
audit. Its comparisons use white and `#222222` menu-card surfaces; they are a
contrast non-regression review, not an accessibility certification.

| Provider | QuotaKit accent before | Adopted accent | Official source | Reported contrast |
| --- | --- | --- | --- | --- |
| Abacus | `#38BDF8` | `#814EE8` | [abacus.ai](https://abacus.ai/) | light 2.14 → 5.01:1; dark 3.17:1 |
| Amp | `#DC2626` | `#F34E3F` | [Amp CSS](https://ampcode.com/_app/immutable/assets/app.ba81f8aee8e1c823.css) | light 4.83 → 3.52:1; dark 4.52:1 |
| Augment | `#8B5CF6` | `#1AA049` | [augmentcode.com](https://www.augmentcode.com/) | light 4.47 → 3.40:1; dark 4.67:1 |
| Bedrock | `#FF9900` | `#01A88D` | [AWS architecture icon package](https://d1.awsstatic.com/onedam/marketing-channels/website/public/shared/architecture-icon-release/Icon-package_07312026.5846e92413caa21490223536cc97f1269e44fa92.zip) | light 2.14 → 3.01:1; dark 5.29:1 |
| ClinePass | `#61A3FA` | `#5487C8` | [Cline CSS](https://cline.bot/_next/static/css/0b73be6370d7bf9c.css) | light 2.58 → 3.70:1; dark 4.30:1 |
| Codebuff | `#44FF00` | `#00FF95` | [Codebuff CSS](https://www.codebuff.com/_next/static/css/17f29cc619045efe.css) | light 1.35 → 1.33:1; dark 11.92:1 |
| CommandCode | `#475569` | `#8C4EDD` | [commandcode.ai](https://commandcode.ai/) | light 4.22 → 4.94:1; dark 3.22:1 |
| Cursor | `#000000` | `#F54E00` | [Cursor CSS](https://cursor.com/marketing-static/_next/static/chunks/06.4i9gbk_pby.css?dpl=dpl_Dqjhj2DDxxLKm2kkipuJt7ret4zo) | light 2.33 → 3.52:1; dark 4.52:1 |
| DeepSeek | `#527DF0` | `#4D6BFE` | [DeepSeek CSS](https://www.deepseek.com/_next/static/css/3da1ce676c85d262.css) | light 3.78 → 4.33:1; dark 3.67:1 |
| Devin | `#46B482` | `#317CFF` | [Devin CSS](https://devin.ai/_next/static/immutable/chunks/111m80s9d-n0-.css) | light 2.59 → 3.85:1; dark 4.13:1 |
| Kiro | `#D97706` | `#9046FF` | [Kiro CSS](https://kiro.dev/_next/static/css/0238e231f83df5bb.css) | light 2.14 → 4.66:1; dark 3.41:1 |
| LongCat | `#FFD100` | `#29E154` | [LongCat logo](https://s3plus.meituan.net/aigc-media-resources/longcat/yeqian-logo.svg) | light 1.46 → 1.75:1; dark 9.09:1 |
| Mistral | `#FF500F` | `#FF5229` | [Mistral CSS](https://mistral.ai/_astro/astro.BOPo2zPB.css) | light 3.28 → 3.24:1; dark 4.92:1 |
| NeuralWatt | `#1FB861` | `#D55934` | [NeuralWatt CSS](https://cdn.prod.website-files.com/693d9776ae14be12d60f5996/css/neural-watt.webflow.shared.5b3762da8.css) | light 1.83 → 3.96:1; dark 4.02:1 |
| Sub2API | `#2DC6D8` | `#14B8A6` | [Sub2API Tailwind config](https://raw.githubusercontent.com/Wei-Shaw/sub2api/main/frontend/tailwind.config.js) | light 2.06 → 2.49:1; dark 6.39:1 |
| Venice | `#3399FF` | `#3C8FDD` | [Venice CSS](https://cdn.venice.ai/_next/static/immutable/chunks/1z9-rwfn_gg4b.css) | light 2.94 → 3.41:1; dark 4.67:1 |

## New provider accents

The provider catalog additions from upstream commits `fca039015` and `81438267f` carry their descriptor accents into the iOS raw palette. `Scripts/audit_provider_palette.py` checks Mac/mobile parity. QuotaKit adapts colliding colors to preserve the mobile palette's existing distinct-provider contract: TinyApi's upstream `#F97316` matches Xiaomi MiMo, so the selected `#F28C54` separates it from existing orange brands; Linkup's near-black accent converges with Ollama gray in dark mode; Aerostack's `#6366F1` is nearly indistinguishable from OpenRouter's `#6467F2`. Provider logos remain unchanged.

| Provider | Upstream descriptor accent | QuotaKit accent | Source |
| --- | --- | --- | --- |
| Tavily | `#78B0A1` | `#78B0A1` | [Tavily usage docs](https://docs.tavily.com/documentation/api-reference/endpoint/usage) |
| Linkup | `#202020` | `#4A4A4A` | [Linkup docs](https://docs.linkup.so/pages/documentation/platform/pricing); adjusted to remain distinct from Ollama in dark mode |
| TinyApi | `#F97316` | `#F28C54` | [TinyApi dashboard](https://tinyapi.rest/dashboard); adjusted to distinguish it from Xiaomi MiMo, NeuralWatt, and ai& |
| Exa | `#0143D9` | `#0143D9` | [Exa API docs](https://exa.ai/docs/reference/team-management/get-api-key-usage) |
| Cosmic AI | `#29ABE2` | `#29ABE2` | [Cosmic CLI docs](https://www.cosmicjs.com/docs/cli) |
| Aerostack | `#6366F1` | `#4F46E5` | [Aerostack billing docs](https://docs.aerostack.dev/billing/); adjusted to distinguish it from OpenRouter |
| Sail Research | `#2C4681` | `#2C4681` | [Sail Research website](https://www.sailresearch.com/) |
| Sofya | `#B0B820` | `#B0B820` | [Sofya website](https://sofya.co/) |

## Preserved color roles

`ProviderDescriptor.branding.color` remains the Mac app accent. Mac widgets now
use that same accent for Abacus, Amp, Augment, Bedrock, ClinePass, Codebuff,
Cursor, DeepSeek, Devin, Kiro, LongCat, Mistral, NeuralWatt, Sub2API, and
Venice. CommandCode keeps its explicit black widget treatment. The iOS widget
lookup continues to preserve its previous raw colors for these providers and
applies its existing appearance adaptation; this fork-specific mobile palette
policy is independent of the Mac widget palette.

Confetti palettes were not refreshed. Moonshot's `#121212` confetti ink stays
in place, and Kimi keeps QuotaKit's documented rose accent `#F43F5E`.

## Retained proposals and fork palette decisions

The final audit rejected these nine proposals after contrast review; QuotaKit
keeps their current accents: AIand, Chutes, Copilot, Deepgram, Doubao,
Fireworks, LiteLLM, Qoder, and Sakana. It left these eleven proposals
unverified, so QuotaKit also keeps their current accents: ClawRouter, Groq,
JetBrains, Kilo, Kimi, Moonshot, Notion, OpenCode, Perplexity, T3Chat, and Warp.
No unverified proposal was inferred or adopted here.

Five retained QuotaKit accents differ from upstream's older accents. This slice
retains those established QuotaKit app colors: the upstream review adopted no
verified replacement for these providers. Copying its older RGB values would
introduce another appearance change without the source support required by this
refresh. The original reasons for the older fork differences are unknown; the
current retention decision is explicit and does not depend on reconstructing them.

| Provider | QuotaKit accent | Final upstream accent | Existing evidence and disposition |
| --- | --- | --- | --- |
| Chutes | `#00B8FF` | `#3184FF` | The proposed `#63D297` was rejected after the reported light-surface contrast fell from 3.57:1 to 1.88:1. QuotaKit's `#18A058` widget color is a separate role. Retain QuotaKit's established `#00B8FF` app accent; the rejected proposal provides no verified replacement. |
| ClawRouter | `#2A82F5` | `#596EF6` | The proposed `#1F5AE0` remains unverified. Retain QuotaKit's established `#2A82F5` app accent while no verified replacement was adopted. |
| Deepgram | `#7D3BED` | `#6467F2` | The proposed `#13EF93` was rejected after the reported light-surface contrast fell from 4.41:1 to 1.52:1. The separate Mac widget color `#0A121B` remains unchanged. Retain QuotaKit's established `#7D3BED` app accent; the rejected proposal provides no verified replacement. |
| LiteLLM | `#4C89C0` | `#4C89F0` | The proposed `#5B3FD1` was rejected after the reported dark-surface contrast fell from 4.65:1 to 2.33:1. Retain QuotaKit's established `#4C89C0` app accent; the rejected proposal provides no verified replacement. |
| OpenCode | `#0EA5E9` | `#3B82F6` | The cited brand page presents `#007AFF` as a UI accent and a grayscale logo; the proposed `#3B7DD8` remains unverified. Retain QuotaKit's established `#0EA5E9` provider app accent while no verified replacement was adopted. |

Kimi's `#F43F5E` rose is a documented QuotaKit fork choice. It remains
separate from Moonshot's unchanged `#205DEB` accent.
