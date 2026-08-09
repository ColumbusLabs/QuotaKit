import Foundation
import Testing
@testable import CodexBarCore

struct ProviderDiagnosticExportTests {
    @Test
    func `generic diagnostic export encodes safe provider envelope`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let export = ProviderDiagnosticExport(
            timestamp: now,
            provider: "codex",
            displayName: "Codex",
            source: "api",
            sourceMode: "auto",
            auth: ProviderDiagnosticAuthSummary(configured: true, modes: ["api"]),
            usage: ProviderDiagnosticUsageSummary(from: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 25,
                    windowMinutes: 300,
                    resetsAt: now.addingTimeInterval(18000),
                    resetDescription: "raw local text"),
                secondary: nil,
                updatedAt: now)),
            fetchAttempts: [
                ProviderDiagnosticFetchAttempt(
                    kind: "api",
                    wasAvailable: true,
                    errorCategory: nil),
            ],
            error: nil,
            settings: ProviderDiagnosticSettingsSummary(sourceMode: .auto))

        let json = try self.json(export)

        #expect(json.contains("\"provider\""))
        #expect(json.contains("\"codex\""))
        #expect(json.contains("\"platform\""))
        #expect(json.contains("\"auth\""))
        #expect(json.contains("\"dataConfidence\""))
        #expect(json.contains("\"unknown\""))
        #expect(json.contains("\"hasResetDescription\""))
        #expect(!json.contains("sk-cp-"))
        #expect(!json.contains("sk-api-"))
        #expect(!json.contains("Bearer"))
        #expect(!json.contains("raw local text"))
        #expect(!json.contains("errorMessage"))
        #expect(!json.contains("localizedDescription"))
    }

    @Test
    func `diagnostic export carries generic detail sections`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [.makeSection(title: "Credits", rows: [
                .makeRow(label: "Credits used", value: "31", secondaryValue: "Resets in 1d"),
            ])],
            updatedAt: now)
        let summary = ProviderDiagnosticUsageSummary(from: snapshot)

        #expect(summary.detailSections == snapshot.details)
        #expect(summary.providerSpecificData.isEmpty)

        let json = try self.json(summary)
        #expect(json.contains("\"detailSections\""))
        #expect(json.contains("\"Credits used\""))
        #expect(json.contains("31"))
    }

    @Test
    func `diagnostic export decodes legacy schema without platform metadata`() throws {
        let export = ProviderDiagnosticExport(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            provider: "codex",
            displayName: "Codex",
            source: "api",
            sourceMode: "auto",
            auth: ProviderDiagnosticAuthSummary(configured: true, modes: ["api"]),
            usage: nil,
            fetchAttempts: [],
            error: nil,
            settings: ProviderDiagnosticSettingsSummary(sourceMode: .auto))
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(self.json(export).utf8)) as? [String: Any])
        object.removeValue(forKey: "platform")
        object.removeValue(forKey: "appVersion")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            ProviderDiagnosticExport.self,
            from: JSONSerialization.data(withJSONObject: object))

        #expect(decoded.platform == ProviderDiagnosticPlatform.current)
        #expect(decoded.appVersion == nil)
    }

    @Test
    func `usage snapshot defaults legacy payloads to unknown confidence without reencoding unknown`() throws {
        let json = """
        {
          "primary": {
            "usedPercent": 42,
            "windowMinutes": 300,
            "hasResetDescription": false
          },
          "secondary": null,
          "tertiary": null,
          "updatedAt": "2023-11-14T22:13:20Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.dataConfidence == .unknown)

        let encoded = try self.json(snapshot)
        #expect(!encoded.contains("dataConfidence"))
    }

    @Test
    func `usage snapshot preserves explicit confidence through Codable`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 12,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(18000),
                resetDescription: nil),
            secondary: nil,
            updatedAt: now,
            dataConfidence: .exact)

        let encoded = try self.json(snapshot)
        #expect(encoded.contains("\"dataConfidence\" : \"exact\""))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UsageSnapshot.self, from: Data(encoded.utf8))
        #expect(decoded.dataConfidence == .exact)
    }

    @Test
    func `usage snapshot treats future confidence values as unknown`() throws {
        let json = """
        {
          "primary": null,
          "secondary": null,
          "tertiary": null,
          "updatedAt": "2023-11-14T22:13:20Z",
          "dataConfidence": "future"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UsageSnapshot.self, from: Data(json.utf8))

        #expect(snapshot.dataConfidence == .unknown)
        #expect(try !self.json(snapshot).contains("dataConfidence"))
    }

    @Test
    func `diagnostic usage summary includes confidence`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = ProviderDiagnosticUsageSummary(from: UsageSnapshot(
            primary: RateWindow(
                usedPercent: 12,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(18000),
                resetDescription: nil),
            secondary: nil,
            updatedAt: now,
            dataConfidence: .exact))

        #expect(summary.dataConfidence == "exact")
    }

    @Test
    func `diagnostic usage summary defaults legacy payloads to unknown confidence`() throws {
        let json = """
        {
          "updatedAt": "2023-11-14T22:13:20Z",
          "windows": [],
          "extraWindowCount": 0,
          "providerCostPresent": false,
          "providerSpecificData": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let summary = try decoder.decode(
            ProviderDiagnosticUsageSummary.self,
            from: Data(json.utf8))

        #expect(summary.dataConfidence == "unknown")
        #expect(try self.json(summary).contains("\"dataConfidence\" : \"unknown\""))
    }

    @Test
    func `unwired provider diagnostics remain unknown confidence`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let usage = UsageSnapshot(
            primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: now)
        let summary = ProviderDiagnosticUsageSummary(from: usage)

        #expect(usage.dataConfidence == .unknown)
        #expect(summary.dataConfidence == "unknown")
        #expect(summary.windows.first?.usedPercent == 25)
    }

    @Test
    func `diagnostic export marks named windows with unknown usage`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = ProviderDiagnosticUsageSummary(from: UsageSnapshot(
            primary: nil,
            secondary: nil,
            extraRateWindows: [
                NamedRateWindow(
                    id: "nebula-window",
                    title: "Nebula Window",
                    window: RateWindow(
                        usedPercent: 100,
                        windowMinutes: nil,
                        resetsAt: now.addingTimeInterval(3600),
                        resetDescription: nil),
                    usageKnown: false),
            ],
            updatedAt: now))

        let json = try self.json(summary)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let windows = try #require(object["windows"] as? [[String: Any]])

        #expect(windows.first?["usageKnown"] as? Bool == false)
    }

    @Test
    func `diagnostic rate window defaults legacy payloads to known usage`() throws {
        let json = """
        {
          "label": "Legacy Window",
          "usedPercent": 42,
          "hasResetDescription": false
        }
        """

        let window = try JSONDecoder().decode(
            ProviderDiagnosticRateWindow.self,
            from: Data(json.utf8))

        #expect(window.usageKnown)
    }

    @Test
    func `raw error text never appears in encoded JSON`() throws {
        let export = ProviderDiagnosticExport(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            provider: "grok",
            displayName: "Grok",
            source: "failed",
            sourceMode: "auto",
            auth: ProviderDiagnosticAuthSummary(configured: true, modes: ["api"]),
            usage: nil,
            fetchAttempts: [
                ProviderDiagnosticFetchAttempt(
                    kind: "api",
                    wasAvailable: true,
                    errorCategory: "network"),
            ],
            error: ProviderDiagnosticError(
                category: "network",
                safeDescription: "Network error - check your connection"),
            settings: ProviderDiagnosticSettingsSummary(sourceMode: .auto))

        let json = try self.json(export)

        #expect(!json.contains("connection refused"))
        #expect(!json.contains("network probe"))
        #expect(!json.contains("not safe to expose"))
        #expect(!json.contains("localizedDescription"))
        #expect(!json.contains("raw"))
        #expect(!json.contains("errorMessage"))
        #expect(json.contains("errorCategory"))
        #expect(json.contains("\"network\""))
    }

    @Test(arguments: [
        (ProviderFetchClassifiedError.Kind.authenticationExpired, "auth"),
        (.missingCredential, "auth"),
        (.permissionDenied, "auth"),
        (.rateLimited, "api"),
        (.providerUnavailable, "api"),
        (.apiFailure, "api"),
        (.parseFailure, "parse"),
        (.networkFailure, "network"),
    ])
    func `diagnostic error maps classified fetch failures`(kind: ProviderFetchClassifiedError.Kind, category: String) {
        let error = ProviderFetchClassifiedError(kind: kind, message: "fixture detail")

        let diagnostic = ProviderDiagnosticError(from: error, authConfigured: true)

        #expect(diagnostic.category == category)
        #expect(!diagnostic.safeDescription.contains("fixture detail"))
    }

    @Test
    func `no available strategy maps missing auth to auth category`() {
        let error = ProviderFetchError.noAvailableStrategy(.grok)
        let diag = ProviderDiagnosticError(from: error, authConfigured: false)

        #expect(diag.category == "auth")
        #expect(diag.safeDescription.contains("Authentication"))
    }

    @Test
    func `available failed strategy does not imply auth is configured`() {
        let outcome = ProviderFetchOutcome(
            result: .failure(ProviderFetchError.noAvailableStrategy(.cursor)),
            attempts: [
                ProviderFetchAttempt(
                    strategyID: "cursor.local",
                    kind: .localProbe,
                    wasAvailable: true,
                    errorDescription: "unauthenticated local probe"),
            ])

        let summary = ProviderDiagnosticAuthSummary(configured: false, modes: []).resolved(with: outcome)

        #expect(!summary.configured)
        #expect(summary.modes.isEmpty)
    }

    @Test
    func `fetch attempt error maps to safe category, never raw text`() {
        let attemptWithRawError = ProviderFetchAttempt(
            strategyID: "grok.api",
            kind: .apiToken,
            wasAvailable: true,
            errorDescription: "Grok API timeout after 30 seconds - connection refused for host example.invalid")
        let diagAttempt = ProviderDiagnosticFetchAttempt(from: attemptWithRawError)
        #expect(diagAttempt.kind == "api")
        #expect(diagAttempt.wasAvailable == true)
        let errorCategoryOne = diagAttempt.errorCategory
        #expect(errorCategoryOne == "network")
        let cat1 = errorCategoryOne ?? ""
        #expect(!cat1.contains("timeout"))
        #expect(!cat1.contains("connection refused"))
        #expect(!cat1.contains("example.invalid"))

        let attemptWithAuthError = ProviderFetchAttempt(
            strategyID: "grok.web",
            kind: .web,
            wasAvailable: false,
            errorDescription: "invalid auth token cookie HERTZ-SESSION=abc123")
        let diagAuthAttempt = ProviderDiagnosticFetchAttempt(from: attemptWithAuthError)
        #expect(diagAuthAttempt.wasAvailable == false)
        let errorCategoryTwo = diagAuthAttempt.errorCategory
        #expect(errorCategoryTwo == "auth")
        let cat2 = errorCategoryTwo ?? ""
        #expect(!cat2.contains("HERTZ-SESSION"))
    }

    @Test
    func `missing api key setup errors map to auth before api`() {
        let category = ProviderDiagnosticFetchAttempt.errorCategoryLabel(
            "Provider API key not configured. Set PROVIDER_API_KEY.")

        #expect(category == "auth")
    }

    @Test
    func `builder creates generic safe diagnostic with error on failure`() {
        let outcome = ProviderFetchOutcome(
            result: .failure(ProviderFetchClassifiedError(kind: .networkFailure, message: "timeout")),
            attempts: [
                ProviderFetchAttempt(
                    strategyID: "grok.api",
                    kind: .apiToken,
                    wasAvailable: true,
                    errorDescription: "timeout"),
            ])

        let diag = ProviderDiagnosticExportBuilder.build(.init(
            provider: .grok,
            descriptor: ProviderDescriptorRegistry.descriptor(for: .grok),
            outcome: outcome,
            sourceMode: .auto,
            settings: nil,
            auth: ProviderDiagnosticAuthSummary(configured: true, modes: ["apiToken"]),
            appVersion: "9.8.7"))

        #expect(diag.provider == "grok")
        #expect(diag.platform == ProviderDiagnosticPlatform.current)
        #expect(diag.appVersion == "9.8.7")
        #expect(diag.source == "failed")
        #expect(diag.auth.configured == true)
        #expect(diag.usage == nil)
        #expect(diag.error != nil)
        #expect(diag.error?.category == "network")
        #expect(diag.fetchAttempts.count == 1)
        #expect(diag.fetchAttempts[0].errorCategory == "network")
    }

    @Test
    func `builder creates generic safe diagnostic on success`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: now)

        let result = ProviderFetchResult(
            usage: snapshot,
            credits: nil,
            dashboard: nil,
            sourceLabel: "api",
            strategyID: "grok.api",
            strategyKind: .apiToken)

        let outcome = ProviderFetchOutcome(
            result: .success(result),
            attempts: [
                ProviderFetchAttempt(
                    strategyID: "grok.api",
                    kind: .apiToken,
                    wasAvailable: true,
                    errorDescription: nil),
            ])

        let diag = ProviderDiagnosticExportBuilder.build(.init(
            provider: .grok,
            descriptor: ProviderDescriptorRegistry.descriptor(for: .grok),
            outcome: outcome,
            sourceMode: .auto,
            settings: nil,
            auth: ProviderDiagnosticAuthSummary(configured: true, modes: ["apiToken"])))

        #expect(diag.provider == "grok")
        #expect(diag.source == "api")
        #expect(diag.auth.configured == true)
        #expect(diag.usage != nil)
        #expect(diag.error == nil)

        #expect(diag.usage?.detailSections == snapshot.details)
    }

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
