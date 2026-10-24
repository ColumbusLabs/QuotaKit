---
summary: "Chatbox AI license usage and credit pools."
provider_id: chatbox
provider_name: Chatbox AI
provider_source: License key for plan and credit usage.
plugin_scope: Read-only license detail endpoint.
read_when:
  - Setting up or modifying the Chatbox AI provider
---

# Chatbox AI

Enable **Chatbox AI** in Settings → Providers and enter the license key, or set `CHATBOX_LICENSE_KEY` for the CLI.
The key is stored in QuotaKit's local config when entered in Settings. The plugin sends a read-only request to
`https://api.chatboxai.app/api/license/detail/realtime`; it does not read browser cookies or modify the account.

The response can include plan token usage, the unified quota, reward credits, expansion-pack credits, and image
generation quota. Each pool is displayed separately. Expired reward pools are excluded when their expiry is known;
top-up and image pools do not inherit the plan's reset schedule. The plan window is shown only when the license is
active and unexpired and has a positive limit with a valid future refresh time. Unknown or malformed required
counters fail the refresh instead of being shown as zero.

The iPhone projection carries the plan meter when available and the remaining-credit rows. It does not create quota
alerts from purchased pools or claim that their balance resets with the plan.
