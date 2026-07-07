# Agent Sessions

QuotaKit can list live Codex and Claude Code sessions on this Mac and other Macs or Linux hosts reachable over SSH.

Enable **Settings → General → Sessions**. Local sessions refresh every 30 seconds. Remote sessions refresh every 60 seconds and whenever the menu opens. Tailscale discovery includes online macOS and Linux peers; add extra SSH destinations as a comma-separated list, such as `user@host`.

The menu groups local sessions first, followed by each remote host. A filled dot is active; an empty dot is idle. Select a local row to activate its terminal, editor, or desktop app. The first focus attempt can request macOS Accessibility permission so QuotaKit can raise the matching window. Remote rows run the same focus command over SSH.

The CLI exposes the same scanner:

```console
quotakit sessions
quotakit sessions --json
quotakit sessions focus <session-id>
```

Remote hosts need key-based, non-interactive SSH and either `quotakit` on `PATH` or QuotaKit installed in `/Applications`.
