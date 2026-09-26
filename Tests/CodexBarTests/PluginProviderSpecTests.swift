import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct PluginProviderSpecTests {
    private static let providers: [UsageProvider] = [
        .xkiro,
        .atlascloud,
        .vercel,
        .devpass,
        .gitkraken,
        .poe,
        .deepinfra,
        .zenmux,
        .clinepass,
        .aiand,
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
                    provider: provider,
                    metadata: metadata)).detailLine(fixture.presentationContext(
                    provider: provider,
                    metadata: metadata)),
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
                    provider: provider,
                    settings: fixture.settings,
                    environment: [:]))
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
        ]
        let data = try JSONSerialization.data(withJSONObject: baseline, options: [.prettyPrinted, .sortedKeys])
        let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/plugin-provider-specs.json")
        let fixtureData = try Data(contentsOf: golden)
        let fixtureObject = try JSONSerialization.jsonObject(with: fixtureData)
        let normalizedFixture = try JSONSerialization.data(withJSONObject: fixtureObject, options: [.prettyPrinted, .sortedKeys])
        #expect(data == normalizedFixture)
    }

    @Test
    func `API key aliases skip empty values and clean quotes`() {
        let spec = PluginProviderSpec(
            id: .xkiro,
            displayName: "Fixture",
            sessionLabel: "Daily",
            weeklyLabel: "Weekly",
            dashboardURL: "https://example.com",
            color: .init(hex: 0x123456),
            confetti: [0x123456, 0x654321],
            noDataMessage: "No history",
            environmentKey: "FIXTURE_KEY",
            environmentAliases: ["FIXTURE_ALIAS"])
        #expect(spec.apiKey(environment: [:]) == nil)
        #expect(spec.apiKey(environment: ["FIXTURE_KEY": "  ", "FIXTURE_ALIAS": " 'alias' "]) == "alias")
        #expect(spec.apiKey(environment: ["FIXTURE_KEY": " primary ", "FIXTURE_ALIAS": "alias"]) == "primary")
    }

    private static func components(_ color: ProviderColor) -> [Double] {
        [color.red, color.green, color.blue]
    }

    @Test
    func `pilot pipelines keep their credential boundaries without prototype flags`() async throws {
        let keys: [UsageProvider: String] = [
            .xkiro: "XKIRO_API_KEY",
            .atlascloud: "ATLASCLOUD_API_KEY",
            .vercel: "AI_GATEWAY_API_KEY",
            .devpass: "DEVPASS_API_KEY",
            .gitkraken: "GITKRAKEN_API_TOKEN",
            .poe: "POE_API_KEY",
            .deepinfra: "DEEPINFRA_API_KEY",
            .zenmux: "ZENMUX_MANAGEMENT_API_KEY",
            .clinepass: "CLINE_API_KEY",
            .aiand: "AIAND_API_KEY",
        ]
        for (provider, key) in keys {
            let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
            let context = ProviderCutoverTestSupport.context(environment: [key: " 'fixture-key' "])
            let strategies = await descriptor.fetchPlan.pipeline.resolveStrategies(context)
            #expect(strategies.map(\.id) == ["\(provider.rawValue).js"])
            let strategy = try #require(strategies.first)
            #expect(await strategy.isAvailable(context))
            #expect(await !strategy.isAvailable(ProviderCutoverTestSupport.context(
                environment: ["OTHER_API_KEY": "fixture-key"])))
            #expect(descriptor.credentials?.resolveToken(environment: context.env)?.token == "fixture-key")
            #expect(descriptor.fetchPlan.sourceModes == [.auto, .api])
        }
    }

    @Test
    func `custom budgets and settings destinations stay explicit`() {
        #expect(AtlasCloudProviderDescriptor.descriptor.menuBarMetrics == .automaticOnly)
        #expect(VercelProviderDescriptor.descriptor.menuBarMetrics == .automaticOnly)
        #expect(DeepInfraProviderDescriptor.spec.timeout == 145)
        #expect(ZenMuxProviderDescriptor.spec.timeout == 35)
        #expect(DevPassProviderDescriptor.spec.apiKeyField?.action?.url == "https://devpass.llmgateway.io/dashboard")
        #expect(ZenMuxProviderDescriptor.spec.apiKeyField?.action?.url == "https://zenmux.ai/platform/management")
        #expect(AiAndProviderDescriptor.spec.apiKeyField?.action?.url == "https://console.aiand.com")
    }
}
