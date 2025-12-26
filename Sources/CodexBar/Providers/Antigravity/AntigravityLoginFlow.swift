import CodexBarCore

@MainActor
extension StatusItemController {
    func runAntigravityLoginFlow() async {
        self.loginPhase = .idle
        self.presentLoginAlert(
            title: "Antigravity login is managed in the app",
            message: "Open Antigravity to sign in, then refresh CodexBar.")
    }
}
