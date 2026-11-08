---
summary: "ElevenLabs provider notes: API key setup and subscription usage fields."
read_when:
  - Adding or modifying the ElevenLabs provider
  - Debugging ElevenLabs API keys or subscription usage parsing
  - Adjusting ElevenLabs credit or voice-slot labels
---

# ElevenLabs Provider

The ElevenLabs provider reads subscription usage from the ElevenLabs API using an API key.

## Features

- Character credit usage from the current subscription period.
- Reset timing when the API returns `next_character_count_reset_unix`.
- Voice slot and professional voice slot usage when those fields are present.
- Plan/status text from the subscription response.

## Setup

### CLI

Store the API key without opening Settings:

```bash
printf '%s' "$ELEVENLABS_API_KEY" | quotakit config set-api-key --provider elevenlabs --stdin
```

This trims the piped key, writes it to the [resolved QuotaKit config](configuration.md) with restrictive permissions,
and enables ElevenLabs by default. Use `--no-enable` to save the key without enabling the provider.
The key needs `user_read` permission to fetch subscription usage.

The command saves a standalone `apiKey`. It does not replace saved API-key accounts or their selection.
A selected saved account takes priority, followed by the standalone key, `ELEVENLABS_API_KEY`, and `XI_API_KEY`.

`quotakit config providers --json` includes this route in ElevenLabs' static `setup` guidance on macOS and Linux.
It lists the accepted input names and existing stdin command without reading credentials or checking whether
the account is ready.

### Settings

1. Open **Settings -> Providers**
2. Enable **ElevenLabs**
3. Open `https://elevenlabs.io/app/settings/api-keys`
4. Create or copy an API key
5. Paste the key into CodexBar's ElevenLabs provider settings

### Environment Variables

CodexBar also accepts these environment variables:

- `ELEVENLABS_API_KEY`
- `XI_API_KEY`

For tests or self-hosted/proxy setups, override the API base URL with `ELEVENLABS_API_URL`.

## How It Works

- Endpoint: `GET https://api.elevenlabs.io/v1/user/subscription`
- Auth header: `xi-api-key`
- Fields used: `character_count`, `character_limit`, `voice_slots_used`, `voice_limit`, `professional_voice_slots_used`, `professional_voice_limit`, `tier`, `status`, `next_character_count_reset_unix`

## Troubleshooting

### "Missing ElevenLabs API key"

Set the key with `quotakit config set-api-key --provider elevenlabs --stdin`, add it in **Settings -> Providers -> ElevenLabs**, set `ELEVENLABS_API_KEY`, or configure an ElevenLabs token account.

### "ElevenLabs API error"

Confirm the API key is valid and that the current network can reach `api.elevenlabs.io`.
