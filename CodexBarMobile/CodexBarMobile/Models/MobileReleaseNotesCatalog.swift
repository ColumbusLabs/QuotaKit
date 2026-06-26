import Foundation

struct ReleaseNotesVersion: Identifiable {
    struct Section: Identifiable {
        let title: String
        let items: [String]

        var id: String {
            self.title
        }
    }

    let version: String
    let status: String
    let summary: String
    let sections: [Section]

    var id: String {
        self.version
    }
}

enum MobileReleaseNotesCatalog {
    static let versions: [ReleaseNotesVersion] = [
        ReleaseNotesVersion(
            version: "1.11.1",
            status: String(localized: "Latest"),
            summary: String(
                localized: "QuotaKit Pro now gates provider, cost, history, sharing, merge, notifications, and iOS widgets for real synced data, with a cleaner QuotaKit-branded iOS experience."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Daily Spend chart — shows a clean ~30-day window and scrolls left to reveal your full cost history (30 / 90 / 365-day windows); the latest day stays pinned to the right edge."),
                        String(
                            localized: "QuotaKit Pro — Free mode keeps one selected synced provider plus basic quota details, while Pro and demo mode unlock the full provider list, cost dashboard, history charts, share actions, advanced merge controls, and visible quota alerts."),
                        String(
                            localized: "Widgets and pace — QuotaKit Pro widgets show Session and Weekly quota windows by default, with a Settings control for Both / Session / Weekly display, sanitized iPhone-side snapshot data, sync-age badges, quota-bar pace markers, and pace chips in single-window modes; daily and monthly day-count labels no longer get mistaken for weekly quota; Usage cards now match the Mac app with deficit/reserve pace labels, projected run-out timing, and expected-usage markers."),
                        String(
                            localized: "Usage organization — provider logos now match the Mac app across cards, detail screens, dashboard provider-share rows, and widgets; you can still choose which provider appears in widgets, and the Usage tab now shows a labeled Provider order button beside the live sync status."),
                        String(
                            localized: "Branding and setup — iOS screens, the app icon, share cards, update prompts, and Mac setup now use QuotaKit. The iPhone shares a Columbus Labs setup page for Mac installation instead of sending you straight to GitHub."),
                        String(
                            localized: "Sync polish — provider colors now stay distinct and readable in both appearances, and the synced-time chip keeps its status available to VoiceOver while refreshing."),
                        String(
                            localized: "Widget sync — widgets now refresh directly from CloudKit silent pushes in the background, so new Mac sync data can update the widget without opening the app first."),
                        String(
                            localized: "Remote guardrails — Columbus Labs can now update safe setup links, announcements, and feature kill switches over the air while native app changes still go through TestFlight/App Store."),
                        String(
                            localized: "Performance — synced data refreshes automatically when you return to the app, the Cost dashboard loads faster, and chart scrubbing stays smooth."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.11.0",
            status: "",
            summary: String(
                localized: "Quieter, more accurate provider data synced from your Mac — Antigravity quota rows without the noise, correct Copilot usage on zero-entitlement plans, fixed Augment parsing, and steadier Claude readings — from the QuotaKit Mac 0.32.4 sync."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Search — filter the Usage list by provider name; handy when many providers are synced."),
                        String(
                            localized: "Antigravity — quota rows are cleaner: image / lite / autocomplete / internal noise rows no longer skew the summary bar."),
                        String(
                            localized: "Copilot — zero-entitlement business tokens no longer show a misleading usage percentage."),
                        String(
                            localized: "Augment — usage parses correctly again after the upstream status-format change."),
                        String(
                            localized: "Claude — a brief sign-in hiccup no longer blanks your usage; the last good reading is kept."),
                        String(
                            localized: "Codex / Claude cost — refreshed by the v0.32 cost-scanner update; your cost cards re-scan to the corrected numbers."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update QuotaKit Mac to 0.32.4 (fork build 79.1 or later). iPhone 1.11.0 stays forward-compatible with older Mac builds — these refinements simply arrive once Mac is updated."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.10.0",
            status: "",
            summary: String(
                localized: "DeepSeek web-session usage and cost on your iPhone, Codex Spark and Antigravity per-model quota lanes synced through, and cost cards that show request counts in the right currency — from the QuotaKit Mac 0.31.0 sync."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "DeepSeek — usage card with web-session today / this-month tokens, spend, and request counts shown alongside your balance."),
                        String(
                            localized: "Codex Spark — 5-hour and weekly Spark model quota lanes now sync to your iPhone."),
                        String(
                            localized: "Antigravity — full per-model quota lanes now flow through, not just the three-family summary."),
                        String(
                            localized: "Cost cards — now show request counts and format amounts in the synced currency (e.g. EUR / CNY), not just USD."),
                        String(
                            localized: "Upstream fixes flow through automatically — the corrected Claude Enterprise extra-usage amount (no longer 100x too high), Grok / Ollama window labels and pace projection, and the Claude Design lane folded into the main Claude limit."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update QuotaKit Mac to 0.31.0 (fork build 73.2 or later) to surface the DeepSeek card and the Codex Spark / Antigravity lanes. iPhone 1.10.0 stays forward-compatible with older Mac builds — the new cards simply stay hidden until Mac is updated."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.9.0",
            status: "",
            summary: String(
                localized: "Three new providers (Azure OpenAI, Alibaba Token Plan, T3 Chat) from the QuotaKit Mac 0.29.0 sync — plus richer detail across many providers: the iPhone now surfaces more of what your Mac already tracks."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Azure OpenAI — usage card validating deployment status from your API key, endpoint, and deployment name."),
                        String(
                            localized: "Alibaba Token Plan (Bailian) — monthly token-plan quota card showing used and total credits with the reset date, imported from browser or manual cookies."),
                        String(
                            localized: "T3 Chat — web-session usage card with a 4-hour base window plus a monthly overage window."),
                        String(
                            localized: "Richer detail elsewhere too — Codex standard/fast spend split per model, an OpenRouter balance & credits card, Mistral daily cost in the Cost dashboard, the Antigravity multi-account switcher, and cost summaries that show the real history window (not always 30 days)."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update QuotaKit Mac to 0.29.0 (fork build 68.1 or later) to see the three new providers. iPhone 1.9.0 stays forward-compatible with older Mac builds — the new cards simply stay hidden until Mac is on 0.29.0."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.8.0",
            status: "",
            summary: String(
                localized: "Five dedicated provider cards (Grok / ElevenLabs / Deepgram / GroqCloud / LLM Proxy), Kiro overage badge, Anthropic Admin API spend, Claude Enterprise spend-limit, OpenAI history-window picker, OpenCode Go Zen balance, MiniMax 30-day billing, plus quota notifications now include the triggering account and Codex shows the active workspace + weekly pace."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Grok (xAI) — dedicated card showing monthly USD spend, plan tier badge, percent used, and the renewal date. Uses Grok CLI billing when available, falls back to grok.com web billing."),
                        String(
                            localized: "ElevenLabs — dedicated card with character credits primary bar, voice slots and professional voice slots rows when present, tier badge, and renewal date."),
                        String(
                            localized: "Deepgram — dedicated card with speech / agent / total hours breakdown, request count, agent tokens, optional TTS character count, and a project badge with '(of N)' hint when you have multiple projects."),
                        String(
                            localized: "GroqCloud — dedicated card with three live-rate columns (requests/min, tokens/min, cache hits/min) plus the cache-hit percentage as a coloured badge."),
                        String(
                            localized: "LLM Proxy — dedicated card showing lowest-remaining-quota headline, credential pool health (active / exhausted keys), aggregate request and token counts, and the top three upstream providers with per-provider request / token / cost breakdown."),
                        String(
                            localized: "Kiro overage — when your monthly plan is exhausted and you're paying for additional credits, the Kiro card now shows the overage credit count and estimated USD cost as an inline orange badge."),
                        String(
                            localized: "Anthropic Admin API on the Claude detail page — Today / 7d / 30d cost summary, top models, and top cost items when an Admin API key is configured on Mac."),
                        String(
                            localized: "Claude Extra usage (spend-limit) card for Enterprise / Team plans — utilization gauge, monthly spend vs limit, and a plan-tier badge."),
                        String(
                            localized: "OpenAI API Dashboard window picker — switch the chart range between 7 / 30 / 90 / 180 / 365 days, clamped to whatever Mac fetched."),
                        String(
                            localized: "OpenCode Go Zen workspace balance — pay-as-you-go USD balance shown below the rolling / weekly / monthly bars."),
                        String(
                            localized: "MiniMax 30-day billing card — Today + 30-day token and USD totals, a 30-day bar chart, and top-3 method / model breakdowns."),
                        String(
                            localized: "Quota notifications now include the triggering account on multi-account providers — e.g. 'Codex · admin@example.com' instead of bare 'Codex'. Honours the Mac Hide-personal-info toggle."),
                        String(
                            localized: "Codex workspace badge — when your active Codex account belongs to an OpenAI workspace, the workspace name shows as a caption under the account email plus a weekly pace arrow (up = ahead of pace, down = under pace)."),
                        String(
                            localized: "Existing Kiro / AWS Bedrock / Moonshot / z.ai / OpenAI API Dashboard / Antigravity multi-account cards from 1.7.0 keep working with no change."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update QuotaKit Mac to 0.27.0 (fork build 65.3 or later) for the full v0.27 surface including the quota account identity push title and Codex workspace badge. iPhone 1.8.0 also remains forward-compatible with Mac 0.26.x and 65.1 / 65.2 — newer tiles just stay hidden / fall back to the older title format until Mac is on 65.3."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.7.0",
            status: "",
            summary: String(
                localized: "Six new dedicated provider cards (Kiro credits, AWS Bedrock cost, Moonshot / Kimi API balance, z.ai hourly chart, OpenAI API Dashboard, Antigravity multi-account) plus two new settings toggles."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "OpenAI Admin API Dashboard on the OpenAI provider page — Today / 7 days / 30 days summary cards, a 30-day spend chart, and top models / top line items lists. Requires Mac 0.26.2 with Admin API access."),
                        String(
                            localized: "Kiro: dedicated credits card with plan tag, primary credit usage progress, and an optional bonus pool with expiry countdown."),
                        String(
                            localized: "AWS Bedrock (NEW): monthly spend + budget card with the active AWS region. Color-coded as approach 75% / 90% of budget."),
                        String(
                            localized: "Moonshot / Kimi API (NEW): clean balance + currency + region card so you can see your top-up at a glance."),
                        String(
                            localized: "z.ai hourly chart: stacked per-model token usage for the last 24 hours, with model legend."),
                        String(
                            localized: "Antigravity multi-account switcher: when more than one Google account is wired on Mac, the iPhone shows the linked list with active-account marker."),
                        String(
                            localized: "Two new Settings toggles — Hide quota-warning markers (only the tick-marks; notifications still fire) and Show provider changelog links (companion section in Settings → About)."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update QuotaKit Mac to 0.26.1 (fork build 63.2 or later). iPhone 1.7.0 is also forward-compatible with Mac 0.25.2 — new cards just stay hidden until Mac is on the new build."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.6.0",
            status: "",
            summary: String(
                localized: "11 new provider cards plus a Claude peak-hours indicator and pre-depletion warning markers on every usage bar."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "11 new providers from QuotaKit Mac v0.24/v0.25 — Windsurf, Codebuff, DeepSeek, Manus, Xiaomi MiMo, Doubao, Command Code, StepFun, Crof, Venice, OpenAI API. Each renders in its own brand color across Usage / Cost / Subscription tabs and on the provider detail page."),
                        String(
                            localized: "Push notifications expanded to cover the 11 new providers — your iPhone now pings on their quota events the same way it does for the existing 27."),
                        String(
                            localized: "Claude peak-hours indicator on the Claude detail page — quick glance at whether you're inside Anthropic's published 8am-2pm ET peak window or how long until the next one starts."),
                        String(
                            localized: "Quota warning markers on every usage bar — tick marks at the thresholds you set on Mac (default 50% / 20% remaining) and a warning icon when you cross the most critical one. Per-provider customization on Mac flows through transparently."),
                        String(
                            localized: "Push notification when you cross a warning threshold (not just at full depletion) — your iPhone now buzzes the moment you hit 50%, 20%, or whatever you've configured."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update QuotaKit Mac to 0.25.2 or later for the warning push. New providers work from 0.25.1."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.5.3",
            status: "",
            summary: String(
                localized: "Multi-account display fix on Cost and Subscription Utilization, plus a new cross-version account-link prompt with the related crash fix."),
            sections: [
                .init(
                    title: String(localized: "Recent updates"),
                    items: [
                        String(
                            localized: "Abacus AI and Mistral support — monthly usage and renewal countdown sync to your iPhone, with quota push notifications."),
                        String(
                            localized: "Claude Designs / Daily Routines / Web Sonnet usage bars on the Claude detail page; Cursor Extra budget gauge on the Cursor page."),
                        String(
                            localized: "Synthetic 5h / weekly tokens / search hourly labels render correctly instead of generic fallbacks."),
                        String(
                            localized: "Codex Pro $100 plan badge; estimated cost for newly-released models marked with *."),
                        String(
                            localized: "Two Macs on different QuotaKit versions during a rolling upgrade now show a single card per account."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(localized: "Requires QuotaKit for Mac 0.23.4 or later for the new providers."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.5.2",
            status: "",
            summary: String(
                localized: "Primarily resolves multiple Codex accounts failing to display fully on iPhone. After configuring multiple Codex accounts on Mac, iPhone now shows each account as a separate card; Cost, Usage, and Provider Share all attribute correctly per account."),
            sections: [
                .init(
                    title: String(localized: "Stability"),
                    items: [
                        String(
                            localized: "Added a real-data regression test suite covering all 27 providers to ensure sync stability across multi-account and multi-device scenarios."),
                    ]),
                .init(
                    title: String(localized: "Other fixes"),
                    items: [
                        String(
                            localized: "Some accounts (Claude / Ollama / Copilot etc.) being incorrectly hidden in specific scenarios."),
                        String(
                            localized: "Stale sync records left behind by previous Mac sessions persisting on iPhone."),
                        String(localized: "Cards being merged or lost in multi-account scenarios."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(localized: "Update QuotaKit Mac to 0.23.6 for these changes to take effect."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.5.1",
            status: "",
            summary: String(
                localized: "Upstream v0.21–0.23 provider alignment — Abacus AI + Mistral as new providers, Claude Designs / Daily Routines / Web Sonnet bars, Cursor Extra usage, Synthetic 5h-weekly-search lanes. Requires updated Mac app."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(
                            localized: "QuotaKit is now distributed by Columbus Labs. Use the Mac setup page for current downloads and setup instructions: columbus-labs.com/quotakit/mac."),
                        String(
                            localized: "Open the QuotaKit Mac setup page to install the current Mac build for new providers and accurate Cost numbers: columbus-labs.com/quotakit/mac."),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Abacus AI support — when you enable Abacus on Mac 0.23+, your iPhone shows the monthly compute-credit usage with billing-cycle countdown. Quota depleted / restored push notifications work like the other 25 providers."),
                        String(
                            localized: "Mistral support — monthly spend and renewal date sync to your iPhone. Push notifications fire on quota events."),
                        String(
                            localized: "Claude extras — Designs, Daily Routines, and Web Sonnet usage bars now appear on the Claude detail page when your account exposes those quotas via OAuth or the Web app."),
                        String(
                            localized: "Cursor Extra usage — on-demand budget gauge from Cursor's menu bar metric is now visible on the Cursor detail page when the budget is enabled."),
                        String(
                            localized: "Synthetic 3-lane labels — five-hour quota, weekly tokens, and search hourly are labeled correctly on the detail page instead of generic Session / Weekly fallback labels."),
                        String(
                            localized: "Codex Pro $100 plan badge — the new Pro $100 / prolite plan names from upstream v0.21 sync through and display in the account-info capsule on each Codex card."),
                        String(
                            localized: "Color palette extended — Abacus uses a warm brown tone, Mistral a vibrant red. Both stay distinct from existing provider colors across cards, charts, and the share image."),
                        String(
                            localized: "Estimated cost for newly-released models — when Mac sees a model name that isn't in its pricing table yet, it uses the closest known model's rate as a temporary estimate and marks the value with * on the Provider Detail cost card. Stops Daily Spend from quietly dropping to $0 the day a fresh model name appears."),
                        String(
                            localized: "Two Macs, one card — when your two Macs are on different QuotaKit versions during a rolling upgrade, your iPhone now correctly shows a single card per account rather than duplicates. Works for accounts whose email contains non-ASCII characters (café@…) too."),
                    ]),
                .init(
                    title: String(localized: "Under the hood"),
                    items: [
                        String(
                            localized: "Mac-side ghost-records cleanup — when you disable a provider on Mac or your Codex account identity changes after a Mac upgrade, the old CloudKit record is now actively deleted at the source. Combines with the iOS 1.3.1 display-time filter for double protection against stale cards."),
                        String(
                            localized: "27 providers / 54 push-subscription zones — the push-notification subscription set automatically expands on first launch to cover Abacus AI and Mistral alongside the existing 25 providers."),
                        String(
                            localized: "Wire-format unchanged — iOS 1.3.x users on the same iCloud account see the new providers as fallback cards (color-tinted) without crashing or missing data; existing 25 providers stay fully functional. iOS 1.5.0 adds the structured rendering for the new ones."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.5.0",
            status: "",
            summary: String(
                localized: "Upstream v0.21–0.23 provider alignment — Abacus AI + Mistral as new providers, Claude Designs / Daily Routines / Web Sonnet bars, Cursor Extra usage, Synthetic 5h-weekly-search lanes. Requires updated Mac app."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(
                            localized: "Open the QuotaKit Mac setup page to install the current Mac build for new providers and accurate Cost numbers: columbus-labs.com/quotakit/mac."),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Abacus AI support — when you enable Abacus on Mac 0.23+, your iPhone shows the monthly compute-credit usage with billing-cycle countdown. Quota depleted / restored push notifications work like the other 25 providers."),
                        String(
                            localized: "Mistral support — monthly spend and renewal date sync to your iPhone. Push notifications fire on quota events."),
                        String(
                            localized: "Claude extras — Designs, Daily Routines, and Web Sonnet usage bars now appear on the Claude detail page when your account exposes those quotas via OAuth or the Web app."),
                        String(
                            localized: "Cursor Extra usage — on-demand budget gauge from Cursor's menu bar metric is now visible on the Cursor detail page when the budget is enabled."),
                        String(
                            localized: "Synthetic 3-lane labels — five-hour quota, weekly tokens, and search hourly are labeled correctly on the detail page instead of generic Session / Weekly fallback labels."),
                        String(
                            localized: "Codex Pro $100 plan badge — the new Pro $100 / prolite plan names from upstream v0.21 sync through and display in the account-info capsule on each Codex card."),
                        String(
                            localized: "Color palette extended — Abacus uses a warm brown tone, Mistral a vibrant red. Both stay distinct from existing provider colors across cards, charts, and the share image."),
                        String(
                            localized: "Estimated cost for newly-released models — when Mac sees a model name that isn't in its pricing table yet, it uses the closest known model's rate as a temporary estimate and marks the value with * on the Provider Detail cost card. Stops Daily Spend from quietly dropping to $0 the day a fresh model name appears."),
                        String(
                            localized: "Two Macs, one card — when your two Macs are on different QuotaKit versions during a rolling upgrade, your iPhone now correctly shows a single card per account rather than duplicates. Works for accounts whose email contains non-ASCII characters (café@…) too."),
                    ]),
                .init(
                    title: String(localized: "Under the hood"),
                    items: [
                        String(
                            localized: "Mac-side ghost-records cleanup — when you disable a provider on Mac or your Codex account identity changes after a Mac upgrade, the old CloudKit record is now actively deleted at the source. Combines with the iOS 1.3.1 display-time filter for double protection against stale cards."),
                        String(
                            localized: "27 providers / 54 push-subscription zones — the push-notification subscription set automatically expands on first launch to cover Abacus AI and Mistral alongside the existing 25 providers."),
                        String(
                            localized: "Wire-format unchanged — iOS 1.3.x users on the same iCloud account see the new providers as fallback cards (color-tinted) without crashing or missing data; existing 25 providers stay fully functional. iOS 1.5.0 adds the structured rendering for the new ones."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.3.0",
            status: "",
            summary: String(
                localized: "Upstream v0.20 provider alignment — Perplexity + OpenCode Go, Codex multi-account cards, SwiftData-backed local cache. Requires updated Mac app."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(
                            localized: "Open the QuotaKit Mac setup page to install the current Mac build for Perplexity credit breakdowns and other synced provider improvements: columbus-labs.com/quotakit/mac."),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Perplexity credit breakdown — when Mac 0.20.3+ is installed, the Perplexity detail page shows a stacked 3-segment bar for monthly / bonus / purchased credits, a Pro/Max plan badge, and a renewal-date countdown."),
                        String(
                            localized: "OpenCode Go support — separate provider from OpenCode Zen with its own tint (mint) and push subscriptions; cards are visually distinguishable at a glance even with both products enabled."),
                        String(
                            localized: "Codex multi-account cards — if you have 2+ Codex accounts (e.g. a personal Pro and a work Business account), each now renders as its own card with the email as the subtitle. Accounts without an email get a localized ordinal fallback (\"Codex 2\", etc.)."),
                        String(
                            localized: "Full push-notification coverage — quota depleted / restored pushes now work for Perplexity and OpenCode Go in addition to the 23 existing providers."),
                        String(
                            localized: "Provider color palette consolidated — every tab and card uses the same color for a given provider, so the Subscription Utilization chart, the provider list, the share card, and the detail page all agree."),
                    ]),
                .init(
                    title: String(localized: "Under the hood"),
                    items: [
                        String(
                            localized: "SwiftData-backed local cache — cold start time for Usage / Cost tabs reduced from 2-5 seconds to under 200 ms. Data persists across app relaunches instead of re-fetching from CloudKit every time."),
                        String(
                            localized: "Per-provider CloudKit records with zlib compression — removes the 1 MB-per-record hard cap that long-term users were approaching as their utilization history grew."),
                        String(
                            localized: "Push-driven incremental sync — Mac changes now land on iPhone within ~500 ms via CloudKit silent pushes instead of waiting for the next manual refresh."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.2.0",
            status: "",
            summary: String(localized: "Subscription Utilization, multi-Mac sync, and push notifications from Mac."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(
                            localized: "Open the QuotaKit Mac setup page to install the current Mac build. Subscription Utilization and Mac-to-iPhone push notifications depend on the paired Mac app: columbus-labs.com/quotakit/mac."),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Subscription Utilization visualization — see how much of each session / weekly / opus quota you're using, per provider and across all providers. 30-day daily bar chart in the Cost tab with Today / This Week / 14 Days / 30 Days summary cards, plus a utilization history chart on every provider detail page."),
                        String(
                            localized: "Multi-Mac data merge — if you run QuotaKit on more than one Mac, data from all of them is deduped by hour and combined on iPhone, so your iPhone charts stay consistent regardless of which Mac was last active."),
                        String(
                            localized: "Push notifications from Mac — when a session quota hits 0% or becomes available again on any of your Macs, your iPhone receives a notification that includes the provider name. Background App Refresh does not need to be enabled."),
                    ]),
                .init(
                    title: String(localized: "Improvements"),
                    items: [
                        String(
                            localized: "Settings and Developer Tools streamlined — Setup Guide promoted to the top of Settings; Push Diagnostic tool added under Developer Tools to inspect the Mac→iOS push chain; redundant How It Works sections removed."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.1.0",
            status: "",
            summary: String(localized: "Multi-device CloudKit sync. Requires updated Mac app."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(
                            localized: "Open the QuotaKit Mac setup page to install the current Mac build and unlock CloudKit sync: columbus-labs.com/quotakit/mac"),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "CloudKit multi-device sync — data from multiple Macs is now merged on iPhone instead of last-write-wins."),
                        String(
                            localized: "New Sync Detail page in Settings — view sync status, connected devices, and detailed error info."),
                        String(
                            localized: "Raw Sync Data inspector — per-device unmerged data with daily cost breakdowns for debugging."),
                        String(
                            localized: "Specific CloudKit error messages — network, auth, quota issues now show exact cause instead of generic errors."),
                    ]),
                .init(
                    title: String(localized: "Improvements"),
                    items: [
                        String(localized: "Tab bar no longer hides when scrolling."),
                        String(localized: "Simplified sync status bar at the bottom of Usage and Cost tabs."),
                        String(localized: "Legacy KVS sync maintained as fallback for older Mac app versions."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.0.0 (21)",
            status: "",
            summary: String(localized: "The first App Store release. Works with QuotaKit on Mac."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Share your AI spending as a beautiful image card — choose Classic or Vibe style, supports Today, 7 Days, and 30 Days, and adapts to dark mode."),
                        String(localized: "Usage percentages now stay crisp without blur on provider cards."),
                        String(localized: "Cost summaries and breakdown amounts remain sharp in tighter layouts."),
                        String(localized: "View AI coding tool usage on iPhone, synced from Mac via iCloud."),
                        String(
                            localized: "Provider cards with real-time rate limits, budget progress, and daily cost breakdowns."),
                        String(
                            localized: "Cost dashboard with provider share, model and service mix, and 30-day spend analysis."),
                        String(
                            localized: "Interactive charts with Bar and Line styles, press-and-hold inspection, and horizontal scrolling for history."),
                        String(localized: "Supports English, Simplified Chinese, Traditional Chinese, and Japanese."),
                        String(localized: "Liquid Glass design, demo mode, onboarding guide, and pull-to-refresh."),
                    ]),
                .init(
                    title: String(localized: "Improvements & Fixes"),
                    items: [
                        String(localized: "Percentage and cost labels are now sharper and easier to read."),
                        String(localized: "Toggle between used and remaining quota display in Settings."),
                        String(localized: "Smarter chart axis scaling with clean integer tick marks."),
                        String(localized: "Improved iCloud sync reliability and error reporting."),
                    ]),
            ]),
    ]
}
