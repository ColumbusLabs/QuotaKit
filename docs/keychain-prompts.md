---
summary: "Safe troubleshooting for macOS Keychain and browser Safe Storage prompts."
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

Scheduled browser-cookie refresh uses a noninteractive Safe Storage preflight. A current allowed
result can resume background refresh after a prior denial; interactive or failed preflight results
remain blocked, and the user-initiated denial cooldown is preserved.

Concurrent preflights for the same trusted application and executable share an in-flight code-signature validation.
For the running executable (or its own main app bundle), preflight checks the ACL's signing requirement against the
process's dynamic code identity with default Security flags, avoiding sealed-resource hashing. A bundled CLI helper
only validates its own identity; it cannot authorize its enclosing app. Other paths and ACLs without an available
signing requirement keep the static validator. Requirement mismatches remain confirmed rejections; other dynamic
errors stay inconclusive. Completed successful validations and transient failures are not retained across operations;
the existing short, explicit operation memo can reuse preflight only within that operation.

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

Safe checks:

```bash
pgrep -fl 'QuotaKit|QuotaKitCLI'
ls -ld /Applications/QuotaKit.app
brew info --cask quotakit
mdfind 'kMDItemCFBundleIdentifier == "com.columbuslabs.quotakit.mac"'
```

Also check:

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

## Cache ACL and no-UI checks

QuotaKit identifies a bundled CLI through the running executable's kernel path, including launches through a symlink.
An external symlink is not added to the cache item's trusted applications. Unbundled development binaries keep their
cache in memory. Before a background secret read, a no-UI attributes check inspects the current decrypt ACL and code
signature. Inconclusive checks retry up to three times; only a confirmed ACL rejection starts a five-minute cache
cooldown.

When fresh data is available, QuotaKit can replace **its own** stale cache item using no-UI deletion and creation.
Failed replacement is attempted once per cooldown. A locked or inconclusive Keychain remains retryable and is not
replaced. Concurrent signature checks share an in-flight result, but a completed success is revalidated on the next
operation so changes to sealed app resources cannot rely on stale approval.

## What to include in a support issue

- QuotaKit version and install source: GitHub release, Homebrew cask, Sparkle update, or another source.
- macOS version.
- The uninstall method if this happened after uninstalling.
- Whether Activity Monitor or `pgrep` still shows QuotaKit.
- Whether System Settings -> General -> Login Items still lists QuotaKit.
- Whether `/Applications/QuotaKit.app`, Homebrew cask metadata, or Spotlight finds another copy.
- A screenshot of the Keychain prompt showing the requested item and requesting app/path, with secrets redacted.
