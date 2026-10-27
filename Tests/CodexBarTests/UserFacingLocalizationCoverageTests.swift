import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct UserFacingLocalizationCoverageTests {
    @Test
    func `OpenAI credential scope captions are translated and preserve the account label`() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CodexBar/Resources")
        let accountKey = "Applies to the selected token account “%@”. Each account keeps its own limits."
        let providerKey = "Applies to the OpenAI API key, not to token accounts."
        let languages = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
        #expect(languages.count == 23)
        for language in languages {
            let identifier = language.deletingPathExtension().lastPathComponent
            let source = try String(contentsOf: language.appendingPathComponent("Localizable.strings"), encoding: .utf8)
            #expect(source.contains("\"\(accountKey)\" ="))
            #expect(source.contains("\"\(providerKey)\" ="))
            CodexBarLocalizationOverride.$appLanguage.withValue(identifier) {
                let account = L(accountKey, "Synthetic Account")
                let provider = L(providerKey)
                #expect(account.contains("Synthetic Account"))
                #expect(!account.contains("%@"))
                if identifier != "en" {
                    #expect(account != accountKey.replacingOccurrences(of: "%@", with: "Synthetic Account"))
                    #expect(provider != providerKey)
                }
            }
        }
    }

    @Test
    func `selected user-facing UI surfaces avoid raw English literals`() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let forbiddenMarkersByFile: [String: [String]] = [
            "Sources/CodexBar/Menu/CostHistoryChartMenuView.swift": [
                ".value(\"Day\"",
                ".value(\"Cost\"",
                ".value(\"Cap start\"",
                ".value(\"Cap end\"",
            ],
            "Sources/CodexBar/Menu/CreditsHistoryChartMenuView.swift": [
                ".value(\"Day\"",
                ".value(\"Credits used\"",
                ".value(\"Cap start\"",
                ".value(\"Cap end\"",
                "Text(\"Total (30d):",
                "\\(total) credits",
                "\\(used) credits",
            ],
            "Sources/CodexBar/Menu/PlanUtilizationHistoryChartMenuView.swift": [
                ".value(\"Series\"",
                ".value(\"Capacity Start\"",
                ".value(\"Capacity End\"",
                ".value(\"Utilization Start\"",
                ".value(\"Utilization End\"",
            ],
            "Sources/CodexBar/Providers/JetBrains/JetBrainsLoginFlow.swift": [
                "                \"Install a JetBrains IDE with AI Assistant enabled, then refresh CodexBar.\",",
                "                \"Alternatively, set a custom path in Settings.\",",
                "title: \"No JetBrains IDE detected\"",
            ],
            "Sources/CodexBar/Providers/Codex/PreferencesCodexAccountsSection.swift": [
                "?? \"No system account\"",
                "return \"Adding Account…\"",
                "return \"Add Account\"",
                "return \"Re-authenticating…\"",
                "return \"Re-auth\"",
                "ProviderSettingsSection(title: \"Accounts\")",
                "Text(\"Active\")",
                "Text(\"Choose which Codex account CodexBar should follow.\")",
                "Text(\"Account\")",
                "Text(\"No Codex accounts detected yet.\")",
                "Text(\"System\")",
                "Text(\"The default Codex account on this Mac.\")",
                "Text(\"(System)\")",
                "Button(\"Remove\")",
            ],
            "Sources/CodexBar/Settings/PreferencesProviderDetailView.swift": [
                ".help(\"Refresh\")",
                "accessibilityLabel: \"Usage used\"",
            ],
            "Sources/CodexBar/Settings/PreferencesProviderErrorView.swift": [
                ".help(\"Copy error\")",
            ],
            "Sources/CodexBar/Settings/PreferencesSpendDashboardPane.swift": [
                "Text(\"Model breakdown unavailable\")",
                "Text(\"Partial model breakdown\")",
                "Text(\"Partial estimate\")",
            ],
            "Sources/CodexBar/Settings/PreferencesProviderSettingsRows.swift": [
                "Text(self.title)",
                "Text(self.toggle.title)",
                "Text(self.toggle.subtitle)",
                "Button(action.title)",
                "Text(self.picker.title)",
                "Text(option.title)",
                "Text(trimmedTitle)",
                "Text(trimmedSubtitle)",
                "Text(self.descriptor.title)",
                "Text(self.descriptor.subtitle)",
                "Text(\"No token accounts yet.\")",
                "Button(\"Remove\")",
                "TextField(\"Label\"",
                "Button(\"Add\")",
                "TextField(\"Org ID (optional)\"",
                ".help(\"Optional organization ID for accounts linked to multiple Anthropic organizations.\")",
                "Button(\"Open token file\")",
                "Button(\"Reload\")",
                "Text(\"No organizations loaded. Click Refresh after setting your API key.\")",
                "Button(\"Refresh organizations\")",
            ],
            "Sources/CodexBar/Settings/PreferencesSidebar.swift": [
                "\"Disabled —",
                ".accessibilityLabel(\"Sort",
            ],
            "Sources/CodexBar/StatusItem/StatusItemController+CostMenuCard.swift": [
                "static let costMenuTitle",
            ],
            "Sources/CodexBar/Menu/UsageBreakdownChartMenuView.swift": [
                ".value(\"Day\"",
                ".value(\"Credits used\"",
                ".value(\"Service\"",
                ".value(\"Cap start\"",
                ".value(\"Cap end\"",
            ],
        ]

        var violations: [String] = []
        for (relativePath, markers) in forbiddenMarkersByFile.sorted(by: { $0.key < $1.key }) {
            let source = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
            for marker in markers where source.contains(marker) {
                violations.append("\(relativePath): \(marker)")
            }
        }

        #expect(
            violations.isEmpty,
            "Raw user-facing localization markers remain:\n\(violations.joined(separator: "\n"))")
    }

    @Test
    func `provider detail localization preserves technical identifiers`() throws {
        let details = try [
            ProviderDetailSection(
                title: "Usage",
                rows: [
                    .init(label: "Balance", value: "$12.34"),
                    .init(label: "Top model", value: "deepseek-v4-flash"),
                ],
                chart: .init(
                    kind: .bars,
                    title: "Usage",
                    unit: "tokens",
                    points: [.init(label: "2026-08-20", value: 42)])),
        ]

        let localized = CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            UsageMenuCardView.Model.localizedProviderDetails(details, provider: .deepseek)
        }

        let section = try #require(localized.first)
        #expect(section.title == "用量")
        #expect(section.rows.map(\.label) == ["余额", "最常用模型"])
        #expect(section.rows.map(\.value) == ["$12.34", "deepseek-v4-flash"])
        #expect(section.chart?.title == "用量")
        #expect(section.chart?.unit == "token")
        #expect(section.chart?.points.first?.label == "2026-08-20")
    }

    @Test
    func `kiro cap phrases localize of prefixes`() throws {
        let details = try [
            ProviderDetailSection(
                title: "Usage",
                rows: [
                    .init(label: "Overage usage", value: "3603.49 credits", secondaryValue: "of 10000"),
                    .init(label: "Overage cost", value: "$144.14", secondaryValue: "of $400.00"),
                ]),
        ]

        let localized = CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            UsageMenuCardView.Model.localizedProviderDetails(details, provider: .kiro)
        }

        let section = try #require(localized.first)
        #expect(section.rows.map(\.label) == ["超额用量", "超额费用"])
        #expect(section.rows.map(\.value) == ["3603.49 额度", "$144.14"])
        #expect(section.rows.map(\.secondaryValue) == ["/ 10000", "/ $400.00"])
    }

    @Test
    func `spend dashboard model breakdown state stays precise and localized`() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root
                .appendingPathComponent("Sources/CodexBar/SpendDashboard/SpendDashboardProviderBreakdown.swift"),
            encoding: .utf8)

        #expect(source.contains(#"self.modelHistoryState(L("Model breakdown unavailable"))"#))
        #expect(source.contains(#"L("Partial model breakdown")"#))
        #expect(source.contains(#"self.modelHistoryState(L("No model-level history"))"#))
    }

    @Test
    func `hourly chart accessibility retains localized plurals`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(spendDashboardHourlyChartAccessibilityValue(hourCount: 1, serviceCount: 1)
                == "1 hour of usage data across 1 service")
            #expect(spendDashboardHourlyChartAccessibilityValue(hourCount: 2, serviceCount: 1)
                == "2 hours of usage data across 1 service")
            #expect(spendDashboardHourlyChartAccessibilityValue(hourCount: 1, serviceCount: 2)
                == "1 hour of usage data across 2 services")
            #expect(spendDashboardHourlyChartAccessibilityValue(hourCount: 2, serviceCount: 2)
                == "2 hours of usage data across 2 services")
        }
    }
}
