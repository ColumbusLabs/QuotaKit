# Agent Sessions

QuotaKit can list live Codex, Claude Code, pi, and OMP sessions on this Mac and other Macs or Linux hosts reachable over SSH.

Enable **Settings → Menu → Agent sessions**. Local sessions refresh every 30 seconds. Remote sessions refresh every 60 seconds and whenever the menu opens. Tailscale discovery includes online macOS and Linux peers; add extra SSH destinations as a comma-separated list, such as `user@host`.

Choose the row label format in the same settings section:

- **Project** keeps the working-directory name used by earlier releases.
- **Descriptive** uses the Codex thread title, pi/OMP session name when available, or named subagent task, with the project as a fallback.
- **Descriptive + project** shows both when they differ.

Thread and session titles can contain sensitive text. **Project** remains the default; choose a descriptive mode only if you are comfortable showing those titles in the menu. QuotaKit reads only bounded title metadata, limits labels to 64 Unicode scalars, does not modify provider state, and does not persist titles separately.

Claude Code sessions currently fall back to the project name because Claude does not expose equivalent session-title metadata. Pi-family rows show their `pi` or `omp` dialect tag, and never create file-only rows without a live process.

The menu groups local sessions first, followed by each remote host. A filled dot is active; an empty dot is idle. Select a local row to activate its terminal, editor, or desktop app. The first focus attempt can request macOS Accessibility permission so QuotaKit can raise the matching window. Remote rows run the same focus command over SSH.

The CLI exposes the same scanner:

```console
quotakit sessions
quotakit sessions --json
quotakit sessions --json-v2
quotakit sessions focus <session-id>
```

`--json` preserves the legacy v1 array restricted to Codex and Claude. `--json-v2` includes Pi-family rows and their dialect. Remote fetching negotiates v2 first and falls back to v1 for mixed-version hosts.

Remote hosts need key-based, non-interactive SSH and either `quotakit` on `PATH` or QuotaKit installed in `/Applications`.
