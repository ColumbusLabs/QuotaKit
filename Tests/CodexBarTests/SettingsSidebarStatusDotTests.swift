import CodexBarCore
import Testing
@testable import CodexBar

struct SettingsSidebarStatusDotTests {
    @Test
    func `Critical status describes provider service health`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarStatusDot.statusDescription(for: .critical)
                == "Provider service status: Critical issue")
        }
    }

    @Test
    func `Major status describes provider service health`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarStatusDot.statusDescription(for: .major)
                == "Provider service status: Major outage")
        }
    }

    @Test(arguments: [ProviderStatusIndicator.critical, .major, .none])
    func `Provider row announces visible service status`(indicator: ProviderStatusIndicator) {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: true,
                statusChecksEnabled: true,
                indicator: indicator) == "Codex — Provider service status: \(indicator.label)")
        }
    }

    @Test
    func `Disabled provider keeps its existing accessibility label`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: false,
                statusChecksEnabled: true,
                indicator: .critical) == "Codex — Disabled")
        }
    }

    @Test
    func `Provider row omits service status when status checks are off`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: true,
                statusChecksEnabled: false,
                indicator: .major) == "Codex")
        }
    }

    @Test
    func `Missing status is unknown rather than operational`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarStatusDot.statusDescription(for: nil)
                == "Provider service status: Status unknown")
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: true,
                statusChecksEnabled: true,
                indicator: nil) == "Codex — Provider service status: Status unknown")
        }
    }

    @Test
    func `Fetched healthy status remains operational`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarStatusDot.statusDescription(for: ProviderStatusIndicator.none)
                == "Provider service status: Operational")
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: true,
                statusChecksEnabled: true,
                indicator: ProviderStatusIndicator.none) == "Codex — Provider service status: Operational")
        }
    }
}
