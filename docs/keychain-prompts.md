---
summary: "Why macOS Keychain prompts appear, how CodexBar limits them, and safe troubleshooting."
read_when:
  - Investigating Chrome Safe Storage or browser Safe Storage prompts
  - Explaining prompts that appear after uninstalling QuotaKit
  - Collecting safe support details without exposing secrets
---

# Keychain prompts

QuotaKit can trigger macOS Keychain prompts when an enabled provider imports browser cookies, reads a provider-owned
OAuth item, or uses a QuotaKit-owned cache entry. Chromium browser cookie import commonly asks for the browser's
Safe Storage item, such as "Chrome Safe Storage", "Brave Safe Storage", or "Microsoft Edge Safe Storage".

QuotaKit does not need your browser password. macOS owns the prompt, and the prompt should identify the app or binary
that is requesting access. For support reports, include that requesting app/path when possible and do not paste
passwords, cookie headers, OAuth tokens, API keys, or Keychain item values.

Before a Keychain read that may require interaction, QuotaKit shows an explanation of the item and its purpose.
**Learn More** opens this page without dismissing that explanation or starting the macOS prompt. Choose **OK** only
when you are ready to continue, or use the opt-out below.

After you acknowledge the Claude OAuth explanation, QuotaKit does not repeat that explanation for six hours. This
cooldown only applies to QuotaKit's explanatory alert: macOS can still show its own Keychain authorization prompt,
and the Claude **Never prompt** and global **Disable Keychain access** settings remain in effect.

## If the prompt appears after uninstalling QuotaKit

Deleting `QuotaKit.app` prevents a new process from launching from that bundle, but it does not terminate a process
that is already running from it. That process can continue to request Keychain access until it quits. If macOS still
shows a prompt such as "QuotaKit wants to use your confidential information stored in 'Chrome Safe Storage'", the
usual causes are:

- A QuotaKit process or bundled helper is still running.
- QuotaKit is still enabled in Login Items and relaunched from an existing install.
- Another copy of `QuotaKit.app` exists elsewhere on the machine.
- The uninstall path did not remove the same copy that launched the process. Finder, Homebrew cask, Sparkle updates,
  and manually copied apps can leave different install paths in play.
- The prompt is naming the requesting binary, not proving that the copy you deleted is the one still running.

Keychain access control evaluates the requesting executable's code signature and designated requirement, not just its
filename or install path. A stable, properly signed CodexBar bundle makes grants more durable, while ad-hoc development
builds or a materially changed identity may need authorization again. The Keychain item's owner can also recreate or
rotate a foreign item. Chromium or Claude Code updates can therefore replace the previous access-control entry even
when CodexBar itself has not changed.

The item's accessibility class controls when its data is available, such as after the first unlock. It does not grant
a changed executable access and does not repair a code-signature ACL mismatch.

## Allow Once and Always Allow

- **Allow Once** authorizes the current request or session. A later explicit import or repair may ask again.
- **Always Allow** adds the current CodexBar identity to that item's access control and is the better choice when you
  intentionally use automatic browser import or Claude's direct Keychain repair.
- **Deny** leaves the source unavailable. CodexBar should fail soft and use another configured source where possible.

Only authorize a prompt whose requested item and requesting app match the action you just started. Avoid “Allow all
applications.” In Keychain Access, adding only the installed, stably signed `CodexBar.app` is the narrower grant.

## Disable CodexBar Keychain access

Open **CodexBar → Settings → Advanced** and enable **Disable Keychain access**. The stored setting is applied
immediately; relaunching is useful when diagnosing another already-running copy.

This setting blocks CodexBar-owned Security.framework item reads and writes, including foreign-item readers such as
Zed, and disables Chromium Safe Storage decryption. Browser-cookie import that needs Keychain is skipped. It does not
promise that a provider-owned CLI launched by CodexBar will avoid its own credential store; Claude's owner-CLI policy
is intentionally unchanged.

Alternatives depend on the provider:

- Paste a Cookie header manually instead of importing it from a browser.
- Configure an API key or OAuth/device flow that does not depend on browser Safe Storage.
- Use a supported file-backed or local provider source.
- For Claude, leave direct foreign-item consent off and choose a CLI, Web, or usable credentials-file path.

## Safe troubleshooting

If a prompt appears unexpectedly, first read the full item name and requesting app/path. Quit CodexBar, then check for
another running or installed copy:

```bash
pgrep -fl 'QuotaKit|QuotaKitCLI'
ls -ld /Applications/QuotaKit.app
brew info --cask quotakit
mdfind 'kMDItemCFBundleIdentifier == "com.columbuslabs.quotakit.mac"'
```

Also inspect **Activity Monitor** and **System Settings → General → Login Items**. Deleting an app does not terminate
an already-running process, and another copy may have launched from a different path. Do not use command-line tools to
dump Keychain contents while troubleshooting.

- **Activity Monitor**: search for `QuotaKit` and `QuotaKitCLI`.
- **System Settings -> General -> Login Items**: remove QuotaKit if it remains listed.
- **Keychain prompt screenshot**: capture the full prompt, especially any requesting app/path details. Redact user
  names or unrelated window contents if needed, but do not include secrets.

If you find a still-running process, quit QuotaKit from the menu if possible, or quit it from Activity Monitor. If you
find another installed copy, confirm whether that copy is the one macOS names in the prompt before changing anything
else.

## Stop QuotaKit from using Keychain

If QuotaKit is still installed and you want it to stop all Keychain access:

1. Open **QuotaKit -> Settings -> Advanced**.
2. In **Keychain access**, enable **Disable Keychain access**.
3. Relaunch QuotaKit.

This disables Keychain reads and writes from QuotaKit. Browser-cookie-based providers will be skipped because
QuotaKit can no longer decrypt browser cookies. Manual cookie headers, API keys, and CLI/OAuth flows that do not rely
on Keychain can still work where the provider supports them.

## Browser Safe Storage prompts

If a Chromium-family Safe Storage check requires interaction or is denied, QuotaKit pauses automatic cookie imports
for every Chromium-family browser for six hours. This prevents a denial in Arc, Edge, Brave, or another Chromium
browser from immediately moving to the next browser and showing another prompt. **Refresh Now** is an explicit retry
for the browser that was blocked; Safari and Firefox-family cookie imports remain available during the pause.

For normal browser-cookie import prompts, either allow QuotaKit in the Keychain item's Access Control list or disable
Keychain access:

1. Open **Keychain Access.app**.
2. Select the `login` keychain.
3. Search for the item named in the prompt, for example `Chrome Safe Storage`.
4. Open the item, choose **Access Control**, and add `QuotaKit.app` under "Always allow access by these applications".
5. Relaunch QuotaKit.

Avoid "Allow all applications" unless you intentionally want every app to access that item. Do not paste or share the
item's secret value when asking for help.

## What to include in a support issue

- QuotaKit version and install source: GitHub release, Homebrew cask, Sparkle update, or another source.
- macOS version.
- The uninstall method if this happened after uninstalling.
- Whether Activity Monitor or `pgrep` still shows QuotaKit.
- Whether System Settings -> General -> Login Items still lists QuotaKit.
- Whether `/Applications/QuotaKit.app`, Homebrew cask metadata, or Spotlight finds another copy.
- A screenshot of the Keychain prompt showing the requested item and requesting app/path, with secrets redacted.
