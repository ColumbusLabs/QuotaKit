# QuotaKit Product Spec

QuotaKit tracks AI quota, usage, and spend on Mac, then syncs that data to iPhone through iCloud.

## Product Boundary

- Product: QuotaKit
- Company: Columbus Labs
- Setup page: `https://columbus-labs.com/quotakit/mac`
- Repository: `https://github.com/ColumbusLabs/QuotaKit`

## Core Experience

1. The Mac app gathers provider usage locally.
2. The Mac app syncs quota snapshots through the user's private iCloud account.
3. The iPhone app displays synced quota, cost, provider status, alerts, share cards, and widgets.
4. QuotaKit Pro unlocks the full usage/cost surface and widgets.

## Public Copy Rules

- Use QuotaKit for product copy.
- Use Columbus Labs for company copy.
- Keep upstream names only in explicit credits, provenance, or inherited implementation notes.
- Installation flows should point to `https://columbus-labs.com/quotakit/mac`.

## Privacy Position

QuotaKit is local-first. Provider credentials and local usage sources are read only for enabled providers. Synced usage data stays in the user's iCloud account.
