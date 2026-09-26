import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

@MainActor
struct PluginProviderSpecTests {
    private static let providers: [UsageProvider] = [
        .xkiro, .atlascloud, .vercel, .devpass, .gitkraken, .poe, .deepinfra, .zenmux, .clinepass, .aiand,
    ]

    @Test
    func `pilot registration and settings preserve their baseline`() throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: "PluginProviderSpecTests")
        let rows = try Self.providers.map { provider -> [String: Any] in
            let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
            let metadata = descriptor.metadata
            let implementation = try #require(ProviderCatalog.implementation(for: provider))
            let fields = implementation.settingsFields(context: fixture.settingsContext(provider: provider))
            var row: [String: Any] = [
                "id": provider.rawValue,
                "name": metadata.displayName,
                "labels": [metadata.sessionLabel, metadata.weeklyLabel, metadata.opusLabel ?? ""],
                "toggle": metadata.toggleTitle,
                "cli": [descriptor.cli.name] + descriptor.cli.aliases,
                "dashboard": metadata.dashboardURL ?? "",
                "status": [metadata.statusPageURL ?? "", metadata.statusLinkURL ?? ""],
                "debug": metadata.debugLogUnavailableMessage ?? "",
                "flags": [
                    metadata.supportsOpus,
                    metadata.supportsCredits,
                    metadata.defaultEnabled,
                    metadata.widgetSelectable,
                    metadata.isPrimaryProvider,
                    metadata.usesAccountFallback,
                    metadata.balanceOnly,
                    metadata.usesDetailBackedWindow,
                ],
                "color": Self.components(descriptor.branding.color),
                "confetti": descriptor.branding.confettiPalette.map(Self.components),
                "icon": descriptor.branding.iconResourceName,
                "noData": descriptor.tokenCost.noDataMessage(),
                "detail": implementation.presentation(context: fixture.presentationContext(
                    provider: provider, metadata: metadata)).detailLine(fixture.presentationContext(
                    provider: provider, metadata: metadata)),
                "fields": fields.map { field -> [String: Any] in
                    [
                        "id": field.id,
                        "title": field.title,
                        "subtitle": field.subtitle,
                        "placeholder": field.placeholder as Any? ?? NSNull(),
                        "secure": field.kind == .secure,
                        "actions": field.actions.map { ["id": $0.id, "title": $0.title] },
                    ]
                },
            ]
            row["availability"] = ["", "  ", "fixture-key"].map { value in
                fixture.settings[providerConfig: provider, field: .apiKey] = value
                return implementation.isAvailable(context: .init(
                    provider: provider, settings: fixture.settings, environment: [:]))
            }
            for field in fields where field.kind == .secure {
                field.binding.wrappedValue = "bound-key"
                #expect(fixture.settings[providerConfig: provider, field: .apiKey] == "bound-key")
            }
            return row
        }
        let baseline: [String: Any] = [
            "providers": rows,
            "order": ProviderDescriptorRegistry.all.map(\.id.rawValue),
            "implementationOrder": ProviderCatalog.all.map(\.id.rawValue),
            "help": CodexBarCLI.rootHelp(version: "0.0.0"),
        ]
        let data = try JSONSerialization.data(withJSONObject: baseline, options: [.prettyPrinted, .sortedKeys])
        let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/plugin-provider-specs.json")
        #expect(try String(decoding: data, as: UTF8.self) == String(contentsOf: golden, encoding: .utf8))
    }

    @Test
    func `API key aliases skip empty values and clean quotes`() {
        let spec = PluginProviderSpec(
            id: .xkiro, displayName: "Fixture", sessionLabel: "Daily", weeklyLabel: "Weekly",
            dashboardURL: "https://example.com", color: .init(hex: 0x123456), confetti: [0x123456, 0x654321],
            noDataMessage: "No history", environmentKey: "FIXTURE_KEY", environmentAliases: ["FIXTURE_ALIAS"])
        #expect(spec.apiKey(environment: [:]) == nil)
        #expect(spec.apiKey(environment: ["FIXTURE_KEY": "  ", "FIXTURE_ALIAS": " 'alias' "]) == "alias")
        #expect(spec.apiKey(environment: ["FIXTURE_KEY": " primary ", "FIXTURE_ALIAS": "alias"]) == "primary")
    }

    private static func components(_ color: ProviderColor) -> [Double] {
        [color.red, color.green, color.blue]
    }
}
