import AppKit
import Testing
@testable import CodexBar

struct StatusItemHostingDiagnosticsTests {
    @Test
    func `hosting trace filters unrelated windows and redacts names`() throws {
        let records = [
            self.window(number: 1),
            self.window(number: 2, owner: "Control Centre"),
            self.window(number: 3, owner: "Other App"),
            self.window(number: 4, layer: 0),
            self.window(number: 5, name: "private window title"),
        ]
        let diagnostic = MenuBarStatusItemWindowProbe.hostingDiagnostics(
            name: "quotakit-merged",
            windowInfo: records)

        #expect(diagnostic["layer25Count"] as? Int == 3)
        #expect(diagnostic["layer25Numbers"] as? [Int] == [1, 2, 5])
        let matches = try #require(diagnostic["namedMatches"] as? [[String: Any]])
        #expect(matches.compactMap { $0["number"] as? Int } == [1, 2])
        #expect(matches.first?["onscreen"] as? Bool == true)
        let data = try JSONSerialization.data(withJSONObject: diagnostic)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("private window title"))
        #expect(!json.contains("quotakit-merged"))
    }

    @Test
    func `redacted Control Center windows remain counted without a named match`() {
        var redacted = self.window(number: 1)
        redacted.removeValue(forKey: kCGWindowName as String)

        for name in ["", "private autosave name"] {
            let diagnostic = MenuBarStatusItemWindowProbe.hostingDiagnostics(name: name, windowInfo: [redacted])
            #expect(diagnostic["layer25Count"] as? Int == 1)
            #expect(diagnostic["unnamedCount"] as? Int == 1)
            #expect((diagnostic["namedMatches"] as? [[String: Any]])?.isEmpty == true)
        }
    }

    @Test
    func `status item trace fields omit autosave identity and evidence description`() throws {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: false,
            isOnCurrentScreen: false,
            buttonWidth: 32)
        let evidence = StatusItemStartupVisibilityEvidence(
            autosaveName: "private-account-autosave-name",
            expectsVisibility: true,
            visibilityDefault: true,
            snapshot: snapshot)
        let fields = MenuBarStatusItemWindowProbe.statusItemDiagnostics(
            itemPresent: true,
            snapshot: evidence.snapshot,
            expectsVisibility: evidence.expectsVisibility,
            visibilityDefault: evidence.visibilityDefault)
        let data = try JSONSerialization.data(withJSONObject: fields)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect((fields["visible"] as? Bool) == true)
        #expect((fields["hasScreen"] as? Bool) == false)
        #expect((fields["buttonWidth"] as? Double) == 32)
        #expect(!json.contains("private-account-autosave-name"))
        #expect(!json.contains(evidence.description))
    }

    @Test
    func `diagnostics require explicit environment opt in`() {
        #expect(!MenuBarStatusItemWindowProbe.isDiagnosticsEnabled(environment: [:]))
        #expect(!MenuBarStatusItemWindowProbe.isDiagnosticsEnabled(
            environment: ["CODEXBAR_STATUS_ITEM_DIAGNOSTICS": "true"]))
        #expect(MenuBarStatusItemWindowProbe.isDiagnosticsEnabled(
            environment: ["CODEXBAR_STATUS_ITEM_DIAGNOSTICS": "1"]))
    }

    @Test
    func `diagnostic event budget stops at 128`() {
        var budget = MenuBarStatusItemDiagnosticBudget()
        for sequence in 1...128 {
            #expect(budget.nextSequence() == sequence)
        }
        #expect(budget.nextSequence() == nil)
        #expect(budget.emittedEvents == 128)
    }

    @Test
    func `missing window records alone do not change startup recovery`() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 32)
        let evidence = StatusItemStartupVisibilityEvidence(
            autosaveName: "quotakit-merged",
            expectsVisibility: true,
            visibilityDefault: true,
            snapshot: snapshot)

        #expect(!MenuBarVisibilityWatcher.hasAnyStartupRecoveryCandidate(
            snapshots: [snapshot],
            evidence: [evidence],
            windowSnapshots: [],
            detectTahoeBlockedStatusItem: true))
    }

    private func window(
        number: Int,
        owner: String = "Control Center",
        layer: Int = 25,
        name: String = "quotakit-merged") -> [String: Any]
    {
        [
            kCGWindowNumber as String: number,
            kCGWindowOwnerName as String: owner,
            kCGWindowLayer as String: layer,
            kCGWindowName as String: name,
            kCGWindowBounds as String: ["X": 20, "Y": 0, "Width": 32, "Height": 24],
            kCGWindowIsOnscreen as String: true,
        ]
    }
}
