import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct SyncCoordinatorProviderDetailsTests {
    @Test
    func `WorkBuddy sync allowlists numeric credit details and clears empty results`() {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [
                .makeSection(title: "Credits", rows: [
                    .makeRow(label: "Left", value: "1,234.5"),
                    .makeRow(label: "Total", value: "2,000"),
                    .makeRow(label: "Reserved", value: "10"),
                    .makeRow(label: "Cookie", value: "fixture-secret"),
                    .makeRow(label: "Account Email", value: "person@example.com"),
                    .makeRow(label: "Left", value: "NaN"),
                ]),
                .makeSection(title: "Account", rows: [.makeRow(label: "ID", value: "private-id")]),
            ],
            updatedAt: Date())

        #expect(SyncCoordinator.mapProviderDetails(provider: .workbuddy, snapshot: snapshot) == [
            SyncProviderDetailSection(title: "Credits", rows: [
                .init(label: "Left", value: "1,234.5"),
                .init(label: "Total", value: "2,000"),
                .init(label: "Reserved", value: "10"),
            ]),
        ])
        #expect(SyncCoordinator.mapProviderDetails(provider: .workbuddy, snapshot: nil) == nil)

        let empty = UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [.makeSection(title: "Credits", rows: [.makeRow(label: "Cookie", value: "secret")])],
            updatedAt: Date())
        #expect(SyncCoordinator.mapProviderDetails(provider: .workbuddy, snapshot: empty) == [])
    }

    @Test
    func `WorkBuddy phone payload omits account identity and cookie details`() async throws {
        let suite = "SyncCoordinatorWorkBuddyDetailsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .workbuddy,
            metadata: #require(ProviderDefaults.metadata[.workbuddy]),
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                details: [.makeSection(title: "Credits", rows: [
                    .makeRow(label: "Left", value: "450"),
                    .makeRow(label: "Total", value: "500"),
                    .makeRow(label: "Cookie", value: "session=fixture-secret"),
                    .makeRow(label: "Account Email", value: "person@example.com"),
                ])],
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .workbuddy,
                    accountEmail: "person@example.com",
                    accountOrganization: nil,
                    loginMethod: "Pro",
                    accountID: "private-id")),
            provider: .workbuddy)

        let pusher = MockSyncPusher()
        await SyncCoordinator(store: store, settings: settings, syncManager: pusher).pushCurrentSnapshot()
        let provider = try #require(pusher.lastPerProviderEnvelopes.first {
            $0.provider.providerID == "workbuddy"
        }?.provider)
        #expect(provider.accountEmail == nil)
        #expect(provider.accountIdentities == nil)
        #expect(provider.providerDetails == [SyncProviderDetailSection(title: "Credits", rows: [
            .init(label: "Left", value: "450"),
            .init(label: "Total", value: "500"),
        ])])
        let wire = try #require(String(bytes: JSONEncoder().encode(provider), encoding: .utf8))
        #expect(!wire.contains("person@example.com"))
        #expect(!wire.contains("private-id"))
        #expect(!wire.contains("fixture-secret"))
    }

    @Test(arguments: [0, 1, 2])
    func `Claude sync publishes only cloud dollars and handles missing or expired balances`(phase: Int) async throws {
        let expired = phase == 1
        let suite = "SyncCoordinatorClaudeCloudTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        settings.accountWidgetsEnabled = false
        try settings.setProviderEnabled(
            provider: .claude, metadata: #require(ProviderDefaults.metadata[.claude]), enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let expiry = Date().addingTimeInterval(expired ? -3600 : 3600).ISO8601Format()
        let details = [ProviderDetailSection.makeSection(title: "Cloud credits", rows: [
            .makeRow(
                id: "claude-cloud-credits",
                label: "Cloud credits",
                value: "$15.00 of $20.00 remaining",
                secondaryValue: "Expires \(expiry)",
                usageValue: 15),
            .makeRow(label: "Cookie", value: "fixture-secret"),
        ]), .makeSection(rows: [.makeRow(label: "Limit Reset Credits", value: "fixture-redemption")])]
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: phase == 2 ? RateWindow(
                    usedPercent: 12,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil) : nil,
                secondary: nil,
                details: phase == 2 ? [] : details,
                updatedAt: Date()),
            provider: .claude)
        let pusher = MockSyncPusher()
        await SyncCoordinator(store: store, settings: settings, syncManager: pusher).pushCurrentSnapshot()
        let provider = try #require(pusher.lastPerProviderEnvelopes.first { $0.provider.providerID == "claude" }?
            .provider)
        let expected = [SyncProviderDetailSection(title: "Cloud credits", rows: [
            .init(
                label: "Cloud credits",
                value: expired ? "Expired" : "$15.00 of $20.00 remaining",
                secondaryValue: "Expires \(expiry)"),
        ])]
        let expectedDetails = phase == 2 ? [] : expected
        #expect(provider.providerDetails == expectedDetails)
        #expect(provider.rateWindows.isEmpty == (phase != 2))
        if phase == 2 { #expect(provider.rateWindows.first?.usedPercent == 12) }
        #expect(provider.budget == nil)
        #expect(provider.costSummary == nil)
        #expect(pusher.lastSnapshot?.providers.first { $0.providerID == "claude" }?.providerDetails == expectedDetails)
        let wire = try #require(String(bytes: JSONEncoder().encode(provider), encoding: .utf8))
        #expect(!wire.contains("fixture-secret"))
        #expect(!wire.contains("fixture-redemption"))
    }

    @Test
    func `Muse browser team source reaches iPhone without the team list or credential rows`() async throws {
        let suite = "SyncCoordinatorMuseDetailsTests-\(UUID().uuidString)"
        let authFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite)-auth.json")
        try Data(#"{"providers":{"meta":{"mechanism":"oauth","access_token":"dca:fixture-sync"}}}"#.utf8)
            .write(to: authFile)
        defer { try? FileManager.default.removeItem(at: authFile) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .muse,
            metadata: #require(ProviderDefaults.metadata[.muse]),
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            environmentBase: [MuseCredentials.authPathEnvironmentKey: authFile.path])
        let details = try [
            ProviderDetailSection(title: "Muse Code subscription", rows: [
                .init(label: "Plan", value: "Muse Code Power Usage"),
            ]),
            ProviderDetailSection(title: "Browser teams", rows: [
                .init(label: "Other", value: "11"),
                .init(label: "Selected", value: "22"),
            ]),
            ProviderDetailSection(title: "Browser team quota (dev.meta.ai)", rows: [
                .init(label: "Team", value: "Selected"),
                .init(label: "Weekly", value: "15%"),
                .init(label: "Cookie", value: "llama_dev_sess=fixture-secret"),
            ]),
        ]
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 15, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
                details: details,
                updatedAt: Date(),
                dataConfidence: .estimated),
            provider: .muse)
        let pusher = MockSyncPusher()
        await SyncCoordinator(store: store, settings: settings, syncManager: pusher).pushCurrentSnapshot()

        let provider = try #require(pusher.lastPerProviderEnvelopes.first {
            $0.provider.providerID == "muse"
        }?.provider)
        #expect(provider.rateWindows.count == 2)
        #expect(provider.providerDetails == [SyncProviderDetailSection(
            title: "Browser team quota (dev.meta.ai)",
            rows: [.init(label: "Team", value: "Selected")])])
        let legacy = try #require(pusher.lastSnapshot?.providers.first { $0.providerID == "muse" })
        #expect(legacy.providerDetails == provider.providerDetails)
    }

    @Test
    func `Copilot seat credits are published as provider details`() async throws {
        let suite = "SyncCoordinatorCopilotDetailsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .copilot,
            metadata: #require(ProviderDefaults.metadata[.copilot]),
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                details: [.makeSection(title: "Credits", rows: [
                    .makeRow(label: "Credits used", value: "12 / 50", secondaryValue: "Resets next month"),
                ])],
                updatedAt: Date()),
            provider: .copilot)
        let pusher = MockSyncPusher()
        await SyncCoordinator(store: store, settings: settings, syncManager: pusher).pushCurrentSnapshot()

        let provider = try #require(pusher.lastPerProviderEnvelopes.first {
            $0.provider.providerID == "copilot"
        }?.provider)
        #expect(provider.providerDetails?.first?.rows.first?.value == "12 / 50")
        #expect(provider.providerDetails?.first?.rows.first?.secondaryValue == "Resets next month")
    }

    @Test
    func `detail-only balance is published without inventing quota windows`() async throws {
        let suite = "SyncCoordinatorProviderDetailsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .atlascloud,
            metadata: #require(ProviderDefaults.metadata[.atlascloud]),
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let details = [ProviderDetailSection.makeSection(
            title: "Account balance",
            rows: [.makeRow(label: "Available balance", value: "$95.50")])]
        store._setSnapshotForTesting(
            UsageSnapshot(primary: nil, secondary: nil, details: details, updatedAt: Date()),
            provider: .atlascloud)
        let pusher = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: pusher)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(pusher.lastSnapshot?.providers.first { $0.providerID == "atlascloud" })
        #expect(provider.rateWindows.isEmpty)
        #expect(provider.providerDetails?.first?.rows.first?.value == "$95.50")
        let record = try #require(pusher.lastPerProviderEnvelopes.first {
            $0.provider.providerID == "atlascloud"
        })
        #expect(record.provider.providerDetails?.first?.rows.first?.value == "$95.50")
    }

    @Test
    func `plugin detail rows survive Mac mapping into per-provider iPhone records`() async throws {
        let suite = "SyncCoordinatorPluginDetailsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        let providers: [UsageProvider] = [.devpass, .raycast, .typesafe, .xkiro, .poe, .sakana]
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            environmentBase: [
                PoeSettingsReader.apiKeyEnvironmentKey: "fixture-key",
                SakanaSettingsReader.cookieHeaderKey: "session=fixture",
            ])
        for provider in providers {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(ProviderDefaults.metadata[provider]),
                enabled: true)
            store._setSnapshotForTesting(
                UsageSnapshot(
                    primary: nil,
                    secondary: nil,
                    details: [.makeSection(
                        title: "Account details",
                        rows: [.makeRow(label: "Value", value: provider.rawValue)])],
                    updatedAt: Date()),
                provider: provider)
        }
        let pusher = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: pusher)
        await coordinator.pushCurrentSnapshot()

        for provider in providers {
            let envelope = try #require(pusher.lastPerProviderEnvelopes.first {
                $0.provider.providerID == provider.rawValue
            })
            #expect(envelope.provider.rateWindows.isEmpty)
            #expect(envelope.provider.providerDetails?.first?.rows.first?.value == provider.rawValue)
        }
    }

    private struct BillingFixture {
        let provider: UsageProvider
        let expected: [SyncProviderDetailSection]

        var details: [ProviderDetailSection] {
            self.expected.map { section in
                .makeSection(title: section.title, rows: section.rows.map { row in
                    .makeRow(label: row.label, value: row.value, secondaryValue: "fixture-private-secondary")
                } + [
                    .makeRow(label: "API key", value: "fixture-private-key"),
                    .makeRow(label: "Account Email", value: "fixture-private@example.com"),
                    .makeRow(label: "Action URL", value: "https://example.com/fixture-private-action"),
                ])
            } + [.makeSection(title: "Account", rows: [.makeRow(label: "ID", value: "fixture-private-id")])]
        }
    }

    private static var billingFixtures: [BillingFixture] {
        [
            .init(provider: .tavily, expected: [
                .init(title: "Account plan", rows: [
                    .init(label: "Used", value: "1,000 credits"), .init(label: "Limit", value: "2,000 credits"),
                    .init(label: "Remaining", value: "1,000 credits"),
                ]),
                .init(title: "API key", rows: [
                    .init(label: "Used", value: "10 credits"), .init(label: "Limit", value: "Unlimited"),
                ]),
                .init(title: "Pay as you go", rows: [
                    .init(label: "Used", value: "1 credits"), .init(label: "Limit", value: "5 credits"),
                    .init(label: "Remaining", value: "4 credits"),
                ]),
            ]),
            .init(provider: .exa, expected: [
                .init(title: "API key this month (UTC)", rows: [.init(label: "Spend", value: "$12.34")]),
            ]),
            .init(provider: .linkup, expected: [
                .init(title: "Account balance", rows: [.init(label: "Credit balance", value: "-$1.25")]),
            ]),
            .init(provider: .tinyapi, expected: [
                .init(title: "Credits", rows: [.init(label: "Available credits", value: "12.50 credits")]),
            ]),
            .init(provider: .cosmic, expected: [
                .init(title: "Input tokens", rows: [
                    .init(label: "Used", value: "1,200"), .init(label: "Allowance", value: "1,000"),
                    .init(label: "Remaining", value: "0"), .init(label: "Above allowance", value: "200"),
                ]),
                .init(title: "Output tokens", rows: [
                    .init(label: "Used", value: "50"), .init(label: "Allowance", value: "Not reported"),
                ]),
            ]),
            .init(provider: .aerostack, expected: [
                .init(title: "Monthly AI tokens", rows: [
                    .init(label: "Tokens used", value: "20"), .init(label: "Allowance", value: "10"),
                    .init(label: "Remaining", value: "0"), .init(label: "Above allowance", value: "10"),
                    .init(label: "Period", value: "2026-10"),
                ]),
            ]),
            .init(provider: .sailresearch, expected: [
                .init(title: "Organization billing", rows: [
                    .init(label: "Credit balance", value: "-$4.50"),
                    .init(label: "Last 30 days spend", value: "$5.00"),
                ]),
            ]),
            .init(provider: .sofya, expected: [
                .init(title: "Account credits", rows: [
                    .init(label: "Available credits", value: "1.123456"), .init(label: "Plan credits", value: "20"),
                    .init(label: "Purchased credits", value: "0"),
                    .init(label: "Monthly reset", value: "2026-10-31 12:30:00.123 UTC"),
                ]),
            ]),
            .init(provider: .ollama, expected: [
                .init(title: "Credits", rows: [
                    .init(label: "Credit balance", value: "$18.25"),
                    .init(label: "Monthly credits used", value: "$4.50"),
                ]),
            ]),
            .init(provider: .jetbrains, expected: [
                .init(title: "Top-up credits", rows: [.init(label: "Remaining", value: "54.90 credits")]),
            ]),
        ]
    }

    @Test
    func `billing details allow only known display values and distinguish empty success from absence`() {
        for fixture in Self.billingFixtures {
            let snapshot = UsageSnapshot(
                primary: nil, secondary: nil, details: fixture.details, updatedAt: Date())
            #expect(SyncCoordinator.mapProviderDetails(provider: fixture.provider, snapshot: snapshot) == fixture
                .expected)
            #expect(SyncCoordinator.mapProviderDetails(provider: fixture.provider, snapshot: nil) == nil)
            #expect(SyncCoordinator.mapProviderDetails(
                provider: fixture.provider,
                snapshot: UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date())) == [])
        }
    }

    @Test
    func `actual wallet and topup snapshot builders match the phone detail allowlist`() throws {
        let html = """
        <section>
          <h2>Usage credits<span>pro</span></h2>
          <span>$18.25</span>
          <p>Refills to $30 in 3 weeks.</p>
          <span>Monthly credits used</span><span>$4.50</span>
        </section>
        """
        let wallet = try OllamaUsageParser.parse(html: html).toUsageSnapshot()
        let walletFixture = try #require(Self.billingFixtures.first { $0.provider == .ollama })
        #expect(SyncCoordinator.mapProviderDetails(provider: .ollama, snapshot: wallet) == walletFixture.expected)
        #expect(wallet.primary == nil)
        #expect(wallet.secondary == nil)
        let fractionalWallet = try OllamaUsageParser.parse(
            html: html.replacingOccurrences(of: "$18.25", with: "$0.0003")).toUsageSnapshot()
        #expect(SyncCoordinator.mapProviderDetails(
            provider: .ollama, snapshot: fractionalWallet)?.first?.rows.first?.value == "$0.0003")

        let topUp = try #require(JetBrainsTopUpQuota(maximum: 10_000_000, available: 5_490_000))
        let quota = JetBrainsQuotaInfo(
            type: "fixture-plan", used: 200_000, maximum: 1_000_000, available: 800_000, until: nil, topUp: topUp)
        let jetbrains = try JetBrainsStatusSnapshot(
            quotaInfo: quota, refillInfo: nil, detectedIDE: nil).toUsageSnapshot()
        let topUpFixture = try #require(Self.billingFixtures.first { $0.provider == .jetbrains })
        #expect(SyncCoordinator.mapProviderDetails(provider: .jetbrains, snapshot: jetbrains) == topUpFixture.expected)
        #expect(jetbrains.primary?.usedPercent == 20)
        #expect(jetbrains.secondary == nil)
    }

    @Test
    func `billing mapper rejects malformed oversized values and coalesces duplicate fields`() {
        let rows: [ProviderDetailSection.Row] = [
            .makeRow(label: "Credit balance", value: "NaN"),
            .makeRow(label: "Credit balance", value: "$12,34.00"),
            .makeRow(label: "Credit balance", value: "$" + String(repeating: "9", count: 96)),
            .makeRow(label: "Credit balance", value: "$1.00", secondaryValue: "fixture-private"),
            .makeRow(label: "Credit balance", value: "$2.00"),
            .makeRow(label: "Monthly credits used", value: "-$4.50"),
            .makeRow(label: "Next refill", value: "to $30 in 3 weeks."),
        ]
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [
                .makeSection(title: "Credits", rows: rows),
                .makeSection(title: "Credits", rows: [.makeRow(label: "Credit balance", value: "$3.00")]),
                .makeSection(title: "Unrelated wallet", rows: [.makeRow(label: "Credit balance", value: "$99.00")]),
            ],
            updatedAt: Date())
        #expect(SyncCoordinator.mapProviderDetails(provider: .ollama, snapshot: snapshot) == [
            .init(title: "Credits", rows: [.init(label: "Credit balance", value: "$1.00")]),
        ])
        let malformed: [(UsageProvider, String, String, String)] = [
            (.exa, "API key this month (UTC)", "Spend", "-$1.00"),
            (.tinyapi, "Credits", "Available credits", "-1 credits"),
            (.jetbrains, "Top-up credits", "Remaining", "Infinity credits"),
            (.tavily, "Account plan", "Used", "1.5 credits"),
            (.cosmic, "Input tokens", "Used", "1e3"),
            (.aerostack, "Monthly AI tokens", "Period", "2026-13"),
            (.sofya, "Account credits", "Monthly reset", "2026-02-30 12:30:00 UTC"),
            (.sailresearch, "Organization billing", "Credit balance", "USD 10.00 secret"),
            (.linkup, "Account balance", "Credit balance", "$1.00 owed fixture-private"),
        ]
        for (provider, title, label, value) in malformed {
            let snapshot = UsageSnapshot(
                primary: nil,
                secondary: nil,
                details: [.makeSection(title: title, rows: [.makeRow(label: label, value: value)])],
                updatedAt: Date())
            #expect(SyncCoordinator.mapProviderDetails(provider: provider, snapshot: snapshot) == [])
        }
    }

    @Test
    func `new billing details survive ghost filtering and envelope persistence without inventing quota`() async throws {
        let suite = "SyncCoordinatorBillingDetailsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        settings.accountWidgetsEnabled = false
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        for fixture in Self.billingFixtures {
            try settings.setProviderEnabled(
                provider: fixture.provider,
                metadata: #require(ProviderDefaults.metadata[fixture.provider]),
                enabled: true)
            store._setSnapshotForTesting(
                UsageSnapshot(
                    primary: nil,
                    secondary: nil,
                    details: fixture.details,
                    updatedAt: Date()),
                provider: fixture.provider)
        }
        let pusher = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: pusher)
        await coordinator.pushCurrentSnapshot()
        for fixture in Self.billingFixtures {
            let envelope = try #require(pusher.lastPerProviderEnvelopes.first {
                $0.provider.providerID == fixture.provider.rawValue
            })
            let provider = envelope.provider
            #expect(provider.providerDetails == fixture.expected)
            #expect(provider.rateWindows.isEmpty)
            #expect(provider.primary == nil)
            #expect(provider.secondary == nil)
            #expect(provider.budget == nil)
            #expect(provider.costSummary == nil)
            #expect(pusher.lastSnapshot?.providers.first {
                $0.providerID == fixture.provider.rawValue
            }?.providerDetails == fixture.expected)
            let persisted = try JSONEncoder().encode(envelope)
            let restored = try JSONDecoder().decode(ProviderUsageEnvelope.self, from: persisted)
            #expect(restored.provider.providerDetails == fixture.expected)
            let wire = try #require(String(bytes: persisted, encoding: .utf8))
            #expect(!wire.contains("fixture-private"))
        }
        // A successful empty detail-only result replaces the legacy payload with [] and deletes
        // its old per-provider record through the existing ghost cleanup path.
        store._setSnapshotForTesting(
            UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date()), provider: .linkup)
        await coordinator.pushCurrentSnapshot()
        #expect(pusher.lastSnapshot?.providers.first { $0.providerID == "linkup" }?.providerDetails == [])
        #expect(pusher.deletedRecordNamesAcrossCalls.flatMap(\.self).contains { $0.contains("|linkup|") })

        // A provider that still reports real quota retains that quota and explicitly clears wallet rows.
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .ollama)
        await coordinator.pushCurrentSnapshot()
        let cleared = try #require(pusher.lastPerProviderEnvelopes.first { $0.provider.providerID == "ollama" })
        #expect(cleared.provider.providerDetails == [])
        #expect(cleared.provider.primary?.usedPercent == 20)
        #expect(cleared.provider.secondary == nil)
        let restored = try JSONDecoder().decode(ProviderUsageEnvelope.self, from: JSONEncoder().encode(cleared))
        #expect(restored.provider.providerDetails == [])
    }

    @Test
    func `LithosAI prepaid balance stays detail and never becomes mobile spend or quota`() async throws {
        let suite = "SyncCoordinatorLithosAIDetailsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .lithosai,
            metadata: #require(ProviderDefaults.metadata[.lithosai]),
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                providerCost: ProviderCostSnapshot(
                    used: 4.70709986,
                    limit: 0,
                    currencyCode: "USD",
                    period: "Prepaid credits",
                    updatedAt: Date()),
                details: [.makeSection(title: "Billing", rows: [
                    .makeRow(label: "Balance", value: "$4.71", usageValue: 4.70709986),
                    .makeRow(label: "Payment card", value: "Added"),
                    .makeRow(label: "Account status", value: "Active"),
                    .makeRow(label: "Today (UTC)", value: "$0.36"),
                    .makeRow(label: "This month (UTC)", value: "$2.36"),
                ])],
                updatedAt: Date()),
            provider: .lithosai)
        let pusher = MockSyncPusher()
        await SyncCoordinator(store: store, settings: settings, syncManager: pusher).pushCurrentSnapshot()

        let provider = try #require(pusher.lastPerProviderEnvelopes.first {
            $0.provider.providerID == "lithosai"
        }?.provider)
        #expect(provider.rateWindows.isEmpty)
        #expect(provider.primary == nil)
        #expect(provider.secondary == nil)
        #expect(provider.budget == nil)
        #expect(provider.costSummary == nil)
        #expect(provider.statusMessage == "Prepaid balance: USD 4.71")
        #expect(provider.providerDetails?.first?.rows.map(\.label) == [
            "Balance", "Payment card", "Account status", "Today (UTC)", "This month (UTC)",
        ])
    }
}
