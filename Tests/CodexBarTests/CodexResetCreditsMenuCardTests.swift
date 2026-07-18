import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CodexResetCreditsMenuCardTests {
    @Test
    func `presentation uses authoritative count and exact known expiries in stable order`() throws {
        let now = Date(timeIntervalSince1970: 1_781_726_400)
        let snapshot = Self.snapshot(
            now: now,
            credits: [
                Self.credit(id: "no-expiry", status: .available, now: now, expiresIn: nil),
                Self.credit(id: "late", status: .available, now: now, expiresIn: 172_800),
                Self.credit(id: "redeemed", status: .redeemed, now: now, expiresIn: 43200),
                Self.credit(id: "expired", status: .available, now: now, expiresIn: -1),
                Self.credit(id: "early", status: .available, now: now, expiresIn: 86400),
            ],
            availableCount: 99)

        let model = try Self.model(snapshot: snapshot, now: now)
        let presentation = try #require(model.codexResetCredits)
        let earlyExact = CodexResetCreditsPresentation.exactExpiryTimeText(now.addingTimeInterval(86400))
        let lateExact = CodexResetCreditsPresentation.exactExpiryTimeText(now.addingTimeInterval(172_800))

        #expect(presentation.text == "99 available")
        #expect(presentation.availableCount == 99)
        #expect(presentation.items.map(\.expiryText) == [
            "Expires \(earlyExact)",
            "Expires \(lateExact)",
            "No expiry",
        ])
        #expect(presentation.items.map(\.relativeExpiryText) == ["in 1d", "in 2d", nil])
        #expect(presentation.nearestKnownExpiryText == "Next expires \(earlyExact)")
        #expect(presentation.partialDetailText == "Expiry times: 3 of 99")
        #expect(presentation.helpText ==
            "1. Expires \(earlyExact)\n" +
            "2. Expires \(lateExact)\n" +
            "3. No expiry\n" +
            "Expiry times: 3 of 99")
        #expect(presentation.accessibilityLabel.contains(presentation.helpText))
    }

    @Test
    func `no-expiry reset remains visible without a next-expiry date`() throws {
        let now = Date(timeIntervalSince1970: 1_781_726_400)
        let model = try Self.model(
            snapshot: Self.snapshot(
                now: now,
                credits: [Self.credit(id: "no-expiry", status: .available, now: now, expiresIn: nil)]),
            now: now)
        let presentation = try #require(model.codexResetCredits)

        #expect(presentation.text == "1 available")
        #expect(presentation.items.map(\.expiryText) == ["No expiry"])
        #expect(presentation.nearestKnownExpiryText == "No expiry")
        #expect(presentation.partialDetailText == nil)
        #expect(model.hasUsageContent)
    }

    @Test
    func `inventory always exposes exact timestamp and omits countdown in absolute style`() throws {
        let now = Date(timeIntervalSince1970: 1_781_726_400)
        let expiresAt = now.addingTimeInterval(86400)
        let model = try Self.model(
            snapshot: Self.snapshot(
                now: now,
                credits: [Self.credit(id: "finite", status: .available, now: now, expiresIn: 86400)]),
            resetStyle: .absolute,
            now: now)
        let presentation = try #require(model.codexResetCredits)
        let formatted = CodexResetCreditsPresentation.exactExpiryTimeText(expiresAt)

        #expect(presentation.items.map(\.expiryText) == ["Expires \(formatted)"])
        #expect(presentation.items.map(\.relativeExpiryText) == [nil])
        #expect(presentation.nearestKnownExpiryText == "Next expires \(formatted)")
    }

    @Test
    func `optional usage preference does not hide reset inventory`() throws {
        let now = Date(timeIntervalSince1970: 1_781_726_400)
        let model = try Self.model(
            snapshot: Self.snapshot(
                now: now,
                credits: [Self.credit(id: "finite", status: .available, now: now, expiresIn: 86400)]),
            showOptionalUsage: false,
            now: now)

        #expect(model.codexResetCredits?.text == "1 available")
        #expect(model.codexResetCredits?.items.first?.relativeExpiryText == "in 1d")
    }

    @Test
    func `presenter keeps all known expiries for provider settings`() throws {
        let now = Date(timeIntervalSince1970: 1_781_726_400)
        let credits = (1...6).map { day in
            Self.credit(id: "day-\(day)", status: .available, now: now, expiresIn: Double(day * 86400))
        }
        let model = try Self.model(snapshot: Self.snapshot(now: now, credits: credits), now: now)

        let presentation = try #require(model.codexResetCredits)
        #expect(presentation.items.count == 6)
        #expect(presentation.partialDetailText == nil)
        #expect(presentation.helpText.split(separator: "\n").count == 6)
    }

    @Test
    func `partial backend detail reports known expiry count without inventing dates`() throws {
        let now = Date(timeIntervalSince1970: 1_781_726_400)
        let credits = (1...2).map { day in
            Self.credit(id: "day-\(day)", status: .available, now: now, expiresIn: Double(day * 86400))
        }
        let model = try Self.model(
            snapshot: Self.snapshot(now: now, credits: credits, availableCount: 4),
            now: now)

        let presentation = try #require(model.codexResetCredits)
        #expect(presentation.text == "4 available")
        #expect(presentation.items.count == 2)
        #expect(presentation.partialDetailText == "Expiry times: 2 of 4")
    }

    @Test
    func `hosted usage model keeps reset inventory compatible with live refresh`() throws {
        let now = Date(timeIntervalSince1970: 1_781_726_400)
        let model = try Self.model(
            snapshot: Self.snapshot(
                now: now,
                credits: [Self.credit(id: "finite", status: .available, now: now, expiresIn: 86400)]),
            now: now)

        #expect(model.codexResetCredits != nil)
        #expect(model.hasCompatibleTrackedLayout(with: model))
    }

    @Test
    func `authoritative count remains visible when no expiry details are known`() throws {
        let now = Date(timeIntervalSince1970: 1_781_726_400)
        let model = try Self.model(
            snapshot: Self.snapshot(
                now: now,
                credits: [Self.credit(id: "expired", status: .available, now: now, expiresIn: -1)],
                availableCount: 1),
            now: now)

        #expect(model.codexResetCredits?.text == "1 available")
        #expect(model.codexResetCredits?.items.isEmpty == true)
        #expect(model.codexResetCredits?.nearestKnownExpiryText == nil)
        #expect(model.codexResetCredits?.partialDetailText == "Expiry times: 0 of 1")
        #expect(model.hasCompatibleTrackedLayout(with: model))
    }

    @Test
    func `authoritative zero hides stale available detail`() throws {
        let now = Date(timeIntervalSince1970: 1_781_726_400)
        let model = try Self.model(
            snapshot: Self.snapshot(
                now: now,
                credits: [Self.credit(id: "stale", status: .available, now: now, expiresIn: 86400)],
                availableCount: 0),
            now: now)

        #expect(model.codexResetCredits == nil)
    }

    private static func model(
        snapshot: UsageSnapshot,
        showOptionalUsage: Bool = true,
        resetStyle: ResetTimeDisplayStyle = .countdown,
        now: Date) throws -> UsageMenuCardView.Model
    {
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        return UsageMenuCardView.Model.make(UsageMenuCardView.Model.Input(
            provider: .codex,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: resetStyle,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: showOptionalUsage,
            hidePersonalInfo: false,
            now: now))
    }

    private static func snapshot(
        now: Date,
        credits: [CodexRateLimitResetCredit],
        availableCount: Int? = nil) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: nil,
            secondary: nil,
            codexResetCredits: CodexRateLimitResetCreditsSnapshot(
                credits: credits,
                availableCount: availableCount ?? credits.count,
                updatedAt: now),
            updatedAt: now)
    }

    private static func credit(
        id: String,
        status: CodexRateLimitResetCreditStatus,
        now: Date,
        expiresIn: TimeInterval?) -> CodexRateLimitResetCredit
    {
        CodexRateLimitResetCredit(
            id: id,
            resetType: "codex_rate_limits",
            status: status,
            grantedAt: now.addingTimeInterval(-3600),
            expiresAt: expiresIn.map(now.addingTimeInterval),
            redeemStartedAt: nil,
            redeemedAt: nil,
            title: nil,
            description: nil)
    }
}
