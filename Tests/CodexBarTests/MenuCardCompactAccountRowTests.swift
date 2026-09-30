import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
private enum CompactAccountResetFixtures {
    static let now = Date(timeIntervalSince1970: 1_782_000_000)

    static func window(
        _ used: Double,
        after seconds: TimeInterval? = nil,
        description: String? = nil,
        synthetic: Bool = false) -> RateWindow
    {
        RateWindow(
            usedPercent: used,
            windowMinutes: 300,
            resetsAt: seconds.map { self.now.addingTimeInterval($0) },
            resetDescription: description,
            isSyntheticPlaceholder: synthetic)
    }

    static func row(
        provider: UsageProvider = .codex,
        primary: RateWindow? = nil,
        weekly: RateWindow? = nil,
        monthly: RateWindow? = nil,
        extras: [NamedRateWindow] = [],
        error: String? = nil,
        usesLastKnownUsage: Bool = false) throws -> AccountMenuLayoutPlanner.CompactRow
    {
        let snapshot = UsageSnapshot(
            primary: primary,
            secondary: weekly,
            tertiary: monthly,
            extraRateWindows: extras,
            updatedAt: usesLastKnownUsage ? self.now.addingTimeInterval(-3600) : self.now)
        let siblingSnapshot = UsageSnapshot(
            primary: self.window(0, after: 600),
            secondary: nil,
            updatedAt: self.now)
        let accounts: [ProviderAccountUsageSnapshot] = (0..<4).map { index in
            let isTarget = index == 1
            let label = isTarget ? "owner@example.com" : "account-\(index)@example.com"
            let chosenSnapshot: UsageSnapshot = isTarget ? snapshot : siblingSnapshot
            return ProviderAccountUsageSnapshot(
                id: ProviderAccountIdentity(source: "fixture", opaqueID: String(index)),
                provider: provider,
                displayLabel: label,
                isActive: index == 0,
                canActivate: index != 0,
                usesLastKnownUsage: isTarget && usesLastKnownUsage,
                snapshot: chosenSnapshot,
                error: isTarget ? error : nil,
                sourceLabel: "fixture")
        }
        let plan = AccountMenuLayoutPlanner.plan(accounts: accounts, healthyTailExpanded: true)
        return try #require(plan.rows.compactMap { row in
            if case let .compact(compact) = row, compact.accountID.opaqueID == "1" { return compact }
            return nil
        }.first)
    }

    static func model(
        _ row: AccountMenuLayoutPlanner.CompactRow,
        style: ResetTimeDisplayStyle = .countdown,
        now: Date = Self.now,
        hidePersonalInfo: Bool = false) -> MenuCardCompactAccountRowView.Model
    {
        MenuCardCompactAccountRowView.Model(
            row: row,
            resetTimeDisplayStyle: style,
            hidePersonalInfo: hidePersonalInfo,
            now: now)
    }
}

@MainActor
struct MenuCardCompactAccountRowTests {
    private typealias Fixture = CompactAccountResetFixtures

    @Test
    func `cached headroom does not hide the error indicator`() {
        let model = MenuCardCompactAccountRowView.Model(
            label: "Stale account",
            headroomPercent: 72,
            severity: .healthy,
            constraintDetail: nil,
            hasError: true,
            showsBestBadge: false)

        #expect(model.showsErrorIndicator)
        #expect(model.showsHeadroomIndicator)
        #expect(model.headroomLabel == "72%")
    }

    @Test
    func `each constrained window uses its own reset and configured style`() throws {
        let session = Fixture.window(98, after: 3600)
        let weekly = Fixture.window(89, after: 187_200)
        let row = try Fixture.row(primary: session, weekly: weekly)

        #expect(row.headroomPercent == 2)
        #expect(row.windowDetails.map(\.window) == [session, weekly])

        let countdown = Fixture.model(row)
        let absolute = Fixture.model(row, style: .absolute)
        let sessionCountdown = try #require(
            UsageFormatter.resetLine(for: session, style: .countdown, now: Fixture.now))
        let weeklyCountdown = try #require(
            UsageFormatter.resetLine(for: weekly, style: .countdown, now: Fixture.now))
        let sessionAbsolute = try #require(
            UsageFormatter.resetLine(for: session, style: .absolute, now: Fixture.now))
        let weeklyAbsolute = try #require(
            UsageFormatter.resetLine(for: weekly, style: .absolute, now: Fixture.now))

        #expect(countdown.detailLines[0].hasSuffix(sessionCountdown))
        #expect(countdown.detailLines[1].hasSuffix(weeklyCountdown))
        #expect(absolute.detailLines[0].hasSuffix(sessionAbsolute))
        #expect(absolute.detailLines[1].hasSuffix(weeklyAbsolute))
        #expect(countdown.heightFingerprint != absolute.heightFingerprint)
        #expect(countdown.accessibilityText.contains(weeklyCountdown))
    }

    @Test
    func `healthy accounts show their least remaining visible window`() throws {
        let primary = Fixture.window(0, after: 3600)
        let weekly = Fixture.window(10, after: 172_800)
        let row = try Fixture.row(primary: primary, weekly: weekly)

        #expect(row.severity == .healthy)
        #expect(row.constraints.isEmpty)
        #expect(row.windowDetails.map(\.window) == [weekly])
        #expect(Fixture.model(row).detailLines.count == 1)
    }

    @Test
    func `provider hidden reset policy does not show balance descriptions`() throws {
        let balance = Fixture.window(80, description: "$5.00 (Paid: $3.00 / Granted: $2.00)")
        let row = try Fixture.row(provider: .deepseek, primary: balance)
        let model = Fixture.model(row)

        #expect(row.windowDetails.first?.resetPresentation == .hidden)
        #expect(model.detailLines.count == 1)
        #expect(!model.detailLines[0].contains(" · "))
        #expect(!model.accessibilityText.contains("$5.00"))
    }

    @Test
    func `provider reset description is shown without a reset prefix`() throws {
        let window = Fixture.window(80, description: "  Quota detail  ")
        let row = try Fixture.row(provider: .openrouter, primary: window)
        let model = Fixture.model(row)

        #expect(row.windowDetails.first?.resetPresentation == .providerDescription)
        #expect(model.detailLines[0].hasSuffix(" · Quota detail"))
        #expect(!model.detailLines[0].contains("Resets"))

        let blank = try Fixture.row(provider: .openrouter, primary: Fixture.window(80, description: "  "))
        #expect(Fixture.model(blank).detailLines[0].contains(" · ") == false)
    }

    @Test
    func `primary reset suppression leaves a secondary reset visible`() throws {
        let primary = Fixture.window(80, after: 3600, description: "Balance")
        let weekly = Fixture.window(70, after: 187_200)
        let row = try Fixture.row(provider: .manus, primary: primary, weekly: weekly)
        let model = Fixture.model(row)
        let weeklyReset = try #require(
            UsageFormatter.resetLine(for: weekly, style: .countdown, now: Fixture.now))

        #expect(row.windowDetails.map(\.resetPresentation) == [.hidden, .standard])
        #expect(!model.detailLines[0].contains("Balance"))
        #expect(model.detailLines[1].hasSuffix(weeklyReset))
    }

    @Test
    func `crof hides the primary reset until the secondary window is available`() throws {
        let primary = Fixture.window(80, after: 3600)
        let withoutSecondary = try Fixture.row(provider: .crof, primary: primary)
        let withSecondary = try Fixture.row(
            provider: .crof,
            primary: primary,
            weekly: Fixture.window(70, after: 187_200))
        let primaryReset = try #require(
            UsageFormatter.resetLine(for: primary, style: .countdown, now: Fixture.now))

        #expect(withoutSecondary.windowDetails.first?.resetPresentation == .hidden)
        #expect(withSecondary.windowDetails.first?.resetPresentation == .standard)
        #expect(Fixture.model(withSecondary).detailLines[0].hasSuffix(primaryReset))
    }

    @Test
    func `captured stale usage remains visible with an error and affects height`() throws {
        let row = try Fixture.row(
            primary: Fixture.window(90, after: 3600),
            error: "Refresh failed",
            usesLastKnownUsage: true)
        let model = Fixture.model(row)
        let capturedAt = try #require(row.lastKnownUsageCapturedAt)
        let message = LastKnownUsagePresentation.message(capturedAt: capturedAt, now: Fixture.now)

        #expect(model.hasError)
        #expect(model.showsErrorIndicator)
        #expect(model.showsHeadroomIndicator)
        #expect(model.detailLines.last == message)
        #expect(model.accessibilityText.contains(message))
        #expect(model.heightFingerprint.contains(message))
    }

    @Test
    func `privacy mode redacts reset prose and keeps it out of accessibility text`() throws {
        let row = try Fixture.row(
            provider: .openrouter,
            primary: Fixture.window(80, description: "Quota for owner@example.com"))
        let model = Fixture.model(row, hidePersonalInfo: true)

        #expect(model.label.isEmpty)
        #expect(model.detailLines[0].contains("Quota for"))
        #expect(!model.detailLines[0].contains("@example.com"))
        #expect(!model.accessibilityText.contains("@example.com"))
    }
}
