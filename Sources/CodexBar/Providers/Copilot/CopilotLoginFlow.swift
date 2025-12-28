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

            // Let's show a "Waiting" alert that can be cancelled.
            let waitingAlert = NSAlert()
            waitingAlert.messageText = "Waiting for Authentication..."
            waitingAlert.informativeText = """
            Please complete the login in your browser.
            This window will close automatically when finished.
            """
            waitingAlert.addButton(withTitle: "Cancel")
            let waitingWindow = waitingAlert.window
            var completion: Result<String, Error>?
            let tokenTask = Task.detached(priority: .userInitiated) {
                try await flow.pollForToken(deviceCode: code.deviceCode, interval: code.interval)
            }

            Task { @MainActor in
                do {
                    let token = try await tokenTask.value
                    completion = .success(token)
                    if NSApp.modalWindow === waitingWindow {
                        NSApp.stopModal(withCode: .OK)
                    }
                    waitingWindow.orderOut(nil)
                } catch {
                    guard !(error is CancellationError) else { return }
                    completion = .failure(error)
                    if NSApp.modalWindow === waitingWindow {
                        NSApp.stopModal(withCode: .abort)
                    }
                    waitingWindow.orderOut(nil)
                }
            }

            if completion == nil {
                let waitResponse = waitingAlert.runModal()
                if completion == nil, waitResponse == .alertFirstButtonReturn {
                    tokenTask.cancel()
                }
            }
            waitingWindow.orderOut(nil)
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
