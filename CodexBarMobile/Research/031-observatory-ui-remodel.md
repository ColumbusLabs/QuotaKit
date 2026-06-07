# 031 — Observatory UI Remodel

**Status:** done  
**Branch:** `ui/observatory`

## Direction

Dark-first "Observatory" design: mission-control aesthetic for AI quota and spend tracking. Solid themed surfaces replace blanket `.ultraThinMaterial` cards.

## Design tokens

| Token | Dark | Light |
|-------|------|-------|
| canvas | `#0B0D12` | `#F4F5F7` |
| surface | `#141820` | `#FFFFFF` |
| surfaceElevated | `#1C2230` | `#FAFAFA` |
| border | white 6% | black 8% |
| textPrimary | `#F0F2F5` | `#111111` |
| textMuted | `#8B92A0` | `#6B7280` |
| accent | `#5B8CFF` | `#3B6FE8` |
| spendWarm | orange family | brighter orange |
| chartPlot | `#0F1218` | `#ECEEF2` |

## New components (`CodexBarMobile/Design/`)

- `QuotaKitTheme.swift` — tokens + environment
- `QKSurfaceCard.swift` — replaces material cards
- `QKSectionHeader.swift` — section labels
- `QKStatusChip.swift` — demo/sync/mock chips
- `UsageRingGauge.swift` — primary quota ring
- `QKMetricDisplay.swift` — monospaced hero numbers
- `CostHeroStrip.swift` — Cost tab hero

## Migration checklist

- [x] Theme + appearance preference
- [x] Shared primitives
- [x] Usage tab (ring + bars, status chips)
- [x] Cost tab (hero strip, chart, breakdown rows)
- [x] Settings (panel cards)
- [x] ProviderDetailView + specialty cards
- [x] Nav chrome + empty states + onboarding
- [x] Tests + CHANGELOG (localization keys follow standard xcstrings workflow)

## Deferred

- Home screen widgets (`QuotaKitWidgetViews.swift`)
- Share card exports (`CostShareCardView`, `CyberShareCardView`)
