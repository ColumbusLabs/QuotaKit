import Foundation
import SweetCookieKit
import Testing
@testable import CodexBar
@testable import CodexBarCore

private struct NewProviderSpecExpectation {
    let provider: UsageProvider
    let displayName: String
    let balanceOnly: Bool
    let allowsBurnDown: Bool
    let sourceModes: Set<ProviderSourceMode>
}

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
        .synthetic, .chutes, .v0, .elevenlabs, .neuralwatt, .clawrouter,
        .aixy, .bifrost, .deepgram, .llmproxy, .litellm, .sub2api, .llmman, .langdock,
    ]

    @Test
    func `browser-backed cookie guidance names supported browsers and manual alternative`() throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: #function)
        fixture.settings.debugDisableKeychainAccess = false
        let cookiePickers: [(UsageProvider, String)] = [
            (.museai, "Cookie source"),
            (.raycast, "Cookie source"),
            (.perplexity, "Cookie source"),
            (.kimi, "Cookie source"),
            (.ollama, "Cookie source"),
            (.copilot, "GitHub cookies"),
            (.zed, "Cookie source"),
        ]
        for (provider, title) in cookiePickers {
            let implementation = try #require(ProviderCatalog.implementation(for: provider))
            let picker = try #require(implementation.settingsPickers(
                context: fixture.settingsContext(provider: provider)).first(where: { $0.title == title }))
            picker.binding.wrappedValue = ProviderCookieSource.auto.rawValue
            let browsers = ProviderDefaults.metadata[provider]?.browserCookieOrder ?? Browser.defaultImportOrder
            let names = browsers.map(\.displayName).joined(separator: ", ")
            #expect(picker.subtitle.contains("Supported browsers: \(names). Use Manual for other browsers."))
            #expect(picker.dynamicSubtitle?()?.contains("Supported browsers: \(names).") == true)
        }
    }

    @Test
    func `plugin registration and settings preserve their baseline`() async throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: "PluginProviderSpecTests")
        var rows: [[String: Any]] = []
        for provider in Self.providers {
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
                "subscriptionDashboard": metadata.subscriptionDashboardURL ?? "",
                "creditsHint": metadata.creditsHint,
                "planLabels": metadata.sharePlanLabels,
                "apiKeyDebugLabel": descriptor.credentials?.apiKeyDebugLabel ?? "",
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
                "widgetColor": Self.components(descriptor.branding.widgetColor),
                "progressColor": String(describing: descriptor.branding.progressColorStyle),
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
            row["toggles"] = implementation.settingsToggles(context: fixture.settingsContext(provider: provider))
                .map { ["id": $0.id, "title": $0.title, "subtitle": $0.subtitle] }
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
            fixture.settings[providerConfig: provider, field: .apiKey] = ""
            var config = ProviderConfig(id: provider.instanceID, apiKey: "fixture-key", workspaceID: "fixture-project")
            config.enterpriseHost = "https://fixture.example.com"
            config.litellmModelUsageEnabled = true
            let projected = descriptor.credentials?.applyConfig(base: [:], config: config) ?? [:]
            row["projections"] = projected
            row["enterpriseHost"] = descriptor.config.supportsEnterpriseHost
            row["workspaceOrder"] = descriptor.config.workspaceIDValidationOrder as Any? ?? NSNull()
            row["projectToken"] = descriptor.credentials?.resolveToken(kind: .projectID, environment: projected)?
                .token ?? ""
            let keyOnly = descriptor.credentials?.applyConfig(
                base: [:], config: ProviderConfig(id: provider.instanceID, apiKey: "fixture-key")) ?? [:]
            config.enterpriseHost = "http://public.example.com"
            let invalid = descriptor.credentials?.applyConfig(base: [:], config: config) ?? [:]
            var availability: [[Bool]] = []
            for environment in [[:], keyOnly, projected, invalid] {
                let context = ProviderCutoverTestSupport.context(environment: environment)
                let strategies = await descriptor.fetchPlan.pipeline.resolveStrategies(context)
                await availability.append([
                    implementation.isAvailable(context: .init(
                        provider: provider, settings: fixture.settings, environment: environment)),
                    strategies.first?.isAvailable(context) ?? false,
                ])
            }
            row["environmentAvailability"] = availability
            if let support = descriptor.credentials?.tokenAccountSupport {
                row["tokenAccounts"] = [
                    "title": support.title,
                    "subtitle": support.subtitle,
                    "placeholder": support.placeholder,
                    "injection": support.envOverride(token: "fixture-account") ?? [:],
                    "delay": support.minimumDelayBetweenAccountRefreshes.map(String.init(describing:)) ?? "",
                ]
                fixture.settings.addTokenAccount(provider: provider, label: "Fixture", token: "fixture-account")
                row["accountAvailability"] = implementation.isAvailable(context: .init(
                    provider: provider, settings: fixture.settings, environment: [:]))
            }
            rows.append(row)
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
        let normalizedFixture = try JSONSerialization.data(
            withJSONObject: fixtureObject,
            options: [.prettyPrinted, .sortedKeys])
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
    func `new provider specs preserve quota and source semantics`() {
        let expected = [
            NewProviderSpecExpectation(
                provider: .tavily,
                displayName: "Tavily",
                balanceOnly: false,
                allowsBurnDown: true,
                sourceModes: [.auto, .api]),
            NewProviderSpecExpectation(
                provider: .linkup,
                displayName: "Linkup",
                balanceOnly: true,
                allowsBurnDown: false,
                sourceModes: [.auto, .api]),
            NewProviderSpecExpectation(
                provider: .tinyapi,
                displayName: "TinyApi",
                balanceOnly: true,
                allowsBurnDown: false,
                sourceModes: [.auto, .web]),
            NewProviderSpecExpectation(
                provider: .exa,
                displayName: "Exa",
                balanceOnly: false,
                allowsBurnDown: false,
                sourceModes: [.auto, .api]),
            NewProviderSpecExpectation(
                provider: .cosmic,
                displayName: "Cosmic AI",
                balanceOnly: false,
                allowsBurnDown: true,
                sourceModes: [.auto, .api]),
            NewProviderSpecExpectation(
                provider: .aerostack,
                displayName: "Aerostack",
                balanceOnly: false,
                allowsBurnDown: true,
                sourceModes: [.auto, .api]),
            NewProviderSpecExpectation(
                provider: .sailresearch,
                displayName: "Sail Research",
                balanceOnly: true,
                allowsBurnDown: false,
                sourceModes: [.auto, .api]),
            NewProviderSpecExpectation(
                provider: .sofya,
                displayName: "Sofya",
                balanceOnly: true,
                allowsBurnDown: false,
                sourceModes: [.auto, .api]),
        ]
        for expectation in expected {
            let descriptor = ProviderDescriptorRegistry.descriptor(for: expectation.provider)
            #expect(descriptor.metadata.displayName == expectation.displayName)
            #expect(descriptor.metadata.balanceOnly == expectation.balanceOnly)
            #expect(!descriptor.metadata.widgetSelectable)
            #expect(descriptor.snapshotExport.allowsWidgets == (expectation.provider != .exa))
            let allowsBurnDown = descriptor.snapshotExport.allowsWidgets &&
                descriptor.metadata.burnDownWidgetSelectable && !descriptor.metadata.balanceOnly
            #expect(allowsBurnDown == expectation.allowsBurnDown)
            #expect(!descriptor.metadata.defaultEnabled)
            #expect(descriptor.fetchPlan.sourceModes == expectation.sourceModes)
            #expect(descriptor.branding.iconResourceName == "ProviderIcon-\(expectation.provider.rawValue)")
            #expect(ProviderCatalog.implementation(for: expectation.provider) != nil)
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

extension PluginProviderSpecTests {
    @Test
    func `workspace bindings and project token resolution remain distinct`() throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: "PluginSpec-workspaces")
        for spec in [V0ProviderDescriptor.spec, DeepgramProviderDescriptor.spec] {
            let workspace = try #require(spec.workspaceField)
            let implementation = try #require(ProviderCatalog.implementation(for: spec.id))
            let field = try #require(implementation.settingsFields(context: fixture.settingsContext(provider: spec.id))
                .first { $0.id == workspace.field.id })
            field.binding.wrappedValue = "fixture-project"
            let config = try #require(fixture.settings.providerConfig(for: spec.id))
            #expect(config.workspaceID == "fixture-project")
            #expect(config.apiKey == nil)
            let environment = spec.makeDescriptor().credentials?.applyConfig(base: [:], config: config) ?? [:]
            #expect(environment[workspace.environmentKey] == "fixture-project")
            let project = spec.makeDescriptor().credentials?.resolveToken(kind: .projectID, environment: environment)
            #expect(project?.token == (workspace.resolvesProjectID ? "fixture-project" : nil))
        }
    }

    @Test
    func `endpoint fields share config projection and retain validation policies`() throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: "PluginSpec-endpoints")
        for spec in [
            AixyProviderDescriptor.spec, BifrostProviderDescriptor.spec, LLMProxyProviderDescriptor.spec,
            LiteLLMProviderDescriptor.spec, Sub2APIProviderDescriptor.spec, LLMManProviderDescriptor.spec,
        ] {
            let endpoint = try #require(spec.endpoint)
            let implementation = try #require(ProviderCatalog.implementation(for: spec.id))
            let fields = implementation.settingsFields(context: fixture.settingsContext(provider: spec.id))
            let field = try #require(fields.first { $0.id == endpoint.field.id })
            field.binding.wrappedValue = "https://fixture.example.com/v1"
            let config = try #require(fixture.settings.providerConfig(for: spec.id))
            #expect(config.enterpriseHost == "https://fixture.example.com/v1")
            let projected = spec.makeDescriptor().credentials?.applyConfig(base: [:], config: config) ?? [:]
            #expect(projected[endpoint.environmentKey] == "https://fixture.example.com/v1")
            #expect(endpoint.url(environment: projected)?.absoluteString == "https://fixture.example.com/v1")
            #expect(endpoint.url(environment: [endpoint.environmentKey: "http://public.example.com"]) == nil)
            #expect(endpoint
                .url(environment: [endpoint.environmentKey: "https://user:password@fixture.example.com"]) == nil)
        }
        #expect(AixyProviderDescriptor.spec.endpoint?.url(environment: [:]) == AixySettingsReader.defaultBaseURL)
        #expect(LLMManProviderDescriptor.spec.endpoint?.url(environment: [:]) == LLMManSettingsReader.defaultBaseURL)
        #expect(LLMManProviderDescriptor.spec.endpoint?.url(environment: ["LLMMAN_HOST": "localhost"])?
            .absoluteString == "http://localhost:17434")
    }

    @Test
    func `keyless daemon fetch and optional activity budget remain explicit`() throws {
        let context = ProviderCutoverTestSupport.context(environment: [:])
        let daemon = try #require(LLMManProviderDescriptor.spec.scriptValues(context))
        #expect(daemon.secrets.isEmpty)
        #expect(daemon.settings == ["LLMMAN_HOST": "http://127.0.0.1:17434"])
        #expect(LiteLLMProviderDescriptor.spec.scriptValues(context) == nil)
        #expect(LiteLLMProviderDescriptor.spec.fetchTimeout(environment: [:]) == ProviderPluginRuntime.defaultTimeout)
        #expect(LiteLLMProviderDescriptor.spec.fetchTimeout(environment: ["LITELLM_MODEL_USAGE_ENABLED": "true"]) == 40)
        #expect(LiteLLMProviderDescriptor.spec.fetchTimeout(environment: ["LITELLM_MODEL_USAGE_ENABLED": "false"]) ==
            ProviderPluginRuntime.defaultTimeout)
        let values = try #require(LiteLLMProviderDescriptor.spec.scriptValues(ProviderCutoverTestSupport.context(
            environment: ["LITELLM_API_KEY": "fixture-key", "LITELLM_BASE_URL": "https://fixture.example.com"])))
        #expect(values.settings["LITELLM_MODEL_USAGE_ENABLED"] == "false")
    }
}
