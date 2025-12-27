import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct CopilotLoginFlow {
    static func run(settings: SettingsStore) async {
        let flow = CopilotDeviceFlow()

        do {
            let code = try await flow.requestDeviceCode()

            // Copy code to clipboard
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(code.userCode, forType: .string)

            let alert = NSAlert()
            alert.messageText = "GitHub Copilot Login"
            alert.informativeText = """
            A device code has been copied to your clipboard: \(code.userCode)

            Please verify it at: \(code.verificationUri)
            """
            alert.addButton(withTitle: "Open Browser")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                return // Cancelled
            }

            if let url = URL(string: code.verificationUri) {
                NSWorkspace.shared.open(url)
            }

            // Poll in background (modal blocks, but we need to wait for token effectively)
            // Ideally we'd show a "Waiting..." modal or spinner.
            // For simplicity, we can use a non-modal window or just block a Task?
            // `runModal` blocks the thread. We need to poll while the user is doing auth in browser.
            // But we already returned from runModal to open the browser.
            // We need a secondary "Waiting for confirmation..." alert or state.

            // Let's show a "Waiting" alert that can be cancelled
            let waitingAlert = NSAlert()
            waitingAlert.messageText = "Waiting for Authentication..."
            waitingAlert.informativeText = """
            Please complete the login in your browser.
            This window will close automatically when finished.
            """
            waitingAlert.addButton(withTitle: "Cancel")

            // Show the modal. If user clicks Cancel, we cancel the task.
            // We need a way to close the modal programmatically when task finishes.
            // NSAlert doesn't support programmatic closing easily in runModal.
            // We'll use a custom window or just hope the user waits?
            // Actually, we can use `beginSheetModal` but we are not attached to a window necessarily.

            // Hack: Poll loop checks `tokenTask` status? No.
            // Better: Just loop polling here (blocking) but that freezes UI?
            // No, `await` doesn't freeze UI if on MainActor? `alert.runModal` DOES freeze UI loop.

            // Alternative: Don't use a second modal. Just set status in Settings?
            // But we want to confirm success.

            // Let's try:
            // 1. Alert 1: "Copy Code & Open Browser". Buttons: "Open & Wait", "Cancel".
            // 2. If "Open & Wait": Launch browser, then show Alert 2: "Waiting... [Cancel]".
            // 3. Background task polls. If success, it uses `NSApp.abortModal` to close Alert 2?

            // Implementing `abortModal` logic:

            var completion: Result<String, Error>?
            let tokenTask = Task {
                try await flow.pollForToken(deviceCode: code.deviceCode, interval: code.interval)
            }

            Task {
                do {
                    let token = try await tokenTask.value
                    await MainActor.run {
                        completion = .success(token)
                        NSApp.stopModal()
                        waitingAlert.window.close()
                    }
                } catch {
                    await MainActor.run {
                        guard !(error is CancellationError) else { return }
                        completion = .failure(error)
                        NSApp.stopModal()
                        waitingAlert.window.close()
                    }
                }
            }

            let waitResponse = waitingAlert.runModal()
            if completion == nil, waitResponse == .alertFirstButtonReturn { // Cancel button (it's the only one)
                tokenTask.cancel()
            }
            if let completion {
                switch completion {
                case let .success(token):
                    settings.copilotAPIToken = token
                    settings.setProviderEnabled(
                        provider: .copilot,
                        metadata: ProviderRegistry.shared.metadata[.copilot]!,
                        enabled: true)

                    let success = NSAlert()
                    success.messageText = "Login Successful"
                    success.runModal()
                case let .failure(error):
                    let err = NSAlert()
                    err.messageText = "Login Failed"
                    err.informativeText = error.localizedDescription
                    err.runModal()
                }
            }

        } catch {
            let err = NSAlert()
            err.messageText = "Login Failed"
            err.informativeText = error.localizedDescription
            err.runModal()
        }
    }
}
