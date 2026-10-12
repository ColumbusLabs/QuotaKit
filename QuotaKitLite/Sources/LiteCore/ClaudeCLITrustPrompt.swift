import Foundation

/// Claude Code's "Quick safety check" folder-trust prompt, as it appears on the first run in Lite's folder:
/// "❯ No, exit" above "Yes, I trust this folder", Enter to confirm.
public enum ClaudeCLITrustPrompt {
    /// CSI and OSC sequences and charset switches. The pattern is a constant, so it always compiles.
    private static let escapeSequence = try? NSRegularExpression(
        pattern: "\u{1b}(\\[[0-9;?]*[ -/]*[@-~]|\\][^\u{7}]*\u{7}|[()][A-Za-z0-9])")

    /// The keys that choose "Yes, I trust this folder", or nil when the prompt isn't on screen. Only ever sent from
    /// the app's `ClaudeCLIRefresher`, whose working directory is Lite's own empty folder.
    public static func keys(forScreen screen: Data) -> String? {
        // Spaces arrive as cursor moves, so drop escape sequences before matching words.
        // A read can end mid-character; Latin-1 always decodes and the words matched are ASCII.
        let raw = String(bytes: screen, encoding: .utf8) ?? String(bytes: screen, encoding: .isoLatin1) ?? ""
        let stripped = self.escapeSequence?.stringByReplacingMatches(
            in: raw,
            range: NSRange(raw.startIndex..., in: raw),
            withTemplate: "") ?? raw
        let text = stripped.lowercased().filter { !$0.isWhitespace }
        guard let yes = text.range(of: "yes,itrustthisfolder", options: .backwards) else { return nil }
        // The highlighted default is "No, exit"; one Down moves to "Yes" when it is listed first.
        if let no = text.range(of: "no,exit", options: .backwards), no.lowerBound < yes.lowerBound {
            return "\u{1b}[B\r"
        }
        return "\r"
    }
}
