import AppKit
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore
@testable import CodexBarWidget

// The exact-anchor catalog intentionally makes this test data file long.
// swiftlint:disable file_length

/// Provider architecture drift tripwire for honest mistakes by future contributors and AI agents.
///
/// This lexical scanner detects dotted provider cases, including qualified, labeled, and multiline statements, plus
/// lowercase raw provider-ID string literals in every single-statement position, including assignments, bare function
/// arguments, dictionary keys and values, array elements, and returns. It scans shipped Swift under `Sources/**` and
/// `WidgetExtension/**` and applies suppressions to exact provider tokens rather than whole statements.
///
/// Dotted provider cases that require real expression parsing, including implicit closure returns and closure-body
/// dataflow, are intentionally out of scope. String concatenation, reflection, and dynamic lookup are also out of
/// scope, as are `Tests/**` and non-Swift files. This test is a lexical drift tripwire for honest mistakes, not an
/// adversarially complete analyzer. If in-the-wild drift starts slipping past it, the concrete upgrade path is a
/// SwiftSyntax-based implementation that can model expressions and dataflow instead of extending these heuristics.
@MainActor
// swiftlint:disable:next type_body_length
struct ProviderArchitectureGatekeeperTests {
    private static let postBaselineProviders: Set<UsageProvider> = [
        .bifrost, .devpass, .aixy, .xkiro, .raycast, .helmcode, .typesafe,
        .atlascloud, .vercel, .llmman, .nous, .muse, .pi, .museai, .lithosai, .workbuddy, .langdock, .xapi,
    ]
    @Test
    func `every provider has descriptor and implementation manifest entries`() {
        let expected = Set(UsageProvider.allCases)
        let descriptors = Set(ProviderDescriptorRegistry.all.map(\.id))
        let implementations = Set(ProviderImplementationRegistry.all.map(\.id))
        let missingDescriptors = expected.subtracting(descriptors).map(\.rawValue).sorted()
        let missingImplementations = expected.subtracting(implementations).map(\.rawValue).sorted()

        #expect(
            missingDescriptors.isEmpty,
            "Missing descriptor manifest entries: \(missingDescriptors.joined(separator: ", "))")
        #expect(
            missingImplementations.isEmpty,
            "Missing implementation manifest entries: \(missingImplementations.joined(separator: ", "))")
    }

    @Test
    func `credential adapters self report capabilities through descriptors`() {
        for descriptor in ProviderDescriptorRegistry.all {
            guard let adapter = descriptor.credentials else { continue }

            #expect(
                ProviderConfigEnvironment.supportsAPIKeyOverride(for: descriptor.id) ==
                    adapter.supportsAPIKeyOverride,
                "API-key capability drifted for \(descriptor.id.rawValue).")
            #expect(
                (TokenAccountSupportCatalog.support(for: descriptor.id) != nil) ==
                    (adapter.tokenAccountSupport != nil),
                "Token-account capability drifted for \(descriptor.id.rawValue).")
        }
    }

    @Test
    func `every provider can produce and read its registered settings section`() {
        let settings = testSettingsStore(suiteName: "ProviderArchitectureGatekeeperTests-settings-sections")
        let context = ProviderSettingsSnapshotContext(settings: settings, tokenOverride: nil)
        var builder = ProviderSettingsSnapshotBuilder()

        for implementation in ProviderImplementationRegistry.all {
            let providerName = implementation.id.rawValue
            let registration = ProviderDescriptorRegistry.descriptor(for: implementation.id).settingsSection
            guard let contribution = implementation.settingsSnapshot(context: context) else {
                Issue.record("Missing settings-section contribution for provider '\(providerName)'.")
                continue
            }
            #expect(
                registration.accepts(contribution),
                "Settings-section registration does not match provider '\(providerName)'.")
            builder.apply(contribution)
        }

        let snapshot = builder.build()
        for descriptor in ProviderDescriptorRegistry.all {
            #expect(
                descriptor.settingsSection.canRead(from: snapshot),
                "Could not read settings section for provider '\(descriptor.id.rawValue)'.")
        }
    }

    @Test
    func `empty settings snapshot factory has no provider sections`() {
        let snapshot = ProviderSettingsSnapshot.make()

        #expect(snapshot.abacus == nil)
        #expect(!snapshot.debugMenuEnabled)
        #expect(!snapshot.debugKeepCLISessionsAlive)
    }

    @Test
    func `every provider descriptor has a loadable SVG resource`() throws {
        let resources = try Self.repoRoot()
            .appending(path: "Sources/CodexBar/Resources", directoryHint: .isDirectory)

        for descriptor in ProviderDescriptorRegistry.all {
            let resourceName = descriptor.branding.iconResourceName
            let url = resources.appending(path: "\(resourceName).svg")
            #expect(
                FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
                "Missing SVG for \(descriptor.id.rawValue): \(resourceName).svg")
            #expect(NSImage(contentsOf: url) != nil, "Could not load \(resourceName).svg as NSImage")
        }
    }

    @Test
    func `widget provider choices match selectable descriptor metadata`() {
        let selectable = Set(ProviderDescriptorRegistry.all.filter(\.metadata.widgetSelectable).map(\.id))
        let choices = Set(ProviderChoice.allCases.map(\.provider))
        let missing = selectable.subtracting(choices).map(\.rawValue).sorted()
        let unexpected = choices.subtracting(selectable).map(\.rawValue).sorted()

        #expect(
            missing.isEmpty,
            "Missing ProviderChoice cases for widget-selectable providers: \(missing.joined(separator: ", "))")
        #expect(
            unexpected.isEmpty,
            "ProviderChoice cases marked non-selectable in descriptor metadata: \(unexpected.joined(separator: ", "))")
    }

    @Test
    func `widget short labels preserve compact provider names`() {
        let overrides: [UsageProvider: String] = [
            .antigravity: "Anti",
            .alibabatokenplan: "Token Plan",
            .vertexai: "Vertex",
            .perplexity: "Pplx",
            .mimo: "MiMo",
            .sakana: "Sakana",
            .abacus: "Abacus",
            .bedrock: "Bedrock",
            .jetbrains: "JetBrains",
            .moonshot: "Moonshot",
            .nous: "Nous",
        ]
        for descriptor in ProviderDescriptorRegistry.all {
            let expected = overrides[descriptor.id] ?? descriptor.metadata.displayName
            #expect(
                descriptor.metadata.shortDisplayName == expected,
                "Unexpected widget short label for \(descriptor.id.rawValue).")
        }
    }

    @Test
    func `descriptor widget colors preserve the reviewed palette`() {
        var widgetFingerprint: UInt64 = 1_469_598_103_934_665_603
        var burnDownFingerprint = widgetFingerprint
        let legacyDescriptors = ProviderDescriptorRegistry.all.filter {
            !Self.postBaselineProviders.contains($0.id)
        }
        for descriptor in legacyDescriptors {
            Self.hash(descriptor.id.rawValue.utf8, into: &widgetFingerprint)
            Self.hash(descriptor.branding.widgetColor, into: &widgetFingerprint)
            Self.hash(descriptor.id.rawValue.utf8, into: &burnDownFingerprint)
            Self.hash(descriptor.branding.burnDownWidgetColor, into: &burnDownFingerprint)
        }

        // Reviewed providers now share their menu accent; pin the rest of the widget palette.
        #expect(widgetFingerprint == 15_257_423_529_364_337_610)
        #expect(burnDownFingerprint == 13_248_577_987_729_422_950)

        let museAI = ProviderDescriptorRegistry.descriptor(for: .museai).branding
        #expect(museAI.widgetColor.hexString == "#0668E1")
        #expect(museAI.burnDownWidgetColor.hexString == "#999999")
        let workBuddy = ProviderDescriptorRegistry.descriptor(for: .workbuddy).branding
        #expect(workBuddy.widgetColor.hexString == "#0DD2A6")
        #expect(workBuddy.burnDownWidgetColor.hexString == "#999999")
        let xapi = ProviderDescriptorRegistry.descriptor(for: .xapi).branding
        #expect(xapi.widgetColor.hexString == "#71767B")
        // Balance-only X API has no burndown lane; retain the default ineligible color.
        #expect(xapi.burnDownWidgetColor.hexString == "#999999")
    }

    @Test
    func `descriptor unavailable debug messages preserve the legacy table`() throws {
        let descriptors = ProviderDescriptorRegistry.all.filter {
            $0.metadata.debugLogUnavailableMessage != nil && !Self.postBaselineProviders.contains($0.id)
        }
        var fingerprint: UInt64 = 1_469_598_103_934_665_603
        for descriptor in descriptors {
            Self.hash(descriptor.id.rawValue.utf8, into: &fingerprint)
            try Self.hash(#require(descriptor.metadata.debugLogUnavailableMessage?.utf8), into: &fingerprint)
        }

        #expect(descriptors.count == 38)
        #expect(fingerprint == 2_208_147_801_202_684_136)
    }

    @Test
    func `debug pane provider curation preserves legacy membership and order`() {
        let descriptors = ProviderDescriptorRegistry.all
        let ordered: ((ProviderDebugPaneCapabilities) -> Int?) -> [UsageProvider] = { rank in
            descriptors.compactMap { descriptor -> (UsageProvider, Int)? in
                guard let value = rank(descriptor.metadata.debugPane) else { return nil }
                return (descriptor.id, value)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        }

        #expect(ordered { $0.probeLogOrder } == [.codex, .claude, .cursor, .augment, .amp, .ollama])
        #expect(ordered { $0.notificationSimulationOrder } == [.codex, .claude])
        #expect(ordered { $0.errorSimulationOrder } == [
            .codex, .claude, .gemini, .antigravity, .augment, .amp, .t3chat, .zoommate, .ollama,
        ])
    }

    @Test
    func `small provider capabilities preserve legacy registries`() {
        let descriptors = ProviderDescriptorRegistry.all
        #expect(Set(descriptors.filter(\.metadata.balanceOnly).map(\.id)) == [
            .deepseek, .deepinfra, .moonshot, .poe, .hyper, .atlascloud, .vercel, .lithosai, .xapi,
        ])
        #expect(Set(descriptors.filter(\.metadata.usesDetailBackedWindow).map(\.id)) == [
            .perplexity, .warp, .kilo, .mistral, .deepseek, .deepinfra, .qoder, .chutes,
            .litellm, .longcat, .v0, .bifrost, .aixy, .raycast, .llmman, .manus, .mimo, .neuralwatt, .abacus,
            .workbuddy,
        ])
        #if os(macOS)
        // Antigravity joined via the tokscale-compatible local usage reader.
        #expect(Set(descriptors.filter(\.tokenCost.supportsTokenSnapshot).map(\.id)) == [
            .codex, .claude, .cursor, .vertexai, .bedrock, .antigravity, .muse, .pi,
        ])
        #else
        #expect(Set(descriptors.filter(\.tokenCost.supportsTokenSnapshot).map(\.id)) == [
            .codex, .claude, .vertexai, .bedrock, .antigravity, .muse, .pi,
        ])
        #endif
        #expect(Set(descriptors.filter { $0.cli.binaryLocator != nil }.map(\.id)) == [
            .codex, .claude, .gemini,
        ])
        #expect(descriptors.compactMap { descriptor in
            descriptor.credentials?.apiKeyDebugLabel.map { (descriptor.id, $0) }
        }.map(\.0) == [.openai, .azureopenai, .opencodego, .openrouter, .elevenlabs, .v0, .hyper])

        #expect(CodexProviderDescriptor.descriptor.tokenCost.menuHintLines == [.localized("codex_api_estimate_hint")])
        #expect(ClaudeProviderDescriptor.descriptor.tokenCost.menuHintLines == [.estimate])
        #expect(CursorProviderDescriptor.descriptor.tokenCost.menuHintLines == [.estimate])
        #expect(VertexAIProviderDescriptor.descriptor.tokenCost.menuHintLines == [.localized("cost_estimate_hint")])
        #expect(BedrockProviderDescriptor.descriptor.tokenCost.menuHintLines == [
            .literal("AWS Cost Explorer billing can lag."),
        ])
        #expect(OpenAIAPIProviderDescriptor.descriptor.tokenCost.menuHintLines == [
            .literal("Reported by OpenAI Admin API organization usage."),
        ])
        #expect(MistralProviderDescriptor.descriptor.tokenCost.menuHintLines == [
            .literal("Reported by Mistral billing usage."),
        ])
    }

    @Test
    func `cross provider case clusters are derived or specifically justified`() throws {
        let root = try Self.repoRoot()
        let files = try Self.shippedSwiftSources(root: root)
        let providerIDs = Set(UsageProvider.allCases.map(\.rawValue))
        let providerIDsByFolderName = Dictionary(uniqueKeysWithValues: providerIDs.map { ($0.lowercased(), $0) })
        var failures: [String] = []
        var constructsByPath: [String: [AllowedProviderConstruct]] = [:]
        var suppressionsByPath: [String: [SuppressedProviderReference]] = [:]

        for construct in Self.allowedProviderConstructs {
            constructsByPath[construct.path, default: []].append(construct)
        }
        for suppression in Self.suppressedProviderReferences {
            suppressionsByPath[suppression.path, default: []].append(suppression)
        }

        for file in files {
            let ownedProviderID = Self.providerImplementationID(
                file.path,
                providerIDsByFolderName: providerIDsByFolderName)
            let result = Self.analyze(
                file: file,
                providerIDs: providerIDs.subtracting(ownedProviderID.map { [$0] } ?? []),
                allowedConstructs: constructsByPath.removeValue(forKey: file.path) ?? [],
                suppressedReferences: suppressionsByPath.removeValue(forKey: file.path) ?? [])
            failures.append(contentsOf: result)
        }

        for constructs in constructsByPath.values.flatMap(\.self) {
            failures.append("\(constructs.path): allowlisted construct file does not exist in a shipped Swift target")
        }
        for suppression in suppressionsByPath.values.flatMap(\.self) {
            failures.append("\(suppression.path): suppressed reference file does not exist in a shipped Swift target")
        }

        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: "\n")))
    }

    @Test
    func `provider reference scanner catches raw ID policy fallbacks`() {
        let source = #"let command = sender.representedObject as? String ?? "claude""#
        let references = Self.providerReferences(in: source, providerIDs: ["claude", "codex"])

        #expect(references.count == 1)
        #expect(references.first?.providerIDs == ["claude"])
    }

    @Test
    func `provider reference scanner catches labeled and positional arguments`() {
        let source = "let rows = [makeRow(provider: .claude), makeRow(.codex)]"
        let references = Self.providerReferences(in: source, providerIDs: ["claude", "codex"])

        #expect(references.count == 1)
        #expect(references.first?.providerIDs == ["claude", "codex"])
    }

    @Test
    func `provider reference scanner sees through inline block comments`() {
        let assignment = "let provider: UsageProvider = /* fallback */ .claude"
        let labeled = "choose(provider: /* fallback */ .claude)"

        #expect(Self.providerReferences(in: assignment, providerIDs: ["claude"]).count == 1)
        #expect(Self.providerReferences(in: labeled, providerIDs: ["claude"]).count == 1)
    }

    @Test
    func `single provider argument remains an architecture finding`() {
        let failures = Self.analyze(
            file: SourceFile(path: "Sources/App/Shared.swift", source: "makeRow(provider: .claude)"),
            providerIDs: ["claude"],
            allowedConstructs: [])

        #expect(failures.count == 1)
    }

    @Test
    func `provider reference scanner catches fully qualified cases`() {
        let source = "let provider = UsageProvider.claude"
        let references = Self.providerReferences(in: source, providerIDs: ["claude"])

        #expect(references.count == 1)
        #expect(references.first?.providerIDs == ["claude"])
    }

    @Test
    func `provider instance aliases are derived only when names match`() {
        let derived = "public static let claude = UsageProvider.claude.instanceID"
        let policy = "public static let defaultProvider = UsageProvider.claude.instanceID"

        #expect(Self.providerReferences(in: derived, providerIDs: ["claude"]).isEmpty)
        #expect(Self.providerReferences(in: policy, providerIDs: ["claude"]).count == 1)
    }

    @Test
    func `provider reference scanner catches raw IDs in policy contexts`() {
        let source = #"""
        if selected == "claude" { return }
        case "codex": break
        return "cursor"
        route(command: "gemini")
        """#
        let references = Self.providerReferences(
            in: source,
            providerIDs: ["claude", "codex", "cursor", "gemini"])

        #expect(references.map(\.providerIDs) == [["claude"], ["codex"], ["cursor"], ["gemini"]])
    }

    @Test
    func `provider reference scanner catches raw IDs in every single statement position`() {
        let source = #"""
        let choice = "claude"
        choose("claude")
        let aliases = ["primary": "claude"]
        """#
        let references = Self.providerReferences(in: source, providerIDs: ["claude"])

        #expect(references.map(\.providerIDs) == [["claude"], ["claude"], ["claude"]])
    }

    @Test
    func `provider reference scanner catches labeled dotted case on continuation line`() {
        let source = """
        choose(
            provider:
                .claude)
        """
        let references = Self.providerReferences(in: source, providerIDs: ["claude"])

        #expect(references.count == 1)
        #expect(references.first?.providerIDs == ["claude"])
        #expect(references.first?.newlyRecognizedProviderIDs == ["claude"])
    }

    @Test
    func `provider reference scanner catches raw IDs in multiline policy statements`() {
        let source = #"""
        let handlers = [
            "claude": handler,
        ]
        let providerIDs = [
            "codex",
        ]
        """#
        let references = Self.providerReferences(in: source, providerIDs: ["claude", "codex"])

        #expect(references.map(\.providerIDs) == [["claude"], ["codex"]])
    }

    @Test
    func `provider reference scanner includes every multiline statement line in policy context`() {
        let source = #"""
        let aliases = [
            "provider":
                "claude",
        ]
        """#
        let references = Self.providerReferences(in: source, providerIDs: ["claude"])

        #expect(references.map(\.providerIDs) == [["claude"]])
    }

    @Test
    func `provider reference scanner ignores generic URLs and log categories`() {
        let source = #"""
        let url = "https://example.com/claude/status"
        if endpoint == "https://chat.openai.com" { return }
        let log = Logger(subsystem: "com.example.fixture", category: "codex")
        logger.info("claude request completed")
        logger.info(
            "codex request completed"
        )
        """#

        #expect(Self.providerReferences(in: source, providerIDs: ["claude", "codex", "openai"]).isEmpty)
    }

    @Test
    func `URL and log suppression applies only to its literal`() {
        let source = #"""
        let url = "https://example.com/claude"; let provider = "codex"
        logger.info("codex request completed"); return "codex"
        """#
        let references = Self.providerReferences(in: source, providerIDs: ["claude", "codex"])

        #expect(references.map(\.providerIDs) == [["codex"], ["codex"]])
    }

    @Test
    func `log suppression is scoped to the enclosing call argument`() {
        let source = #"""
        logger.info(
            "codex",
            metadata: ["provider": selectedProvider])
        selectProvider("claude", logger: logger.shared)
        selectProvider(
            "claude",
            logger: logger.shared)
        """#
        let references = Self.providerReferences(in: source, providerIDs: ["claude", "codex"])

        #expect(references.map(\.providerIDs) == [["claude"], ["claude"]])
    }

    @Test
    func `category suppression requires a log category constructor`() {
        let source = #"""
        let providerLog = OSLog(
            subsystem: "com.example.fixture",
            category: "codex")
        ProviderRule(category: "claude")
        """#
        let references = Self.providerReferences(in: source, providerIDs: ["claude", "codex"])

        #expect(references.map(\.providerIDs) == [["claude"]])
    }

    @Test
    func `suppression tokens require identifier boundaries`() {
        let source = #"""
        catalog.provider(
            named: "claude")
        catalogger.provider(
            named: "codex")
        render(
            subcategory:
                provider(named: "cursor"))
        """#
        let references = Self.providerReferences(
            in: source,
            providerIDs: ["claude", "codex", "cursor"])

        #expect(references.map(\.providerIDs) == [["claude"], ["codex"], ["cursor"]])
    }

    @Test
    func `exact suppression leaves repeated provider tokens visible`() {
        let path = "Sources/App/Shared.swift"
        let anchor = "let rows = [makeRow(provider: .claude), makeRow(provider: .claude)]"
        let suppression = SuppressedProviderReference(
            path: path,
            line: 1,
            anchor: anchor,
            expectedProviderIDs: ["claude"],
            reason: "The fixture suppresses exactly one token.")
        let failures = Self.analyze(
            file: SourceFile(path: path, source: anchor),
            providerIDs: ["claude"],
            allowedConstructs: [],
            suppressedReferences: [suppression])

        #expect(failures.count == 1)
        #expect(failures.first?.contains("references: 1") == true)
    }

    @Test
    func `exact suppression can justify a raw provider ID literal`() {
        let path = "Sources/App/Shared.swift"
        let anchor = "let upstreamStorageDirectory = \"opencode\""
        let suppression = SuppressedProviderReference(
            path: path,
            line: 1,
            anchor: anchor,
            expectedProviderIDs: ["opencode"],
            reason: "The fixture models an exact upstream storage contract.")
        let failures = Self.analyze(
            file: SourceFile(path: path, source: anchor),
            providerIDs: ["opencode"],
            allowedConstructs: [],
            suppressedReferences: [suppression])

        #expect(failures.isEmpty)
    }

    @Test
    func `provider implementation path identifies only a real provider folder`() {
        let folders = ["claude": "claude", "codex": "codex"]

        #expect(Self.providerImplementationID(
            "Sources/CodexBar/Providers/Claude/ClaudeSettings.swift",
            providerIDsByFolderName: folders) == "claude")
        #expect(Self.providerImplementationID(
            "Sources/CodexBar/Providers/Shared/ProviderHelpers.swift",
            providerIDsByFolderName: folders) == nil)
        #expect(Self.providerImplementationID(
            "Sources/CodexBar/NotProviders/ClaudeSettings.swift",
            providerIDsByFolderName: folders) == nil)
    }

    @Test
    func `provider folders exempt only their own provider references`() {
        let file = SourceFile(
            path: "Sources/CodexBar/Providers/Claude/ClaudeSettings.swift",
            source: "let providers: [UsageProvider] = [.claude, .codex]")
        let ownedProviderID = Self.providerImplementationID(
            file.path,
            providerIDsByFolderName: ["claude": "claude", "codex": "codex"])
        let failures = Self.analyze(
            file: file,
            providerIDs: Set(["claude", "codex"]).subtracting(ownedProviderID.map { [$0] } ?? []),
            allowedConstructs: [])

        #expect(failures.count == 1)
        #expect(failures.first?.contains("codex") == true)
        #expect(failures.first?.contains("claude") == false)
    }

    @Test
    func `provider clusters cannot chain beyond the fixed window`() {
        let references = [0, 10, 20, 30, 39, 40, 50, 60].map {
            ProviderReference(line: $0, providerIDs: ["codex"])
        }

        #expect(Self.providerReferenceClusters(references).map(\.lineRange) == [0...39, 40...60])
    }

    @Test
    func `one marker cannot justify two provider clusters`() {
        let source = ([
            "// Provider-specific by design: first fallback.",
            "let first = .codex",
        ] + Array(repeating: "", count: 13) + ["let second = .claude"]).joined(separator: "\n")
        let failures = Self.analyze(
            file: SourceFile(path: "Sources/App/Shared.swift", source: source),
            providerIDs: ["claude", "codex"],
            allowedConstructs: [])

        #expect(failures.count == 1)
        #expect(failures.first?.contains(":16 ") == true)
    }

    @Test
    func `provider markers must be comments with reasons`() {
        let stringMarker = #"let text = "Provider-specific by design: not a comment"\nlet value = .codex"#
        let emptyMarker = "// Provider-specific by design:   \nlet value = .codex"
        let validMarker = "// Provider-specific by design: fixture policy.\nlet value = .codex"

        #expect(Self.analyze(
            file: SourceFile(path: "Sources/App/StringMarker.swift", source: stringMarker),
            providerIDs: ["codex"],
            allowedConstructs: []).count == 1)
        #expect(Self.analyze(
            file: SourceFile(path: "Sources/App/EmptyMarker.swift", source: emptyMarker),
            providerIDs: ["codex"],
            allowedConstructs: []).count == 1)
        #expect(Self.analyze(
            file: SourceFile(path: "Sources/App/ValidMarker.swift", source: validMarker),
            providerIDs: ["codex"],
            allowedConstructs: []).isEmpty)
    }

    @Test
    func `allowlist anchors tolerate at most two lines before a cluster`() {
        let source = ["let anchor = true", "", "", "let fallback = .codex"].joined(separator: "\n")
        let construct = AllowedProviderConstruct(
            path: "Sources/App/Shared.swift",
            line: 1,
            anchor: "let anchor = true",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "The fixture verifies anchor distance.")

        #expect(Self.analyze(
            file: SourceFile(path: construct.path, source: source),
            providerIDs: ["codex"],
            allowedConstructs: [construct]).isEmpty == false)
    }

    @Test
    func `allowlisted constructs are unique and fingerprinted`() {
        let source = """
        let fallback = .codex
        """
        let construct = AllowedProviderConstruct(
            path: "Sources/App/Shared.swift",
            line: 1,
            anchor: "let fallback = .codex",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "The fixture verifies exact construct matching.")

        #expect(Self.analyze(
            file: SourceFile(path: construct.path, source: source),
            providerIDs: ["codex"],
            allowedConstructs: [construct]).isEmpty)
        #expect(Self.analyze(
            file: SourceFile(path: construct.path, source: source + "\nlet other = .codex"),
            providerIDs: ["codex"],
            allowedConstructs: [construct]).isEmpty == false)
    }

    @Test
    func `allowlist fingerprints preserve repeated occurrences on one line`() {
        let original = "let anchor = true\nlet values = [.codex]"
        let changed = "let anchor = true\nlet values = [.codex, .codex]"
        let construct = AllowedProviderConstruct(
            path: "Sources/App/Shared.swift",
            line: 1,
            anchor: "let anchor = true",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "The fixture verifies per-occurrence fingerprints.")

        #expect(Self.analyze(
            file: SourceFile(path: construct.path, source: original),
            providerIDs: ["codex"],
            allowedConstructs: [construct]).isEmpty)
        let failures = Self.analyze(
            file: SourceFile(path: construct.path, source: changed),
            providerIDs: ["codex"],
            allowedConstructs: [construct])
        #expect(failures.count == 2)
        #expect(failures.first?.contains("found [\"codex\"]/2/[\"codex@0\", \"codex@0\"]") == true)
    }

    private struct SourceFile {
        let path: String
        let source: String
    }

    private struct ProviderReference: Equatable {
        let line: Int
        var providerOccurrences: [String]
        var newlyRecognizedProviderOccurrences: [String]

        var providerIDs: Set<String> {
            Set(self.providerOccurrences)
        }

        var newlyRecognizedProviderIDs: Set<String> {
            Set(self.newlyRecognizedProviderOccurrences)
        }

        init(
            line: Int,
            providerIDs: Set<String>,
            newlyRecognizedProviderIDs: Set<String> = [])
        {
            self.line = line
            self.providerOccurrences = providerIDs.sorted()
            self.newlyRecognizedProviderOccurrences = newlyRecognizedProviderIDs.sorted()
        }

        init(
            line: Int,
            providerOccurrences: [String],
            newlyRecognizedProviderOccurrences: [String])
        {
            self.line = line
            self.providerOccurrences = providerOccurrences.sorted()
            self.newlyRecognizedProviderOccurrences = newlyRecognizedProviderOccurrences.sorted()
        }

        mutating func suppressOneOccurrence(of providerID: String) -> Bool {
            guard let occurrenceIndex = self.providerOccurrences.firstIndex(of: providerID) else { return false }
            if let newlyRecognizedIndex = self.newlyRecognizedProviderOccurrences.firstIndex(of: providerID) {
                self.newlyRecognizedProviderOccurrences.remove(at: newlyRecognizedIndex)
            }
            self.providerOccurrences.remove(at: occurrenceIndex)
            return true
        }
    }

    private struct ProviderReferenceCluster {
        let references: [ProviderReference]

        var lineRange: ClosedRange<Int> {
            self.references[0].line...self.references[self.references.count - 1].line
        }

        var providerIDs: Set<String> {
            self.references.reduce(into: []) { $0.formUnion($1.providerIDs) }
        }

        var referenceCount: Int {
            self.references.reduce(0) { $0 + $1.providerOccurrences.count }
        }

        var referenceFingerprint: [String] {
            self.references.flatMap { reference in
                reference.providerOccurrences.sorted().map { "\($0)@\(reference.line - self.lineRange.lowerBound)" }
            }
        }

        var newlyRecognizedFingerprint: [String] {
            self.references.flatMap { reference in
                reference.newlyRecognizedProviderOccurrences.sorted().map {
                    "\($0)@\(reference.line - self.lineRange.lowerBound)"
                }
            }
        }
    }

    private struct SuppressedProviderReference {
        let path: String
        let line: Int
        let anchor: String
        let expectedProviderIDs: Set<String>
        let reason: String
    }

    private struct AllowedProviderConstruct {
        let path: String
        let line: Int
        let anchor: String
        let expectedProviderIDs: Set<String>
        let expectedReferenceCount: Int
        let expectedReferenceFingerprint: [String]?
        let reason: String

        init(
            path: String,
            line: Int,
            anchor: String,
            expectedProviderIDs: Set<String>,
            expectedReferenceCount: Int,
            expectedReferenceFingerprint: [String]? = nil,
            reason: String)
        {
            self.path = path
            self.line = line
            self.anchor = anchor
            self.expectedProviderIDs = expectedProviderIDs
            self.expectedReferenceCount = expectedReferenceCount
            self.expectedReferenceFingerprint = expectedReferenceFingerprint
            self.reason = reason
        }
    }

    private static let providerCaseMarker = "Provider-specific by design:"
    private static let providerCaseMarkerWindow = 40
    private static let providerCaseClusterGap = 12
    private static let providerCaseClusterWindow = 40
    private static let allowlistAnchorTolerance = 2

    // swiftlint:disable line_length
    /// Provider references may be suppressed only at an exact source line and for an exact provider set. Each entry
    /// documents why that token is an external contract or ownership data rather than shared provider-selection
    /// policy.
    private static let suppressedProviderReferences: [SuppressedProviderReference] = [
        SuppressedProviderReference(
            path: "Sources/CodexBar/IconRenderer.swift",
            line: 630,
            anchor: "let eyeTiltAngle: CGFloat = .pi / 3 // 60 degrees tilt",
            expectedProviderIDs: ["pi"],
            reason: "This is the mathematical constant π used by the renderer, not a provider selection."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/StatusItemController+Animation.swift",
            line: 345,
            anchor: "style == .combined ? 0 : self.tiltAmount(for: primaryProvider) * .pi / 28",
            expectedProviderIDs: ["pi"],
            reason: "This is the mathematical constant π used for an animation angle, not a provider selection."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/PiFamilySessionScanner.swift",
            line: 491,
            anchor: "case .pi:",
            expectedProviderIDs: ["pi"],
            reason: "This branch dispatches the Pi-family root resolver for the fixed Pi dialect."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/PiFamilySessionScanner.swift",
            line: 530,
            anchor: "case .pi:",
            expectedProviderIDs: ["pi"],
            reason: "This branch dispatches the Pi-family root resolver for the fixed Pi dialect."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/PiFamilySessionScanner.swift",
            line: 657,
            anchor: "case .pi:",
            expectedProviderIDs: ["pi"],
            reason: "This branch checks command selectors for the fixed Pi dialect."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/CodexAccountUsageSnapshotStore.swift",
            line: 230,
            anchor: "let identity = snapshot.identity(for: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-owned integration passes its fixed identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/CodexAccountUsageSnapshotStore.swift",
            line: 232,
            anchor: "providerID: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-owned integration passes its fixed identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/CodexOwnershipContext.swift",
            line: 54,
            anchor: ".toUsageSnapshot(provider: .codex, accountEmail: normalizedEmail)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-owned integration passes its fixed identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/CopilotTokenStore.swift",
            line: 25,
            anchor: "private static let log = CodexBarLog.logger(LogCategories.provider(.copilot, scope: \"token-store\"))",
            expectedProviderIDs: ["copilot"],
            reason: "This provider-owned adapter passes its fixed identity to shared logging or cache infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/CursorLoginRunner.swift",
            line: 126,
            anchor: "private let logger = CodexBarLog.logger(LogCategories.provider(.cursor, scope: \"login\"))",
            expectedProviderIDs: ["cursor"],
            reason: "This provider-owned adapter passes its fixed identity to shared logging or cache infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/CursorLoginRunner.swift",
            line: 213,
            anchor: "let cacheMutationGate = CookieHeaderCache.beginConditionalMutationGate(provider: .cursor)",
            expectedProviderIDs: ["cursor"],
            reason: "This provider-owned adapter passes its fixed identity to shared logging or cache infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/KimiTokenStore.swift",
            line: 25,
            anchor: "private static let log = CodexBarLog.logger(LogCategories.provider(.kimi, scope: \"token-store\"))",
            expectedProviderIDs: ["kimi"],
            reason: "This provider-owned adapter passes its fixed identity to shared logging or cache infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/MenuBarMetricWindowResolver.swift",
            line: 131,
            anchor: "provider: .antigravity,",
            expectedProviderIDs: ["antigravity"],
            reason: "This named provider resolver supplies its fixed provider identity to the shared presentation helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/MiniMaxAPITokenStore.swift",
            line: 25,
            anchor: "private static let log = CodexBarLog.logger(LogCategories.provider(.minimax, scope: \"api-token-store\"))",
            expectedProviderIDs: ["minimax"],
            reason: "This provider-owned adapter passes its fixed identity to shared logging or cache infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/MiniMaxCookieStore.swift",
            line: 25,
            anchor: "private static let log = CodexBarLog.logger(LogCategories.provider(.minimax, scope: \"cookie-store\"))",
            expectedProviderIDs: ["minimax"],
            reason: "This provider-owned adapter passes its fixed identity to shared logging or cache infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/PredictivePaceWarnings.swift",
            line: 219,
            anchor: "preferredEmail: snapshot.accountEmail(for: .codex),",
            expectedProviderIDs: ["codex"],
            reason: "This exact provider-owned construct passes a fixed identity to shared infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/PreferencesProvidersPane+Testing.swift",
            line: 83,
            anchor: "self.codexAccountsSectionState(for: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "This test-only app seam pins Codex fixture data and does not make production routing policy."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/PreferencesProvidersPane+Testing.swift",
            line: 160,
            anchor: "let model = pane._test_menuCardModel(for: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "This test-only app seam pins Codex fixture data and does not make production routing policy."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/PreferencesProvidersPane+Testing.swift",
            line: 165,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This test-only app seam pins Codex fixture data and does not make production routing policy."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/PreferencesProvidersPane+Testing.swift",
            line: 170,
            anchor: "openAIWebDiagnostic: pane._test_openAIWebDiagnostic(for: .codex),",
            expectedProviderIDs: ["codex"],
            reason: "This test-only app seam pins Codex fixture data and does not make production routing policy."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/PreferencesProvidersPane+Testing.swift",
            line: 250,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This test-only app seam pins Codex fixture data and does not make production routing policy."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/SettingsStore+MenuObservation.swift",
            line: 115,
            anchor: "_ = self[providerConfig: .synthetic, field: .apiKey]",
            expectedProviderIDs: ["synthetic"],
            reason: "This observation touchpoint reads a fixed provider field so UI invalidation tracks that setting."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/SettingsStore+MenuObservation.swift",
            line: 135,
            anchor: "_ = self[providerConfig: .warp, field: .apiKey]",
            expectedProviderIDs: ["warp"],
            reason: "This observation touchpoint reads a fixed provider field so UI invalidation tracks that setting."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 491,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This Codex account projection passes its fixed provider identity to shared spend infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 579,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This Codex account projection passes its fixed provider identity to shared spend infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 582,
            anchor: "modelProviderName: ProviderDescriptorRegistry.descriptor(for: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "This Codex account projection passes its fixed provider identity to shared spend infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 661,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This Codex account projection passes its fixed provider identity to shared spend infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 729,
            anchor: "let providerName = store.metadata(for: .codex).displayName",
            expectedProviderIDs: ["codex"],
            reason: "This Codex account projection passes its fixed provider identity to shared spend infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 1757,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This OpenCodex enrichment descriptor maps the canonical source back to the Codex family."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 1796,
            anchor: "if providerID == UsageProvider.codex.rawValue {",
            expectedProviderIDs: ["codex"],
            reason: "This publication projection expands the fixed Codex provider family into its account sources."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 1814,
            anchor: "return .codex",
            expectedProviderIDs: ["codex"],
            reason: "This publication projection maps stable Codex account source IDs back to their provider family."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/StatusItemController+CodexStackedMenu.swift",
            line: 31,
            anchor: "for: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-owned integration passes its fixed identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/StatusItemController+CompactAccountMenu.swift",
            line: 76,
            anchor: "let plan = self.compactAccountPlan(for: .codex, accounts: projected)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/StatusItemController+CompactAccountMenu.swift",
            line: 93,
            anchor: "for: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/StatusItemController+CompactAccountMenu.swift",
            line: 286,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/StatusItemController+MemoryPressure.swift",
            line: 45,
            anchor: ".provider(.codex): cacheEntry,",
            expectedProviderIDs: ["codex"],
            reason: "The memory-pressure debug fixture installs its synthetic entry in the Codex cache slot."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/StatusItemController+Menu.swift",
            line: 1144,
            anchor: "controller.scheduleOpenRootMenuDataRebuildIfStillVisible(menu, provider: .codex) {",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/SyntheticTokenStore.swift",
            line: 25,
            anchor: "private static let log = CodexBarLog.logger(LogCategories.provider(.synthetic, scope: \"token-store\"))",
            expectedProviderIDs: ["synthetic"],
            reason: "This provider-owned adapter passes its fixed identity to shared logging or cache infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+Accessors.swift",
            line: 97,
            anchor: "accountID: self.settings.selectedTokenAccount(for: .deepseek)?.id,",
            expectedProviderIDs: ["deepseek"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+ClaudeDebug.swift",
            line: 111,
            anchor: "for: .claude,",
            expectedProviderIDs: ["claude"],
            reason: "This provider-owned integration passes its fixed identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+CodexCostCatchUp.swift",
            line: 98,
            anchor: "let scope = self.tokenCostScope(for: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-owned integration passes its fixed identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+CodexCostCatchUp.swift",
            line: 99,
            anchor: "let scopeSignature = self.tokenSnapshotScopeSignature(for: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-owned integration passes its fixed identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+HighestUsage.swift",
            line: 161,
            anchor: "let windows = IconRemainingResolver.resolvedWindows(snapshot: snapshot, style: .antigravity)",
            expectedProviderIDs: ["antigravity"],
            reason: "This named provider resolver supplies its fixed provider identity to the shared presentation helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+HistoricalPace.swift",
            line: 160,
            anchor: "let ownership = self.codexOwnershipContext(preferredEmail: snapshot.accountEmail(for: .codex))",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+HistoricalPace.swift",
            line: 227,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+PlanUtilization.swift",
            line: 229,
            anchor: "self.sessionEquivalentBurnCache.removeValue(forKey: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 1086,
            anchor: "providerID: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 1663,
            anchor: "let currentAccount = self.uniqueTokenAccount(provider: .claude, accountID: fetchedAccount.id),",
            expectedProviderIDs: ["claude"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+RefreshEnrichment.swift",
            line: 279,
            anchor: "await self.refreshProvider(.codex, coalesceIfRefreshing: true)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+RefreshEnrichment.swift",
            line: 296,
            anchor: "accessEnabled: self.isEnabled(.codex) &&",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+SpendDashboardCodexCostCatchUp.swift",
            line: 58,
            anchor: "self.settings.isCostUsageEffectivelyEnabled(for: .codex),",
            expectedProviderIDs: ["codex"],
            reason: "This Codex account projection passes its fixed provider identity to shared spend infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+SpendDashboardCodexCostCatchUp.swift",
            line: 59,
            anchor: "self.isEnabled(.codex)",
            expectedProviderIDs: ["codex"],
            reason: "This Codex account projection passes its fixed provider identity to shared spend infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 802,
            anchor: ".descriptor(for: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 805,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1327,
            anchor: "let scoped = result.usage.scoped(to: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1437,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1441,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1444,
            anchor: "self.handlePredictivePaceWarningTransitions(provider: .codex, snapshot: snapshot)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1454,
            anchor: "self.rememberLiveSystemCodexEmailIfNeeded(snapshot.accountEmail(for: .codex))",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1457,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1465,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "The successful Codex account publication passes its fixed provider identity to the opt-in hook."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1495,
            anchor: "if retained == nil { self.snapshots.removeValue(forKey: .codex) }",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1541,
            anchor: "from: self.presentationSnapshot(for: .deepseek))",
            expectedProviderIDs: ["deepseek"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 188,
            anchor: "allowVertexClaudeFallback: !self.isEnabled(.claude),",
            expectedProviderIDs: ["claude"],
            reason: "The local transcript scan permits Vertex fallback only when Claude is disabled to avoid " +
                "double-counting the same logs."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 460,
            anchor: "let scope = self.tokenCostScope(for: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "The Codex-only cache hydration path passes its fixed provider identity to shared state helpers."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 462,
            anchor: "let publicationRevision = self.providerPublicationRevision(for: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "The Codex-only cache hydration path passes its fixed provider identity to shared state helpers."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 463,
            anchor: "let providerConfigRevision = self.settings.providerConfigRevision(for: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "The Codex-only cache hydration path passes its fixed provider identity to shared state helpers."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 465,
            anchor: "let tokenSnapshotScopeSignature = self.tokenSnapshotScopeSignature(for: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "The Codex-only cache hydration path passes its fixed provider identity to shared state helpers."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 466,
            anchor: "let tokenSnapshotPublicationRevision = self.tokenSnapshotPublicationRevision(for: .codex)",
            expectedProviderIDs: ["codex"],
            reason: "The Codex-only cache hydration path passes its fixed provider identity to shared state helpers."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 505,
            anchor: "self.settings.isCostUsageEffectivelyEnabled(for: .codex),",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 506,
            anchor: "self.isEnabled(.codex),",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 515,
            anchor: "self.installCachedTokenSnapshot(result.snapshot, for: .codex, accounting: result.accounting)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 643,
            anchor: "return CookieHeaderCache.loadForDisplay(provider: .cursor)",
            expectedProviderIDs: ["cursor"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 653,
            anchor: "let scope = self.tokenCostScope(for: .cursor)",
            expectedProviderIDs: ["cursor"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 628,
            anchor: "return self.tokenAccountSnapshotCacheKey(provider: .claude, account: account)",
            expectedProviderIDs: ["claude"],
            reason: "Claude widget quota ownership uses the selected Claude account's isolated snapshot key."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 635,
            anchor: "return self.tokenAccountSnapshotCacheKey(provider: .claude, account: account)",
            expectedProviderIDs: ["claude"],
            reason: "Claude widget quota ownership uses the selected Claude account's isolated snapshot key."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore.swift",
            line: 1128,
            anchor: "provider: .deepseek,",
            expectedProviderIDs: ["deepseek"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore.swift",
            line: 1230,
            anchor: "let sourceMode = self.sourceMode(for: .claude)",
            expectedProviderIDs: ["claude"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore.swift",
            line: 1234,
            anchor: "provider: .claude,",
            expectedProviderIDs: ["claude"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/ZaiTokenStore.swift",
            line: 25,
            anchor: "private static let log = CodexBarLog.logger(LogCategories.provider(.zai, scope: \"token-store\"))",
            expectedProviderIDs: ["zai"],
            reason: "This provider-owned adapter passes its fixed identity to shared logging or cache infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCLI/CLICardsRenderer.swift",
            line: 235,
            anchor: "provider: .claude,",
            expectedProviderIDs: ["claude"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCLI/CLICardsRenderer.swift",
            line: 236,
            anchor: "title: ProviderDescriptorRegistry.descriptor(for: .claude).metadata.displayName,",
            expectedProviderIDs: ["claude"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/CodexLocalProjectUsageIndexer.swift",
            line: 69,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-owned integration passes its fixed identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/LocalAgentSessionScanner.swift",
            line: 595,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific core branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardBrowserCookieImporter.swift",
            line: 150,
            anchor: "CookieHeaderCache.loadSerialized(provider: .codex, scope: cacheScope)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-owned adapter passes its fixed identity to shared logging or cache infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardBrowserCookieImporter.swift",
            line: 169,
            anchor: "CookieHeaderCache.clear(provider: .codex, scope: cacheScope)",
            expectedProviderIDs: ["codex"],
            reason: "This provider-owned adapter passes its fixed identity to shared logging or cache infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardBrowserCookieImporter.swift",
            line: 887,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-owned adapter passes its fixed identity to shared logging or cache infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardWebViewCache.swift",
            line: 16,
            anchor: "fileprivate static let log = CodexBarLog.logger(LogCategories.provider(.openai, scope: \"webview\"))",
            expectedProviderIDs: ["openai"],
            reason: "This provider-owned adapter passes its fixed identity to shared logging or cache infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 146,
            anchor: "provider: .claude,",
            expectedProviderIDs: ["claude"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 153,
            anchor: "provider: .claude,",
            expectedProviderIDs: ["claude"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 160,
            anchor: "provider: .claude,",
            expectedProviderIDs: ["claude"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 167,
            anchor: "provider: .claude,",
            expectedProviderIDs: ["claude"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 174,
            anchor: "provider: .claude,",
            expectedProviderIDs: ["claude"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 181,
            anchor: "provider: .claude,",
            expectedProviderIDs: ["claude"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 188,
            anchor: "provider: .claude,",
            expectedProviderIDs: ["claude"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 195,
            anchor: "provider: .claude,",
            expectedProviderIDs: ["claude"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 215,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 222,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 229,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 236,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 243,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 250,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 257,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This inventory row records the provider that owns its static storage location."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/ProviderDiagnosticExport.swift",
            line: 452,
            anchor: "self = try .minimax(container.decode(MiniMaxDiagnosticDetails.self, forKey: .minimax))",
            expectedProviderIDs: ["minimax"],
            reason: "This tagged diagnostic payload decodes its matching MiniMax detail type and key."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/ProviderDiagnosticExport.swift",
            line: 466,
            anchor: "try container.encode(details, forKey: .minimax)",
            expectedProviderIDs: ["minimax"],
            reason: "This tagged diagnostic payload encodes MiniMax details under the matching wire key."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/UsageFetcher.swift",
            line: 1527,
            anchor: "providerID: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific core branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/GeminiLoginRunner.swift",
            line: 7,
            anchor: ".appendingPathComponent(\".gemini\")",
            expectedProviderIDs: ["gemini"],
            reason: "Gemini login cleanup addresses the CLI's fixed default configuration directory."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/UsageStore+OpenAIWeb.swift",
            line: 1617,
            anchor: "&& (lower.contains(\"about\") || lower.contains(\"openai\") || lower.contains(\"chatgpt\"))",
            expectedProviderIDs: ["openai"],
            reason: "This logged-out-page classifier matches OpenAI's public landing-page brand token."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/AgentSession.swift",
            line: 519,
            anchor: ".appendingPathComponent(\".claude\", isDirectory: true)",
            expectedProviderIDs: ["claude"],
            reason: "The Claude transcript locator follows Claude Code's fixed default projects directory."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/AgentSession.swift",
            line: 593,
            anchor: ".appendingPathComponent(\".claude\", isDirectory: true)",
            expectedProviderIDs: ["claude"],
            reason: "The budgeted Claude transcript locator follows Claude Code's fixed default projects directory."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/AgentSession.swift",
            line: 700,
            anchor: "if value.contains(\"ide\") || value.contains(\"vscode\") || value.contains(\"cursor\") || value.contains(\"zed\") {",
            expectedProviderIDs: ["cursor", "zed"],
            reason: "This session-source classifier recognizes editor-origin strings emitted by upstream clients."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/DarwinProcessEnumerator.swift",
            line: 9,
            anchor: "if lowercasedPath.contains(\"antigravity\") {",
            expectedProviderIDs: ["antigravity"],
            reason: "This argv privacy prefilter recognizes Antigravity's fixed executable-path signature."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe.swift",
            line: 208,
            anchor: "matching: { $0.lowercased().contains(\"gemini\") },",
            expectedProviderIDs: ["gemini"],
            reason: "Antigravity quota payloads use this token to identify a model family, not a CodexBar provider."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe.swift",
            line: 211,
            anchor: "matching: { $0.lowercased().contains(\"claude\") || $0.lowercased().contains(\"gpt\") },",
            expectedProviderIDs: ["claude"],
            reason: "Antigravity quota payloads use this token to identify a model family, not a CodexBar provider."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe.swift",
            line: 300,
            anchor: "if lowercasedTitle.contains(\"gemini\") {",
            expectedProviderIDs: ["gemini"],
            reason: "Antigravity quota titles use this token to identify a model family for display."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe.swift",
            line: 303,
            anchor: "if lowercasedTitle.contains(\"claude\") || lowercasedTitle.contains(\"gpt\") {",
            expectedProviderIDs: ["claude"],
            reason: "Antigravity quota titles use this token to identify a model family for display."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe.swift",
            line: 339,
            anchor: "if title.contains(\"gemini\") {",
            expectedProviderIDs: ["gemini"],
            reason: "Antigravity quota titles use this token to rank a model family."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe.swift",
            line: 342,
            anchor: "if title.contains(\"claude\") || title.contains(\"gpt\") {",
            expectedProviderIDs: ["claude"],
            reason: "Antigravity quota titles use this token to rank a model family."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/AzureOpenAI/AzureOpenAIUsageFetcher.swift",
            line: 173,
            anchor: "let base = self.apiRoot(endpoint: endpoint, pathComponents: [\"openai\", \"v1\"])",
            expectedProviderIDs: ["openai"],
            reason: "Azure OpenAI's v1 REST route requires this fixed service path component."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/AzureOpenAI/AzureOpenAIUsageFetcher.swift",
            line: 182,
            anchor: "let base = self.apiRoot(endpoint: endpoint, pathComponents: [\"openai\"])",
            expectedProviderIDs: ["openai"],
            reason: "Azure OpenAI's deployment REST route requires this fixed service path component."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/Gemini/GeminiStatusProbe.swift",
            line: 146,
            anchor: "if normalized.contains(\"migrate\"), normalized.contains(\"antigravity\"), normalized.contains(\"gemini\") {",
            expectedProviderIDs: ["antigravity"],
            reason: "Gemini's upstream deprecation response names the Antigravity migration destination."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/OpenCodeGo/OpenCodeGoLocalUsageReader.swift",
            line: 39,
            anchor: ".appendingPathComponent(\"opencode\", isDirectory: true)",
            expectedProviderIDs: ["opencode"],
            reason: "OpenCode Go reads the upstream OpenCode shared storage directory by contract."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/ProviderVersionDetector.swift",
            line: 147,
            anchor: "return whichHook(\"claude\") != nil",
            expectedProviderIDs: ["claude"],
            reason: "The Claude binary resolvability check asks its injected locator for the fixed executable name."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/Providers/ProviderVersionDetector.swift",
            line: 158,
            anchor: "? self.whichHook!(\"claude\")",
            expectedProviderIDs: ["claude"],
            reason: "The Claude version detector asks its injected locator for the fixed Claude executable name."),
        SuppressedProviderReference(
            path: "Sources/CodexBarWidget/BurnDownWidgetProvider.swift",
            line: 464,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This WidgetKit default or preview pins the established Codex sample provider."),
        SuppressedProviderReference(
            path: "Sources/CodexBarWidget/BurnDownWidgetProvider.swift",
            line: 495,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This WidgetKit default or preview pins the established Codex sample provider."),
        SuppressedProviderReference(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 493,
            anchor: "modelProviderName: ProviderDescriptorRegistry.descriptor(for: .codex).metadata.displayName,",
            expectedProviderIDs: ["codex"],
            reason: "This Codex account projection passes its fixed provider identity to shared spend infrastructure."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCLI/CLICostCommand.swift",
            line: 450,
            anchor: "lines.append(Self.costEstimateHint(provider: .codex))",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCLI/CLICostCommand.swift",
            line: 474,
            anchor: "lines.append(Self.costEstimateHint(provider: .codex))",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific app branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 368,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific core branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 402,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific core branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 1483,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific core branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 1569,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific core branch passes its already-selected identity to a shared helper."),
        SuppressedProviderReference(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 1592,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            reason: "This provider-specific core branch passes its already-selected identity to a shared helper."),
    ]

    /// Each entry names one uniquely anchored construct and pins its complete provider-reference fingerprint.
    /// Adding or removing a reference invalidates the entry instead of silently expanding an exemption.
    /// Anchor literals must remain byte-for-byte single lines for exact source verification.
    private static let allowedProviderConstructs: [AllowedProviderConstruct] = [
        AllowedProviderConstruct(
            path: "Sources/CodexBar/CodexOwnershipContext.swift",
            line: 31,
            anchor: "snapshot?.accountEmail(for: .codex) ??",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["codex@0", "codex@1", "codex@1"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/CodexOwnershipContext.swift",
            line: 56,
            anchor: "?? self.snapshots[.codex]?.secondary?.resetsAt",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/CodexOwnershipContext.swift",
            line: 210,
            anchor: "self.sha256Hex(\"\\(UsageProvider.codex.rawValue):email:\\(normalizedEmail)\")",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/CostHistoryChartMenuView.swift",
            line: 1151,
            anchor: "let projects = provider == .codex ? snapshot.projects : []",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@1"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/HistoricalUsagePace.swift",
            line: 221,
            anchor: "$0.provider == .codex &&",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/HistoricalUsagePace.swift",
            line: 462,
            anchor: "record.provider == .codex && record.windowKind == .secondary && record.windowMinutes > 0",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/IconRenderer.swift",
            line: 734,
            anchor: "let twistGemini = decorations.contains(.gemini)",
            expectedProviderIDs: ["antigravity", "factory", "gemini", "grok", "warp"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["gemini@0", "antigravity@1", "factory@2", "warp@3", "grok@4"],
            reason: "The shared icon renderer reads descriptor decoration flags, including Grok's visor, to draw each provider's configured icon detail."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/InlineUsageDashboardContent.swift",
            line: 408,
            anchor: "if input.provider == .cursor, let meteredCostUSD = snapshot.meteredCostUSD {",
            expectedProviderIDs: ["cursor"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["cursor@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuBarLayout.swift",
            line: 908,
            anchor: "ProviderDescriptorRegistry.descriptor(for: provider ?? .codex).presentation.primarySemanticWindow)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@3"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuBarLayoutEditor.swift",
            line: 896,
            anchor: "let provider = self.provider ?? .codex",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuBarLayoutEditor.swift",
            line: 929,
            anchor: "if provider == .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+CodexResetCredits.swift",
            line: 218,
            anchor: "guard input.provider == .codex,",
            expectedProviderIDs: ["claude", "codex", "grok"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["grok@0", "claude@8", "codex@16"],
            reason: "Grok, Claude, and Codex reset-credit snapshots use distinct provider-owned sources and a common card projection."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+Costs.swift",
            line: 224,
            anchor: "let sessionLabel = if provider == .bedrock || provider == .mistral {",
            expectedProviderIDs: ["bedrock", "mistral"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["bedrock@0", "mistral@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+Costs.swift",
            line: 258,
            anchor: "} else if provider == .mistral,",
            expectedProviderIDs: ["mistral"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["mistral@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+Costs.swift",
            line: 537,
            anchor: "if style == .claude {",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+Kiro.swift",
            line: 7,
            anchor: "if let authMethod = input.snapshot?.loginMethod(for: .kiro)?",
            expectedProviderIDs: ["kiro"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["kiro@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ModelHelpers.swift",
            line: 231,
            anchor: "guard provider == .litellm,",
            expectedProviderIDs: ["litellm"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["litellm@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ModelHelpers.swift",
            line: 337,
            anchor: "if input.provider == .kiro {",
            expectedProviderIDs: ["kilo", "kiro"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["kiro@0", "kilo@4"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ModelHelpers.swift",
            line: 355,
            anchor: "if input.provider == .mimo, input.snapshot != nil {",
            expectedProviderIDs: ["claude", "mimo", "muse", "opencodego"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["mimo@0", "claude@4", "opencodego@10", "muse@15"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ModelHelpers.swift",
            line: 603,
            anchor: "if input.provider == .factory, snapshot.tertiary != nil {",
            expectedProviderIDs: [
                "alibabatokenplan", "amp", "cursor", "doubao", "factory", "grok", "opencode", "qwencloud",
                "sub2api",
            ],
            expectedReferenceCount: 11,
            expectedReferenceFingerprint: [
                "factory@0", "cursor@3", "grok@12", "doubao@14", "sub2api@16", "amp@18", "opencode@20",
                "alibabatokenplan@22",
                "qwencloud@24", "amp@33", "alibabatokenplan@35",
            ],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ModelHelpers.swift",
            line: 814,
            anchor: "case .minimax:",
            expectedProviderIDs: ["codex", "minimax", "poe"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["minimax@0", "poe@8", "codex@13"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ModelHelpers.swift",
            line: 1035,
            anchor: "if input.provider == .codex, !input.showOptionalCreditsAndExtraUsage {",
            expectedProviderIDs: ["claude", "codex", "copilot", "sub2api"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["codex@0", "copilot@3", "claude@6", "sub2api@18"],
            reason: "Extra-window visibility, Sub2API reset details, Claude weekly labels, and Doubao team labels follow provider-specific data."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ModelHelpers.swift",
            line: 1119,
            anchor: "guard provider == .kiro, namedWindow.id == \"kiro-overage\",",
            expectedProviderIDs: ["kiro"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["kiro@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ModelHelpers.swift",
            line: 1149,
            anchor: "if input.provider == .antigravity,",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["antigravity@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ModelHelpers.swift",
            line: 1184,
            anchor: "if provider == .claude || provider == .cursor, window.windowMinutes != 10080 {",
            expectedProviderIDs: ["antigravity", "claude", "codex", "cursor"],
            expectedReferenceCount: 6,
            expectedReferenceFingerprint: [
                "claude@0", "cursor@0", "antigravity@3", "claude@3", "codex@3", "cursor@3",
            ],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ModelHelpers.swift",
            line: 1218,
            anchor: "guard input.provider == .antigravity else { return nil }",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["antigravity@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ProviderDetailLocalization.swift",
            line: 11,
            anchor: "guard provider == .deepseek || provider == .zai || provider == .kiro else {",
            expectedProviderIDs: ["deepseek", "kiro", "zai"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["deepseek@0", "kiro@0", "zai@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ProviderDetailLocalization.swift",
            line: 59,
            anchor: "if provider == .amp {",
            expectedProviderIDs: ["amp", "openrouter"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["amp@0", "openrouter@9"],
            reason: "Localizes Amp's static unit/pool copy and OpenRouter's cap disclosure; balances stay canonical."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ProviderDetailLocalization.swift",
            line: 119,
            anchor: "case .deepseek:",
            expectedProviderIDs: ["deepseek", "kiro", "zai"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["deepseek@0", "zai@2", "kiro@4"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 205,
            anchor: "if provider == .openrouter, metric.id == \"primary\" {",
            expectedProviderIDs: ["openrouter"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["openrouter@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 514,
            anchor: "if self.provider != .codex || self.showsCodexHint,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 600,
            anchor: "guard self.model.provider == .doubao else { return nil }",
            expectedProviderIDs: ["doubao"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["doubao@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1128,
            anchor: "if provider == .kiro,",
            expectedProviderIDs: ["kilo", "kiro"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["kiro@0", "kilo@5"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1151,
            anchor: "if provider == .minimax {",
            expectedProviderIDs: ["codex", "minimax"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["minimax@0", "codex@3"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1186,
            anchor: "guard let loginMethod = snapshot?.loginMethod(for: .kilo) else {",
            expectedProviderIDs: ["kilo"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["kilo@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1272,
            anchor: "if input.provider == .antigravity {",
            expectedProviderIDs: ["antigravity", "mistral"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["antigravity@0", "mistral@6"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1292,
            anchor: "if input.provider == .codex, let codexProjection = input.codexProjection {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1308,
            anchor: "if input.provider != .codex, let weekly = snapshot.secondary {",
            expectedProviderIDs: ["alibaba", "alibabatokenplan", "codex", "perplexity", "sub2api"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: [
                "codex@0",
                "alibaba@9",
                "alibabatokenplan@9",
                "perplexity@16",
                "sub2api@16",
            ],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1348,
            anchor: "if input.provider == .kilo || input.provider == .kimi,",
            expectedProviderIDs: ["kilo", "kimi"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["kilo@0", "kimi@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1449,
            anchor: "var paceDetail = if input.provider == .kimi {",
            expectedProviderIDs: ["kimi"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["kimi@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1466,
            anchor: "if input.provider == .warp,",
            expectedProviderIDs: ["warp"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["warp@0"],
            reason: "Warp replaces its reset date with provider-owned weekly reset copy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1482,
            anchor: "if input.provider == .sub2api {",
            expectedProviderIDs: ["kiro", "sub2api"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["sub2api@0", "kiro@3"],
            reason: "Sub2API reset copy and Kiro bonus-credit details retain their provider-owned presentation."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1499,
            anchor: "if input.provider == .alibaba || input.provider == .alibabatokenplan,",
            expectedProviderIDs: [
                "alibaba",
                "alibabatokenplan",
                "copilot",
                "perplexity",
                "synthetic",
                "zenmux",
            ],
            expectedReferenceCount: 7,
            expectedReferenceFingerprint: [
                "alibaba@0", "alibabatokenplan@0", "copilot@6", "zenmux@6", "zenmux@12", "perplexity@23",
                "synthetic@29",
            ],
            reason: "Alibaba, Copilot/ZenMux, Perplexity, and Synthetic project provider-owned weekly reset or pace details into the shared card."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuDescriptor.swift",
            line: 219,
            anchor: "case .codex: \"⌘\"",
            expectedProviderIDs: ["claude", "codex", "pi"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["codex@0", "claude@1", "pi@2"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuDescriptor.swift",
            line: 494,
            anchor: "if provider == .kiro {",
            expectedProviderIDs: ["kiro"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["kiro@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuDescriptor.swift",
            line: 508,
            anchor: "} else if provider == .kilo {",
            expectedProviderIDs: ["kilo", "mimo", "openrouter", "poe"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["kilo@0", "mimo@9", "openrouter@9", "poe@9"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuDescriptor.swift",
            line: 710,
            anchor: "let target = provider ?? store.enabledFirstPartyProviders().first ?? .codex",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 9,
            expectedReferenceFingerprint: [
                "codex@0",
                "codex@4",
                "claude@11",
                "claude@12",
                "claude@19",
                "claude@21",
                "claude@22",
                "claude@22",
                "claude@23",
            ],
            reason: "Claude account actions accept proven CLI quota success without inventing identity; " +
                "Codex retains its default-provider fallback."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuDescriptor.swift",
            line: 752,
            anchor: "if provider == .factory, snapshot.tertiary != nil {",
            expectedProviderIDs: [
                "alibabatokenplan", "amp", "codex", "cursor", "doubao", "factory", "grok", "qwencloud",
                "sub2api",
            ],
            expectedReferenceCount: 10,
            expectedReferenceFingerprint: [
                "factory@0", "cursor@3", "codex@11", "grok@17", "doubao@20", "sub2api@22", "amp@24",
                "alibabatokenplan@26", "qwencloud@28", "codex@37",
            ],
            reason: "Window titles follow each provider quota contract for Factory, Cursor, Codex, Grok, Doubao, Sub2API, Amp, Alibaba Token Plan, and Qwen Cloud."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuDescriptor.swift",
            line: 876,
            anchor: "let cleaned = if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex plan names use CodexPlanFormatting for tier labels such as Pro 20x; other providers use the generic cleaner."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuOpenRefreshPlan.swift",
            line: 28,
            anchor: "refreshCodexDashboard: inputs.enabledProviders.contains(.codex),",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact quota-state bridge preserves Codex owner changes and fresh-baseline resets."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/PredictivePaceWarnings.swift",
            line: 123,
            anchor: "guard provider == .codex || provider == .claude else { return }",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["claude@0", "codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/PredictivePaceWarnings.swift",
            line: 191,
            anchor: "if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@11"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/PreferencesProvidersPane+Testing.swift",
            line: 115,
            anchor: "store.versions[.codex] = \"1.0.0\"",
            expectedProviderIDs: [
                "claude", "codex", "cursor", "gemini", "kimi", "minimax", "opencode", "opencodego",
                "synthetic", "zai",
            ],
            expectedReferenceCount: 20,
            expectedReferenceFingerprint: [
                "codex@0",
                "claude@1",
                "cursor@2",
                "codex@5",
                "minimax@8",
                "cursor@9",
                "minimax@10",
                "codex@11",
                "codex@23",
                "codex@24",
                "claude@25",
                "cursor@26",
                "opencode@27",
                "opencodego@28",
                "zai@29",
                "synthetic@30",
                "minimax@31",
                "kimi@32",
                "gemini@33",
                "claude@35",
            ],
            reason: "This exact preferences test fixture seeds representative provider versions, snapshots, and accounts."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/PreferencesProvidersPane.swift",
            line: 298,
            anchor: "guard let state = self.codexAccountsSectionState(for: .codex), state.canAddAccount else {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact Codex account fetch binds its descriptor and scoped settings snapshot together."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/PreferencesProvidersPane.swift",
            line: 316,
            anchor: "guard let state = self.codexAccountsSectionState(for: .codex),",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/PreferencesSpendDashboardPane.swift",
            line: 533,
            anchor: "self.configuration.providerIDs.contains(UsageProvider.codex.rawValue)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/PreferencesSpendDashboardPane.swift",
            line: 960,
            anchor: "case .bedrock: icon.isTemplate ? 1 : 0.84",
            expectedProviderIDs: [
                "antigravity",
                "bedrock",
                "codex",
                "cursor",
                "muse",
                "vertexai",
            ],
            expectedReferenceCount: 6,
            expectedReferenceFingerprint: [
                "cursor@0",
                "codex@1",
                "antigravity@2",
                "bedrock@3",
                "muse@4",
                "vertexai@4",
            ],
            reason: "Curated provider artwork uses normalized bounds while template symbols retain the standard size."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/ShareStatsPayload.swift",
            line: 412,
            anchor: "let snapshots: [UsageSnapshot?] = if row.provider == .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Scoped Codex history uses its matching account snapshot for plan labels."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Providers/Shared/ProviderTokenAccountSelection.swift",
            line: 28,
            anchor: "guard provider == .deepseek else { return settings.showOptionalCreditsAndExtraUsage }",
            expectedProviderIDs: ["deepseek"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["deepseek@0"],
            reason: "This exact shared provider integration dispatches a capability owned by the provider descriptor or adapter."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/ShareStatsPayload.swift",
            line: 215,
            anchor: "([\"codestral-\", \"devstral-\", \"magistral-\", \"mistral-\", \"mistral \", \"mistral.\", \"mixtral-\"], \"Mistral\"),",
            expectedProviderIDs: ["mistral"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["mistral@0"],
            reason: "This public model-family sanitizer is independent of the provider registry; Mistral is also a provider ID."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SessionQuotaNotifications.swift",
            line: 201,
            anchor: "if transition != .restored || observation.provider != .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["codex@0", "codex@6", "codex@11"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SessionQuotaNotifications.swift",
            line: 276,
            anchor: "codexOwnerKey: observation.provider == .codex ? observation.codexOwnerKey : nil,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@1"],
            reason: "This exact reducer state preserves Codex owner and trusted-reset baselines."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SessionQuotaNotifications.swift",
            line: 291,
            anchor: "let trustedResetBoundary: Date? = if observation.provider != .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SessionQuotaNotifications.swift",
            line: 307,
            anchor: "codexOwnerKey: observation.provider == .codex ? observation.codexOwnerKey : nil,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact reducer state preserves the Codex owner on updated observations."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SessionQuotaNotifications.swift",
            line: 453,
            anchor: "if provider == .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["codex@0", "codex@9", "codex@10"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SettingsStore+MenuPreferences.swift",
            line: 311,
            anchor: "(provider == .codex && self.codexLocalSessionCostLedgerEnabled)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SettingsStore.swift",
            line: 1252,
            anchor: "if !seen.contains(.factory), let zaiIndex = ordered.firstIndex(of: .zai) {",
            expectedProviderIDs: ["factory", "minimax", "zai"],
            expectedReferenceCount: 8,
            expectedReferenceFingerprint: [
                "factory@0",
                "zai@0",
                "factory@1",
                "factory@2",
                "minimax@5",
                "zai@5",
                "minimax@7",
                "minimax@8",
            ],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 694,
            anchor: "(providers.contains(.codex) && settings.codexLocalSessionCostLedgerEnabled)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct preserves the provider-owned local ledger when global scanning is off."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 210,
            anchor: "let codexSources = providers.contains(.codex)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 759,
            anchor: "if providers.contains(.codex) {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 779,
            anchor: "if providers.contains(.codex) {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["codex@0", "codex@2", "codex@9"],
            reason: "This dashboard boundary fans out the Codex account cache, publication, and refresh inputs."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 1842,
            anchor: "guard input.provider == .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SpendDashboardModel+ModelBreakdown.swift",
            line: 138,
            anchor: "guard summary.input.provider == .codex else { return false }",
            expectedProviderIDs: ["antigravity", "codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "antigravity@10"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SpendDashboardModel.swift",
            line: 1392,
            anchor: "guard provider == .mistral || provider == .openrouter || provider == .xai else { return displayCalendar }",
            expectedProviderIDs: ["mistral", "openrouter", "xai"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["mistral@0", "openrouter@0", "xai@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+AccountMenuDisplay.swift",
            line: 122,
            anchor: "guard providers.contains(.codex) else { return }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+AccountMenuDisplay.swift",
            line: 159,
            anchor: "guard provider == .codex else { return display }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+Actions.swift",
            line: 408,
            anchor: "if provider == .qoder {",
            expectedProviderIDs: ["claude", "helmcode", "qoder"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["qoder@0", "qoder@3", "helmcode@6", "claude@11"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+Actions.swift",
            line: 482,
            anchor: "?? (self.store.isEnabled(.codex) ? .codex : self.store.enabledFirstPartyProviders().first)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["codex@0", "codex@0", "codex@2", "codex@8"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+Actions.swift",
            line: 503,
            anchor: "?? (self.store.isEnabled(.codex) ? .codex : self.store.enabledFirstPartyProviders().first)",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["codex@0", "codex@0", "codex@2", "claude@10"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+Actions.swift",
            line: 576,
            anchor: "?? .codex",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+Actions.swift",
            line: 645,
            anchor: "self.lazyStatusItem(for: provider ?? .codex)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+Actions.swift",
            line: 716,
            anchor: "return .codex",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+Animation.swift",
            line: 746,
            anchor: "guard style == .warp, let phase else { return self.blinkAmount(for: provider) }",
            expectedProviderIDs: ["warp"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["warp@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+Animation.swift",
            line: 1061,
            anchor: "if provider == .kiro {",
            expectedProviderIDs: ["kiro"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["kiro@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+Animation.swift",
            line: 1075,
            anchor: "provider != .cursor || mode == .pace,",
            expectedProviderIDs: ["cursor"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["cursor@0"],
            reason: "Cursor's extra-usage spend is displayed only in pace mode."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+CostMenuCard.swift",
            line: 129,
            anchor: "+ [provider == .codex ? tokenUsage?.hintLine : nil].compactMap(\\.self)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared renderer maps provider-owned presentation data into the generic UI model."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+CountdownRefresh.swift",
            line: 166,
            anchor: "if providers.contains(.codex) {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@11"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+HostedSubmenus.swift",
            line: 508,
            anchor: "projects: provider == .codex ? tokenSnapshot.projects : [],",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@1"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+MemoryPressure.swift",
            line: 37,
            anchor: "scope: UsageProvider.codex.rawValue,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+UserPlugins.swift",
            line: 53,
            anchor: "let fallbackProviderID = (self.resolvedMenuProvider(enabledProviders: enabledProviders) ?? .codex).instanceID",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+Menu.swift",
            line: 1176,
            anchor: "return self.store.enabledFirstPartyProvidersForDisplay().first ?? .codex",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+MenuBarLayout.swift",
            line: 333,
            anchor: "if provider == .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+MenuCardModel.swift",
            line: 129,
            anchor: "?? (target == .codex ? codexPublicationHoldOverride",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "The live Codex card surfaces the provider-owned quota publication hold only for Codex."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+MenuSwitcherWarmup.swift",
            line: 118,
            anchor: "let currentProvider = selectedProvider ?? enabledProviders.first ?? .codex",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+MenuTracking.swift",
            line: 375,
            anchor: "if target == .kilo {",
            expectedProviderIDs: ["claude", "kilo"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["kilo@0", "claude@9"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+MenuTypes.swift",
            line: 14,
            anchor: "self.store.enabledProviders().isEmpty ? .codex : nil",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+MenuViewportRestore.swift",
            line: 611,
            anchor: "return .provider((self.resolvedMenuProvider() ?? .codex).instanceID)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+OverviewSubmenus.swift",
            line: 10,
            anchor: "if provider == .openai,",
            expectedProviderIDs: ["mistral", "openai"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["openai@0", "mistral@9"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+ProviderNavigation.swift",
            line: 63,
            anchor: "self.navigationResolvedProvider(enabledProviders: enabledProviders) ?? .codex",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@9"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+ProviderNavigation.swift",
            line: 91,
            anchor: "return .codex",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+SwitcherMetrics.swift",
            line: 20,
            anchor: "} else if provider == .mistral {",
            expectedProviderIDs: ["mistral"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["mistral@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController.swift",
            line: 925,
            anchor: "if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Accessors.swift",
            line: 65,
            anchor: "snapshot.accountEmail(for: .codex) ?? self.accountInfo(for: .codex).email),",
            expectedProviderIDs: ["codex", "deepseek"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: [
                "codex@0", "codex@0", "deepseek@12", "deepseek@18", "deepseek@18",
            ],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Accessors.swift",
            line: 156,
            anchor: "case .codex:",
            expectedProviderIDs: ["claude", "codex", "ollama"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["codex@0", "claude@2", "ollama@6"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+CodexCostCatchUp.swift",
            line: 83,
            anchor: "guard provider == .codex else { return }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This entry point starts Codex cost catch-up only in response to a Codex usage refresh."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+CodexCostCatchUp.swift",
            line: 100,
            anchor: "let providerConfigRevision = self.settings.providerConfigRevision(for: .codex)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "The paused catch-up scope records Codex's provider configuration revision so configuration changes invalidate its work."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+CodexCostCatchUp.swift",
            line: 511,
            anchor: "guard let currentPublication = self.tokenSnapshotPublicationForCurrentProviderConfig(for: .codex),",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@8"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+CodexCostCatchUp.swift",
            line: 557,
            anchor: "self.tokenSnapshotPublicationRevision(for: .codex) == publicationRevision,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 7,
            expectedReferenceFingerprint: [
                "codex@0",
                "codex@11",
                "codex@12",
                "codex@14",
                "codex@16",
                "codex@17",
                "codex@18",
            ],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+CodexCostCatchUp.swift",
            line: 1210,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Stable Codex catch-up publication compares the Codex revision before replacing the provider snapshot."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+CodexCostCatchUp.swift",
            line: 1232,
            anchor: "self.tokenSnapshotPublicationRevision(for: .codex) == publicationRevision",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 13,
            expectedReferenceFingerprint: [
                "codex@0",
                "codex@1",
                "codex@3",
                "codex@6",
                "codex@11",
                "codex@12",
                "codex@14",
                "codex@15",
                "codex@15",
                "codex@17",
                "codex@19",
                "codex@20",
                "codex@22",
            ],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+CodexCostCatchUp.swift",
            line: 1284,
            anchor: "&& self.settings.providerConfigRevision(for: .codex) == context.providerConfigRevision",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 6,
            expectedReferenceFingerprint: ["codex@0", "codex@8", "codex@11", "codex@12", "codex@13", "codex@14"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+HighestUsage.swift",
            line: 117,
            anchor: "if provider == .cursor,",
            expectedProviderIDs: ["cursor"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["cursor@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+HistoricalPace.swift",
            line: 221,
            anchor: "let codexSnapshot = self.snapshots[.codex]",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+LimitResetCelebration.swift",
            line: 325,
            anchor: "if input.provider == .codex, input.codexCorrectsWeeklyBoundary {",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["codex@0", "claude@9", "codex@10"],
            reason: "Codex boundary corrections take a dedicated no-reset transition while Claude weekly recovery keeps its own detector state."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+LimitResetCelebration.swift",
            line: 213,
            anchor: "let requiresLowConfirmation = context.provider == .claude",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "Claude weekly reset recovery state applies only to Claude observations."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+LimitResetCelebration.swift",
            line: 569,
            anchor: "if input.provider == .codex, input.seriesName == .weekly {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex weekly reset celebrations require provider-owned boundary evidence."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+LimitResetCelebration.swift",
            line: 586,
            anchor: "snapshot.loginMethod(for: .codex)?",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex weekly reset confirmation reads the provider-owned plan identifier."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+LimitResetCelebration.swift",
            line: 195,
            anchor: "if context.provider == .codex, context.codexCorrectsWeeklyBoundary { return }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "A Codex correction without a detector observation suppresses a restored-session notice that could imply a reset."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+LimitResetCelebration.swift",
            line: 235,
            anchor: "let notice: LimitResetNotice? = if context.provider == .codex, context.codexCorrectsWeeklyBoundary {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "A Codex boundary correction updates detector state without producing another reset notice or replacing its dedup receipt."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+LimitResetIdentity.swift",
            line: 11,
            anchor: "if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+MenuCardModel.swift",
            line: 121,
            anchor: "?? (provider == .codex ? account?.codexPublicationHold",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "The Codex account menu card surfaces its provider-owned quota publication hold only for Codex."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+OpenAIWeb.swift",
            line: 386,
            anchor: "guard self.lastSourceLabels[.codex] == \"openai-web\" else { return }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+OpenAIWeb.swift",
            line: 405,
            anchor: "if self.snapshots[.codex] != nil,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+OpenAIWeb.swift",
            line: 452,
            anchor: "guard self.isEnabled(.codex),",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+PlanUtilization.swift",
            line: 209,
            anchor: "var providerBuckets = self.planUtilizationHistory[.codex] ?? PlanUtilizationHistoryBuckets()",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+PlanUtilization.swift",
            line: 226,
            anchor: "self.planUtilizationHistory[.codex] = providerBuckets",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+PlanUtilization.swift",
            line: 1002,
            anchor: "!key.hasPrefix(\"\\(UsageProvider.codex.rawValue):\")",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Legacy Codex reset evidence is discarded unless it carries the current provider-owned schema."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+PlanUtilization.swift",
            line: 280,
            anchor: "let samples = provider == .antigravity",
            expectedProviderIDs: ["antigravity", "claude"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["antigravity@0", "claude@9"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+PlanUtilization.swift",
            line: 303,
            anchor: "let detectorAccountKey = if provider == .claude, isClaudeOAuthSample {",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["claude@0", "claude@9"],
            reason: "Claude OAuth history requires corroborated ownership before reset detection or persistence."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+PlanUtilization.swift",
            line: 368,
            anchor: "if provider == .antigravity,",
            expectedProviderIDs: ["antigravity", "claude", "codex"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["antigravity@0", "antigravity@8", "claude@8", "codex@8"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+PlanUtilization.swift",
            line: 916,
            anchor: "if provider == .claude {",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "claude@3"],
            reason: "Codex and Claude history use different provider-owned account discriminators."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+PlanUtilization.swift",
            line: 961,
            anchor: "guard let identity = snapshot.identity(for: .claude) else { return nil }",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["claude@0", "claude@9", "claude@9"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+PlanUtilization.swift",
            line: 988,
            anchor: "key.hasPrefix(\"\\(UsageProvider.claude.rawValue):\")",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+PlanUtilization.swift",
            line: 1428,
            anchor: "if ![UsageProvider.codex, .claude, .antigravity].contains(provider) {",
            expectedProviderIDs: ["antigravity", "claude", "codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["antigravity@0", "claude@0", "codex@0"],
            reason: "These three providers retain owner-scoped legacy session-equivalent histories."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+ProviderStorage.swift",
            line: 253,
            anchor: "guard uniqueProviders.contains(.codex) else { return providerKey }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+QuotaWarnings.swift",
            line: 103,
            anchor: "let extraWindows = provider == .claude",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+QuotaWarnings.swift",
            line: 141,
            anchor: "guard provider == .claude else { return }",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 355,
            anchor: "let codexExplicitPAT = provider == .codex && self.settings.codexUsageDataSource == .pat",
            expectedProviderIDs: [
                "claude",
                "codex",
                "kilo",
            ],
            expectedReferenceCount: 7,
            expectedReferenceFingerprint: [
                "codex@0",
                "codex@1",
                "codex@10",
                "codex@15",
                "kilo@19",
                "kilo@25",
                "claude@29",
            ],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 337,
            anchor: "previousSourceLabel: hydratedPrior?.sourceLabel ?? self.lastSourceLabels[.codex],",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex refresh preparation restores the provider-owned prior source label."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 414,
            anchor: "let priorClaudeSourceLabel = provider == .claude ? self.lastSourceLabels[.claude] : nil",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["claude@0", "claude@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 428,
            anchor: "guard provider == .codex else { return outcome }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 450,
            anchor: "if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@6"],
            reason: "Codex publication admission verifies both the provider branch and its scoped result."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 488,
            anchor: "usage: result.usage.scoped(to: .codex))",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex publication admission revalidates the admitted result against its expected owner."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 581,
            anchor: "guard input.provider == .claude else {",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 739,
            anchor: "if provider == .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 787,
            anchor: "let isClaudeOAuthSample = provider == .claude",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "Claude OAuth history samples require credential-ownership evidence before persistence."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 835,
            anchor: "if provider == .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@10"],
            reason: "Codex success publication revalidates ownership and selects its reset backfill source."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 880,
            anchor: "codexOwnerKey: provider == .codex ? context.codexSessionQuotaOwnerKey : nil,",
            expectedProviderIDs: ["claude", "codex", "deepseek", "xai"],
            expectedReferenceCount: 7,
            expectedReferenceFingerprint: [
                "claude@0",
                "codex@5",
                "claude@10",
                "claude@11",
                "codex@13",
                "deepseek@19",
                "xai@26",
            ],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 921,
            anchor: "if provider == .gemini {",
            expectedProviderIDs: ["codex", "gemini"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["gemini@0", "codex@5"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 820,
            anchor: "if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex successful refreshes alone publish the provider-owned historical sample."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 961,
            anchor: "provider == .antigravity && result.strategyID == \"antigravity.offline\"",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["antigravity@0"],
            reason: "Antigravity offline results use a provider-owned strategy identifier and ownership policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 983,
            anchor: "if provider == .codex,",
            expectedProviderIDs: ["codex", "deepseek"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["codex@0", "deepseek@11", "deepseek@19", "codex@29"],
            reason: "Failure handling preserves Codex ownership and DeepSeek profile-transition state."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 1051,
            anchor: "guard provider == .deepseek else { return snapshot }",
            expectedProviderIDs: ["codex", "deepseek"],
            expectedReferenceCount: 7,
            expectedReferenceFingerprint: [
                "codex@0", "deepseek@10", "deepseek@11", "codex@18", "codex@26", "codex@37", "codex@38",
            ],
            reason: "Codex publication backfills reset windows while DeepSeek publication preserves the selected profile catalog."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 1129,
            anchor: "guard provider == .claude, !hasSelectedTokenAccount else { return false }",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 1496,
            anchor: "if provider == .gemini, Self.isGeminiConsumerTierDeprecationError(error) {",
            expectedProviderIDs: ["claude", "gemini"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["gemini@0", "claude@12"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 1540,
            anchor: "if provider == .claude,",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "Claude subscription-quota unavailability clears provider-owned stale limits."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 1556,
            anchor: "if provider == .claude,",
            expectedProviderIDs: ["antigravity", "claude", "deepseek"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["claude@0", "claude@11", "antigravity@19", "claude@20", "deepseek@25"],
            reason: "Claude recovery and Antigravity offline fallback preserve provider-owned last-good quota state."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 1664,
            anchor: "cached.cacheKey == self.tokenAccountSnapshotCacheKey(provider: .claude, account: currentAccount)",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+SessionEquivalents.swift",
            line: 183,
            anchor: "guard ![UsageProvider.codex, .claude, .antigravity].contains(provider) else { return true }",
            expectedProviderIDs: ["antigravity", "claude", "codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["antigravity@0", "claude@0", "codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+SpendDashboardCodexCostCatchUp.swift",
            line: 44,
            anchor: "self.tokenCostScope(for: .codex).codexHomePath == nil",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "The live Codex dashboard shares the primary scanner only when its cache scope matches the ambient Codex scope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+SpendDashboardCodexCostCatchUp.swift",
            line: 134,
            anchor: "self.settings.isCostUsageEffectivelyEnabled(for: .codex),",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@1"],
            reason: "Codex spend catch-up starts only while its provider-owned feature and account are enabled."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+SpendDashboardCodexCostCatchUp.swift",
            line: 174,
            anchor: "let providerConfigRevision = self.settings.providerConfigRevision(for: .codex)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Independent Codex account catch-up binds its pause key to the current Codex configuration revision."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 491,
            anchor: "let expectedClaudeQuotaOwnerKey: String? = if swapOwnsClaude {",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["claude@0", "claude@5"],
            reason: "This exact widget projection validates preserved Claude usage against the selected owner."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 193,
            anchor: "let expectedClaudeQuotaOwnerKey = snapshot.entries.contains { $0.provider == .claude }",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["claude@0", "claude@11", "claude@12", "claude@20"],
            reason: "Persisted Claude widget usage is retained only after validating ownership against the selected Claude account."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 514,
            anchor: "(provider == .claude && (storedTokenSnapshot != nil || preservedClaudeUsage != nil))",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 539,
            anchor: "if provider == .codex, let snapshot {",
            expectedProviderIDs: ["claude", "codex", "deepseek", "devin", "openrouter"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["codex@0", "devin@12", "claude@19", "deepseek@31", "openrouter@33"],
            reason: "The widget projection passes Codex credits, Devin cost, Claude owner state, and DeepSeek/OpenRouter balance-only text into provider entries."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 627,
            anchor: "if let account = self.settings.effectiveSelectedTokenAccount(for: .claude) {",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["claude@0", "claude@11", "claude@18", "claude@21", "claude@28"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 703,
            anchor: "let sessionLabel = if provider == .bedrock || provider == .mistral {",
            expectedProviderIDs: ["bedrock", "codex", "mistral"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["bedrock@0", "mistral@0", "codex@2", "codex@8"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 733,
            anchor: "if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 752,
            anchor: "if provider == .claude,",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 787,
            anchor: "let secondaryTitle = if provider == .amp {",
            expectedProviderIDs: ["alibabatokenplan", "amp", "antigravity", "cursor"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: [
                "antigravity@0", "antigravity@6", "cursor@14", "amp@22", "alibabatokenplan@24",
            ],
            reason: "This exact widget projection preserves QuotaKit's provider-specific secondary-window labels."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 812,
            anchor: "if provider == .kimi {",
            expectedProviderIDs: ["claude", "kimi"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["kimi@0", "claude@12"],
            reason: "This exact widget projection preserves Kimi balance details and Claude reset-credit inventory."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore.swift",
            line: 681,
            anchor: "self.metadata(for: .codex).browserCookieOrder ?? Browser.defaultImportOrder",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore.swift",
            line: 733,
            anchor: "self.providerSpecs[provider]?.style ?? .codex",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore.swift",
            line: 775,
            anchor: "guard provider != .codex else { return true }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore.swift",
            line: 1102,
            anchor: "let claudeDebugConfiguration: ClaudeDebugLogConfiguration? = if provider == .claude {",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore.swift",
            line: 1125,
            anchor: "let deepSeekHasTokenAccount = self.settings.selectedTokenAccount(for: .deepseek) != nil",
            expectedProviderIDs: ["deepseek"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["deepseek@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore.swift",
            line: 1182,
            anchor: "case .amp:",
            expectedProviderIDs: ["amp", "deepseek", "notion", "ollama", "warp"],
            expectedReferenceCount: 7,
            expectedReferenceFingerprint: [
                "amp@0",
                "ollama@5",
                "notion@10",
                "warp@16",
                "warp@17",
                "deepseek@21",
                "deepseek@24",
            ],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore.swift",
            line: 1237,
            anchor: "let claudeSettings = snapshot.claude ?? ProviderSettingsSnapshot.ClaudeProviderSettings(",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCLI/CLICardsCommand.swift",
            line: 170,
            anchor: "includeAllCodexAccounts: tokenSelection.allAccounts && providerList == [.codex],",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact CLI construct preserves the provider-specific command and output contract."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCLI/CLIUsageCommand.swift",
            line: 208,
            anchor: "includeAllCodexAccounts: tokenSelection.allAccounts && providerList == [.codex],",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact CLI construct preserves the provider-specific command and output contract."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/AgentSession.swift",
            line: 262,
            anchor: "return AgentSession.Provider.claude.rawValue",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact host integration normalizes the Claude Desktop wrapper to its agent provider name."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/AgentSession.swift",
            line: 295,
            anchor: "if basename == AgentSession.Provider.codex.rawValue {",
            expectedProviderIDs: ["claude", "codex", "pi"],
            expectedReferenceCount: 7,
            expectedReferenceFingerprint: [
                "codex@0", "claude@7", "claude@10", "claude@18", "pi@26", "claude@30", "pi@33",
            ],
            reason: "This exact host integration maps a provider-owned process, path, or window contract."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/AgentSession.swift",
            line: 364,
            anchor: "guard self.provider(for: record) == .claude else { return .cli }",
            expectedProviderIDs: ["claude", "codex", "pi"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["pi@0", "pi@1", "claude@13", "codex@19", "codex@27"],
            reason: "This exact host integration identifies ChatGPT Codex app-server candidates before verifying their running executable."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/AgentSession.swift",
            line: 431,
            anchor: "AgentProcessPath.basename($0) == AgentSession.Provider.claude.rawValue",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact host integration strips the Claude executable from normalized process arguments."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CodexLocalDataScope.swift",
            line: 29,
            anchor: "return self.make(home: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(\".codex\"))",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Config/CodexBarConfig.swift",
            line: 276,
            anchor: "region: provider == .alibabatokenplan ? alibabaTokenPlanRegion.rawValue : nil)",
            expectedProviderIDs: ["alibabatokenplan"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["alibabatokenplan@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/LocalAgentSessionScanner.swift",
            line: 225,
            anchor: "guard AgentPSOutputParser.provider(for: process) == .codex else { return nil }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@4"],
            reason: "This exact host integration maps a provider-owned process, path, or window contract."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/LocalAgentSessionScanner.swift",
            line: 542,
            anchor: "let claudeProcesses = processes.filter { AgentPSOutputParser.provider(for: $0) == .claude }",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact host integration maps a provider-owned process, path, or window contract."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/LocalAgentSessionScanner.swift",
            line: 558,
            anchor: "let codexProcesses = processes.filter { AgentPSOutputParser.provider(for: $0) == .codex }",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["codex@0", "claude@9", "claude@13"],
            reason: "This exact host integration maps a provider-owned process, path, or window contract."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/LocalAgentSessionScanner.swift",
            line: 584,
            anchor: "case .codex:",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact host integration maps a provider-owned process, path, or window contract."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/OpenAIDashboardModels.swift",
            line: 192,
            anchor: "provider: UsageProvider = .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardBrowserCookieImporter.swift",
            line: 107,
            anchor: "ProviderDefaults.metadata[.codex]?.browserCookieOrder ?? Browser.defaultImportOrder",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/ProviderEndpointOverrideValidator.swift",
            line: 9,
            anchor: "case let .minimax(key):",
            expectedProviderIDs: ["minimax"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["minimax@0"],
            reason: "This exact error branch renders the MiniMax-specific endpoint validation failure."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/PathEnvironment.swift",
            line: 625,
            anchor: "let legacyDirectory = \"codex\"",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact binary locator follows the npm Codex package's fixed nested executable path."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/ProviderStorageFootprint.swift",
            line: 309,
            anchor: "case .codex:",
            expectedProviderIDs: ["claude", "codex", "copilot", "cursor", "gemini", "opencode", "opencodego"],
            expectedReferenceCount: 10,
            expectedReferenceFingerprint: [
                "codex@0",
                "claude@3",
                "claude@5",
                "gemini@11",
                "gemini@13",
                "opencode@16",
                "opencodego@16",
                "copilot@20",
                "cursor@24",
                "cursor@28",
            ],
            reason: "This exact shared provider integration dispatches a capability owned by the provider descriptor or adapter."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Providers/ProviderCredentialAdapter.swift",
            line: 57,
            anchor: "} else if provider == .stepfun, self.config?.sanitizedRegion != nil {",
            expectedProviderIDs: ["stepfun"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["stepfun@0"],
            reason: "This exact shared provider integration dispatches a capability owned by the provider descriptor or adapter."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Providers/ProviderDiagnosticExport.swift",
            line: 451,
            anchor: "case \"minimax\":",
            expectedProviderIDs: ["minimax"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["minimax@0"],
            reason: "This exact Codable branch reads the stable MiniMax diagnostic-detail wire discriminator."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Providers/ProviderDiagnosticExport.swift",
            line: 464,
            anchor: "case let .minimax(details):",
            expectedProviderIDs: ["minimax"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["minimax@0", "minimax@1"],
            reason: "This exact Codable branch writes the stable MiniMax diagnostic-detail wire discriminator."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Providers/ProviderDiagnosticExport.swift",
            line: 598,
            anchor: "guard provider == .minimax else { return nil }",
            expectedProviderIDs: ["minimax"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["minimax@0", "minimax@1"],
            reason: "This exact shared provider integration dispatches a capability owned by the provider descriptor or adapter."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Providers/ProviderFetchPlan.swift",
            line: 297,
            anchor: "if provider == .kiro {",
            expectedProviderIDs: ["kiro"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["kiro@0"],
            reason: "This exact shared provider integration dispatches a capability owned by the provider descriptor or adapter."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/SessionWindowFocuser.swift",
            line: 70,
            anchor: "case (.claude, .desktopApp): \"com.anthropic.claudefordesktop\"",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["claude@0", "codex@1"],
            reason: "This exact host integration maps a provider-owned process, path, or window contract."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/UsageSnapshot+SwitcherWeeklyWindow.swift",
            line: 11,
            anchor: "case .factory:",
            expectedProviderIDs: ["cursor", "factory", "perplexity"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["factory@0", "perplexity@3", "cursor@5"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/UsageSnapshot+SwitcherWeeklyWindow.swift",
            line: 44,
            anchor: "case .claude:",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["claude@0", "claude@8"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift",
            line: 214,
            anchor: "guard let pricing = self.codex[model] else { continue }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact cost scanner dispatch selects a provider-owned transcript, cache, or pricing format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift",
            line: 458,
            anchor: "static let codexModelsDevProviderID = \"openai\"",
            expectedProviderIDs: ["deepseek", "openai", "opencode"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["openai@0", "deepseek@7", "openai@10", "opencode@11"],
            reason: "This exact cost scanner dispatch selects a provider-owned transcript, cache, or pricing format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift",
            line: 526,
            anchor: "if self.codex[trimmed] != nil {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@6"],
            reason: "This exact cost scanner dispatch selects a provider-owned transcript, cache, or pricing format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift",
            line: 569,
            anchor: "if self.claude[base] != nil {",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact cost scanner dispatch selects a provider-owned transcript, cache, or pricing format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift",
            line: 792,
            anchor: "self.codex[self.normalizeCodexModel(raw)] != nil",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["codex@0", "codex@5", "codex@14"],
            reason: "This exact Codex pricing boundary normalizes model families before fallback pricing."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift",
            line: 920,
            anchor: "self.claude[self.normalizeClaudeModel(raw)] != nil",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["claude@0", "claude@5", "claude@14"],
            reason: "This exact Claude pricing boundary normalizes model families before fallback pricing."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift",
            line: 493,
            anchor: "providerIDs.append(\"opencode\")",
            expectedProviderIDs: ["opencode"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["opencode@0"],
            reason: "This exact cost scanner dispatch selects a provider-owned transcript, cache, or pricing format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Vendored/CostUsage/ModelsDevPricing.swift",
            line: 79,
            anchor: "[\"anthropic\", \"openai\"].allSatisfy { providerID in",
            expectedProviderIDs: ["openai"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["openai@0"],
            reason: "This exact cost scanner dispatch selects a provider-owned transcript, cache, or pricing format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Logging/LogCategories.swift",
            line: 3,
            anchor: "let base = instanceID.firstPartyProvider == .opencodego ? \"opencode-go\" : instanceID.rawValue",
            expectedProviderIDs: [
                "abacus",
                "amp",
                "antigravity",
                "augment",
                "bedrock",
                "claude",
                "codex",
                "commandcode",
                "copilot",
                "cursor",
                "deepgram",
                "deepseek",
                "devin",
                "doubao",
                "elevenlabs",
                "gemini",
                "opencodego",
            ],
            expectedReferenceCount: 23,
            expectedReferenceFingerprint: [
                "opencodego@0",
                "abacus@8",
                "abacus@9",
                "amp@11",
                "antigravity@12",
                "augment@15",
                "augment@16",
                "bedrock@17",
                "claude@19",
                "claude@20",
                "claude@21",
                "codex@22",
                "commandcode@23",
                "commandcode@24",
                "copilot@30",
                "cursor@32",
                "deepseek@33",
                "deepseek@34",
                "deepgram@35",
                "devin@36",
                "doubao@37",
                "elevenlabs@38",
                "gemini@39",
            ],
            reason: "These exact aliases preserve established provider subsystem category strings while generic logging migrates to provider(scope:)."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Logging/LogCategories.swift",
            line: 43,
            anchor: "public static let grok = Self.provider(.grok)",
            expectedProviderIDs: [
                "grok",
                "kimi",
                "kiro",
                "longcat",
                "manus",
                "mimo",
                "minimax",
                "moonshot",
                "neuralwatt",
                "notion",
                "ollama",
                "openai",
                "opencode",
                "opencodego",
                "openrouter",
                "perplexity",
            ],
            expectedReferenceCount: 30,
            expectedReferenceFingerprint: [
                "grok@0",
                "kimi@6",
                "kimi@7",
                "kimi@8",
                "kimi@9",
                "kiro@10",
                "longcat@11",
                "longcat@12",
                "longcat@13",
                "manus@17",
                "manus@18",
                "manus@19",
                "minimax@21",
                "minimax@22",
                "minimax@23",
                "minimax@24",
                "minimax@25",
                "mimo@26",
                "moonshot@27",
                "neuralwatt@28",
                "notion@30",
                "openai@31",
                "openai@32",
                "ollama@33",
                "opencode@34",
                "opencodego@35",
                "openrouter@36",
                "perplexity@37",
                "perplexity@38",
                "perplexity@39",
            ],
            reason: "These exact aliases preserve established provider subsystem category strings while generic logging migrates to provider(scope:)."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Logging/LogCategories.swift",
            line: 85,
            anchor: "public static let poeUsage = Self.provider(.poe, scope: \"usage\")",
            expectedProviderIDs: [
                "poe",
                "qoder",
                "stepfun",
                "synthetic",
                "t3chat",
                "venice",
                "vertexai",
                "warp",
                "zai",
                "zed",
                "zoommate",
            ],
            expectedReferenceCount: 15,
            expectedReferenceFingerprint: [
                "poe@0",
                "qoder@3",
                "qoder@4",
                "synthetic@10",
                "synthetic@11",
                "t3chat@12",
                "venice@17",
                "vertexai@18",
                "warp@19",
                "zed@20",
                "zai@22",
                "zai@23",
                "zai@24",
                "stepfun@25",
                "zoommate@26",
            ],
            reason: "These exact aliases preserve established provider subsystem category strings while generic logging migrates to provider(scope:)."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Pricing/ClaudeFamilyResolver.swift",
            line: 17,
            anchor: "let providerKey = \"claude\"",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This resolver is the Claude-specific pricing-family normalization boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Pricing/CodexFamilyResolver.swift",
            line: 26,
            anchor: "let providerKey = \"codex\"",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This resolver is the Codex-specific pricing-family normalization boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Sync/AccountIdentityComputer.swift",
            line: 56,
            anchor: "case .codex:",
            expectedProviderIDs: [
                "abacus",
                "aiand",
                "aixy",
                "alibaba",
                "alibabatokenplan",
                "amp",
                "antigravity",
                "atlascloud",
                "augment",
                "azureopenai",
                "bedrock",
                "bifrost",
                "chutes",
                "claude",
                "clawrouter",
                "clinepass",
                "codebuff",
                "coderabbit",
                "codex",
                "commandcode",
                "copilot",
                "cursor",
                "deepgram",
                "deepinfra",
                "deepseek",
                "devin",
                "devpass",
                "doubao",
                "elevenlabs",
                "factory",
                "fireworks",
                "gemini",
                "gitkraken",
                "grok",
                "groq",
                "helmcode",
                "huggingface",
                "hyper",
                "ibmbob",
                "jetbrains",
                "kilo",
                "kimi",
                "kiro",
                "langdock",
                "litellm",
                "lithosai",
                "llmman",
                "llmproxy",
                "longcat",
                "manus",
                "mimo",
                "minimax",
                "mistral",
                "moonshot",
                "muse",
                "museai",
                "neuralwatt",
                "notion",
                "nous",
                "ollama",
                "openai",
                "opencode",
                "opencodego",
                "openrouter",
                "perplexity",
                "pi",
                "poe",
                "qoder",
                "qwencloud",
                "raycast",
                "replicate",
                "sakana",
                "stepfun",
                "sub2api",
                "synthetic",
                "t3chat",
                "typesafe",
                "v0",
                "venice",
                "vercel",
                "vertexai",
                "warp",
                "wayfinder",
                "windsurf",
                "workbuddy",
                "xai",
                "xapi",
                "xkiro",
                "zai",
                "zed",
                "zenmux",
                "zoommate",
            ],
            expectedReferenceCount: 92,
            expectedReferenceFingerprint: [
                "codex@0",
                "claude@2",
                "vertexai@4",
                "replicate@6",
                "copilot@8",
                "alibaba@12",
                "antigravity@12",
                "cursor@12",
                "factory@12",
                "gemini@12",
                "opencode@12",
                "opencodego@12",
                "zai@12",
                "amp@13",
                "augment@13",
                "jetbrains@13",
                "kilo@13",
                "kimi@13",
                "kiro@13",
                "minimax@13",
                "ollama@13",
                "synthetic@13",
                "abacus@14",
                "mistral@14",
                "openrouter@14",
                "perplexity@14",
                "warp@14",
                "deepseek@20",
                "doubao@20",
                "manus@20",
                "mimo@20",
                "openai@20",
                "windsurf@20",
                "codebuff@21",
                "commandcode@21",
                "stepfun@21",
                "venice@21",
                "bedrock@25",
                "moonshot@25",
                "deepgram@29",
                "elevenlabs@29",
                "grok@29",
                "groq@29",
                "litellm@29",
                "llmproxy@29",
                "alibabatokenplan@33",
                "azureopenai@33",
                "t3chat@33",
                "chutes@35",
                "clawrouter@35",
                "devin@35",
                "poe@35",
                "qoder@35",
                "sakana@35",
                "sub2api@35",
                "wayfinder@35",
                "xai@35",
                "zed@35",
                "aiand@36",
                "clinepass@36",
                "deepinfra@36",
                "longcat@36",
                "neuralwatt@36",
                "notion@36",
                "qwencloud@36",
                "zenmux@36",
                "zoommate@36",
                "coderabbit@37",
                "fireworks@37",
                "gitkraken@37",
                "huggingface@37",
                "hyper@37",
                "ibmbob@37",
                "v0@37",
                "aixy@38",
                "bifrost@38",
                "devpass@38",
                "helmcode@38",
                "raycast@38",
                "typesafe@38",
                "xkiro@38",
                "atlascloud@39",
                "langdock@39",
                "lithosai@39",
                "llmman@39",
                "muse@39",
                "museai@39",
                "nous@39",
                "pi@39",
                "vercel@39",
                "workbuddy@39",
                "xapi@39",
            ],
            reason: "This exhaustive fallback preserves stable Mac-to-iOS account grouping for providers without Tier-A identity data, including MuseAI's explicit nil-identity branch."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+QuotaWarningState.swift",
            line: 45,
            anchor: "static let codex = Self(provider: .codex)",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "claude@1"],
            reason: "These canonical keys preserve separate Codex and Claude quota-warning state for unscoped accounts."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+QuotaWarnings.swift",
            line: 23,
            anchor: "if provider == .commandcode, snapshot.commandCodeSubscriptionEnrichmentUnavailable {",
            expectedProviderIDs: ["commandcode"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["commandcode@0"],
            reason: "This exact warning-evaluation branch preserves provider-specific enrichment, owner, and balance semantics before threshold transitions."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+QuotaWarnings.swift",
            line: 378,
            anchor: "if provider != .commandcode,",
            expectedProviderIDs: ["commandcode"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["commandcode@0"],
            reason: "Command Code login metadata includes a changing credit balance and cannot serve as a stable warning identity."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+QuotaWarnings.swift",
            line: 497,
            anchor: "if provider == .commandcode,",
            expectedProviderIDs: ["codex", "commandcode"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["commandcode@0", "codex@6", "codex@15", "commandcode@21", "codex@24"],
            reason: "This exact transition gate handles Command Code enrichment gaps and Codex owner-scoped baseline resets."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+QuotaWarnings.swift",
            line: 543,
            anchor: "guard provider == .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex session warnings reject observations older than the current account baseline requirement."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+QuotaWarnings.swift",
            line: 476,
            anchor: "if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "A successfully evaluated Codex observation clears its one-shot fresh-baseline requirement."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+QuotaWarnings.swift",
            line: 461,
            anchor: "let forceBaseline = provider == .codex && self.codexSessionQuotaBaselineRequirement != nil",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex owner changes ignore the prior transition until a fresh session observation establishes its new baseline."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuDescriptor.swift",
            line: 423,
            anchor: "let hasQuotaKitXAIUsage = provider == .xai && snapshot.xaiUsage != nil",
            expectedProviderIDs: ["xai"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["xai@0", "xai@1"],
            reason: "QuotaKit renders xAI balance rows from its product-owned xAI usage extension."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuDescriptor.swift",
            line: 795,
            anchor: "} else if provider == .amp {",
            expectedProviderIDs: ["alibabatokenplan", "amp"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["amp@0", "alibabatokenplan@2"],
            reason: "Amp and Alibaba Token Plan compute weekly labels from provider-specific secondary-window metadata."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/PreferencesMobilePane.swift",
            line: 223,
            anchor: "self.runTestPush(provider: \"Codex\", providerID: \"codex\", state: \"depleted\")",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 6,
            expectedReferenceFingerprint: ["codex@0", "codex@6", "codex@11", "claude@21", "claude@27", "claude@32"],
            reason: "The mobile developer pane exposes paired Codex and Claude test-push controls for depleted, low, and restored states."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/PreferencesMobilePane.swift",
            line: 554,
            anchor: "(\"Codex\", \"codex\", \"session\", 50),",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["codex@0", "claude@1", "codex@2", "claude@3", "codex@4"],
            reason: "The deterministic burst fixture alternates Codex and Claude warning windows to verify CloudKit record uniqueness."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SettingsStore+TokenAccounts.swift",
            line: 265,
            anchor: "guard provider == .zai,",
            expectedProviderIDs: ["zai"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["zai@0"],
            reason: "Z.ai team-scope credentials uniquely require an organization or workspace identifier."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SettingsStore.swift",
            line: 908,
            anchor: "switch MenuBarMetricPreference(rawValue: migrated[UsageProvider.antigravity.rawValue] ?? \"\") {",
            expectedProviderIDs: ["antigravity", "cursor"],
            expectedReferenceCount: 8,
            expectedReferenceFingerprint: [
                "antigravity@0",
                "antigravity@2",
                "antigravity@4",
                "antigravity@6",
                "cursor@17",
                "cursor@19",
                "cursor@21",
                "cursor@23",
            ],
            reason: "One-time schema migrations remap Antigravity two-pool metrics and Cursor request-plan metrics from their historical meanings."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+HostedSubmenus.swift",
            line: 94,
            anchor: "static let statusComponentsSubmenuProviders: Set<UsageProvider> = [.claude, .codex, .augment, .zoommate]",
            expectedProviderIDs: ["augment", "claude", "codex", "zoommate"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["augment@0", "claude@0", "codex@0", "zoommate@0"],
            reason: "This curated set is limited to provider feeds whose live components are trusted for native submenu rendering."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 913,
            anchor: "if provider == .cursor {",
            expectedProviderIDs: ["cursor"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["cursor@0"],
            reason: "Cursor's widget primary label follows its persisted request, plan, or API-only rate-window layout."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 927,
            anchor: "if provider == .grok,",
            expectedProviderIDs: ["alibabatokenplan", "amp", "doubao", "grok", "opencode", "qwencloud"],
            expectedReferenceCount: 6,
            expectedReferenceFingerprint: [
                "grok@0", "doubao@5", "amp@10", "opencode@15", "alibabatokenplan@20", "qwencloud@25",
            ],
            reason: "These providers derive compact widget labels from distinct primary or secondary quota-window metadata."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 250,
            anchor: "\"codex\", \"claude\", \"cursor\", \"opencode\", \"opencodego\",",
            expectedProviderIDs: [
                "abacus",
                "alibaba",
                "alibabatokenplan",
                "amp",
                "antigravity",
                "augment",
                "azureopenai",
                "bedrock",
                "claude",
                "clinepass",
                "codebuff",
                "codex",
                "commandcode",
                "copilot",
                "cursor",
                "deepgram",
                "deepseek",
                "doubao",
                "elevenlabs",
                "factory",
                "gemini",
                "grok",
                "groq",
                "jetbrains",
                "kilo",
                "kimi",
                "kiro",
                "llmproxy",
                "manus",
                "mimo",
                "minimax",
                "mistral",
                "moonshot",
                "ollama",
                "openai",
                "opencode",
                "opencodego",
                "openrouter",
                "perplexity",
                "stepfun",
                "synthetic",
                "t3chat",
                "venice",
                "vertexai",
                "warp",
                "windsurf",
                "zai",
            ],
            expectedReferenceCount: 47,
            expectedReferenceFingerprint: [
                "claude@0",
                "codex@0",
                "cursor@0",
                "opencode@0",
                "opencodego@0",
                "alibaba@1",
                "antigravity@1",
                "copilot@1",
                "factory@1",
                "gemini@1",
                "kilo@2",
                "kimi@2",
                "kiro@2",
                "minimax@2",
                "zai@2",
                "amp@3",
                "augment@3",
                "clinepass@3",
                "jetbrains@3",
                "vertexai@3",
                "ollama@4",
                "openrouter@4",
                "perplexity@4",
                "synthetic@4",
                "warp@4",
                "abacus@5",
                "mistral@5",
                "doubao@8",
                "manus@8",
                "mimo@8",
                "openai@8",
                "windsurf@8",
                "codebuff@9",
                "commandcode@9",
                "deepseek@9",
                "venice@9",
                "stepfun@10",
                "bedrock@12",
                "moonshot@12",
                "deepgram@14",
                "elevenlabs@14",
                "grok@14",
                "groq@14",
                "llmproxy@14",
                "alibabatokenplan@17",
                "azureopenai@17",
                "t3chat@17",
            ],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 400,
            anchor: "providerID: \"codex\",",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 469,
            anchor: "providerID: \"codex\",",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 533,
            anchor: "providerID: \"codex\",",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 602,
            anchor: "providerID: \"claude\",",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 673,
            anchor: "providerID: \"claude\",",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 752,
            anchor: "providerID: \"perplexity\",",
            expectedProviderIDs: ["perplexity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["perplexity@0"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 984,
            anchor: "providerID: \"cursor\", providerName: \"Cursor\",",
            expectedProviderIDs: ["alibaba", "cursor", "factory", "opencode", "opencodego"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["cursor@0", "opencode@9", "opencodego@18", "alibaba@27", "factory@36"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1029,
            anchor: "providerID: \"gemini\", providerName: \"Gemini\",",
            expectedProviderIDs: ["antigravity", "copilot", "gemini", "zai"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["gemini@0", "antigravity@9", "copilot@18", "zai@27"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1069,
            anchor: "providerID: \"minimax\", providerName: \"MiniMax\",",
            expectedProviderIDs: ["kilo", "kimi", "kiro", "minimax", "vertexai"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["minimax@0", "kimi@9", "kilo@18", "kiro@27", "vertexai@36"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1118,
            anchor: "providerID: \"augment\", providerName: \"Augment\",",
            expectedProviderIDs: ["amp", "augment", "clinepass", "jetbrains"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["augment@0", "jetbrains@9", "clinepass@18", "amp@27"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1161,
            anchor: "providerID: \"ollama\", providerName: \"Ollama\",",
            expectedProviderIDs: ["ollama", "synthetic", "warp"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["ollama@0", "synthetic@9", "warp@18"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1192,
            anchor: "providerID: \"openrouter\", providerName: \"OpenRouter\",",
            expectedProviderIDs: ["abacus", "mistral", "openrouter"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["openrouter@0", "abacus@9", "mistral@18"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1227,
            anchor: "providerID: \"openai\", providerName: \"OpenAI\",",
            expectedProviderIDs: ["doubao", "manus", "mimo", "openai", "windsurf"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["openai@0", "manus@9", "windsurf@18", "mimo@27", "doubao@36"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1272,
            anchor: "providerID: \"deepseek\", providerName: \"DeepSeek\",",
            expectedProviderIDs: ["codebuff", "commandcode", "deepseek", "stepfun", "venice"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["deepseek@0", "codebuff@9", "venice@18", "commandcode@27", "stepfun@36"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1318,
            anchor: "providerID: \"moonshot\", providerName: \"Moonshot / Kimi API\",",
            expectedProviderIDs: ["bedrock", "moonshot"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["moonshot@0", "bedrock@9"],
            reason: "This deterministic fixture keeps Moonshot balance and Bedrock budget payloads together after StepFun starts the preceding sample cluster."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1344,
            anchor: "providerID: \"grok\", providerName: \"Grok\",",
            expectedProviderIDs: ["elevenlabs", "grok", "groq"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["grok@0", "groq@9", "elevenlabs@18"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1375,
            anchor: "providerID: \"deepgram\", providerName: \"Deepgram\",",
            expectedProviderIDs: ["deepgram", "llmproxy"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["deepgram@0", "llmproxy@9"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1401,
            anchor: "providerID: \"azureopenai\", providerName: \"Azure OpenAI\",",
            expectedProviderIDs: ["alibabatokenplan", "azureopenai", "t3chat"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["azureopenai@0", "alibabatokenplan@9", "t3chat@18"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1449,
            anchor: "providerID: \"openai\", providerName: \"OpenAI\",",
            expectedProviderIDs: ["antigravity", "copilot", "deepseek", "manus", "openai"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["openai@0", "deepseek@9", "antigravity@18", "manus@29", "copilot@38"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1496,
            anchor: "providerID: \"venice\", providerName: \"Venice\",",
            expectedProviderIDs: ["stepfun", "venice"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["venice@0", "stepfun@9"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1524,
            anchor: "case \"kiro\":",
            expectedProviderIDs: ["bedrock", "kiro", "moonshot", "zai"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["kiro@0", "bedrock@10", "moonshot@19", "zai@25"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1564,
            anchor: "case \"openai\":",
            expectedProviderIDs: ["openai"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["openai@0"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1593,
            anchor: "case \"antigravity\":",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["antigravity@0"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1609,
            anchor: "case \"openrouter\":",
            expectedProviderIDs: ["openrouter"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["openrouter@0"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/MockProviderInjector.swift",
            line: 1622,
            anchor: "case \"azureopenai\":",
            expectedProviderIDs: ["alibabatokenplan", "azureopenai", "deepseek"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["azureopenai@0", "alibabatokenplan@7", "deepseek@15"],
            reason: "This exact deterministic mobile-sync debug fixture pins provider-specific payload shapes; it is fixture data, not runtime provider-selection policy."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 12,
            anchor: "guard provider == .openai, let openai = snapshot?.openAIAPIUsage else { return nil }",
            expectedProviderIDs: ["openai"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["openai@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 61,
            anchor: "guard provider == .zai, let model = snapshot?.zaiUsage?.modelUsage else { return nil }",
            expectedProviderIDs: ["zai"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["zai@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 90,
            anchor: "guard provider == .kiro, let k = snapshot?.kiroUsage else { return nil }",
            expectedProviderIDs: ["kiro"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["kiro@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 127,
            anchor: "guard provider == .bedrock, let pc = providerCost else { return nil }",
            expectedProviderIDs: ["bedrock"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["bedrock@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 154,
            anchor: "guard provider == .moonshot else { return nil }",
            expectedProviderIDs: ["moonshot"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["moonshot@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 212,
            anchor: "guard provider == .grok, let g = snapshot?.grokUsage else { return nil }",
            expectedProviderIDs: ["grok"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["grok@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 246,
            anchor: "guard provider == .elevenlabs, let e = snapshot?.elevenLabsUsage else { return nil }",
            expectedProviderIDs: ["elevenlabs"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["elevenlabs@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 264,
            anchor: "guard provider == .deepgram, let d = snapshot?.deepgramUsage else { return nil }",
            expectedProviderIDs: ["deepgram"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["deepgram@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 282,
            anchor: "guard provider == .groq, let g = snapshot?.groqUsage else { return nil }",
            expectedProviderIDs: ["groq", "llmproxy"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["groq@0", "llmproxy@12"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 322,
            anchor: "guard provider == .claude, let a = snapshot?.claudeAdminAPIUsage else { return nil }",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 360,
            anchor: "guard provider == .claude else { return nil }",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 413,
            anchor: "guard provider == .opencodego,",
            expectedProviderIDs: ["opencodego"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["opencodego@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 428,
            anchor: "guard provider == .minimax,",
            expectedProviderIDs: ["minimax"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["minimax@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 485,
            anchor: "let paceLabel: String? = pace.map { UsagePaceText.weeklySummary(provider: .codex, pace: $0) }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 529,
            anchor: "guard provider == .mistral, let m = snapshot?.mistralUsage, !m.daily.isEmpty else {",
            expectedProviderIDs: ["mistral"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["mistral@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 554,
            anchor: "sourceRevisions: (snapshot?.updatedAt).map { [\"mistral\": $0] })",
            expectedProviderIDs: ["mistral", "openrouter"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["mistral@0", "openrouter@11"],
            reason: "Mistral's independent cost-source revision and the adjacent OpenRouter mapper preserve their provider-native mobile payload identity."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 588,
            anchor: "guard provider == .azureopenai, let a = snapshot?.azureOpenAIUsage else { return nil }",
            expectedProviderIDs: ["azureopenai"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["azureopenai@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 604,
            anchor: "guard provider == .alibabatokenplan,",
            expectedProviderIDs: ["alibabatokenplan"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["alibabatokenplan@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderMappers.swift",
            line: 625,
            anchor: "guard provider == .deepseek, let ds = snapshot?.deepseekUsage else { return nil }",
            expectedProviderIDs: ["deepseek"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["deepseek@0"],
            reason: "This exact mapper translates provider-native snapshot fields into the versioned Mac-to-iPhone wire envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 326,
            anchor: "tokenAccount: provider == .copilot",
            expectedProviderIDs: ["codex", "copilot"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["copilot@0", "copilot@1", "codex@5"],
            reason: "Copilot's selected account and Codex credits attach only to their respective mobile snapshots."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 646,
            anchor: "guard provider == .antigravity,",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["antigravity@0", "antigravity@1"],
            reason: "Antigravity multi-account records come from its token-account store and must retain their provider identity."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 676,
            anchor: "let codexProjection = provider == .codex",
            expectedProviderIDs: ["codex", "cursor"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "cursor@8"],
            reason: "Codex consumer projections supply account-scoped mobile rate windows without changing other providers' window payloads."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 729,
            anchor: "guard provider == .perplexity,",
            expectedProviderIDs: ["perplexity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["perplexity@0"],
            reason: "Perplexity's recurring and promotional credits map into its provider-specific mobile credit summary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 747,
            anchor: "let copilotAPIHost = provider == .copilot",
            expectedProviderIDs: ["copilot"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["copilot@0"],
            reason: "Copilot's selected GitHub host scopes mobile account identity across public and Enterprise accounts."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 766,
            anchor: "guard provider == .copilot, let tokenAccount,",
            expectedProviderIDs: ["copilot", "workbuddy"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["workbuddy@0", "copilot@1"],
            reason: "WorkBuddy omits public account identity while Copilot scopes readable mobile account keys by GitHub host."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 798,
            anchor: "let bedrockRegion: String? = provider == .bedrock ? {",
            expectedProviderIDs: ["bedrock"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["bedrock@0"],
            reason: "Bedrock's AWS region is read from its settings because the flattened usage snapshot omits that field."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 836,
            anchor: "let openCodeGoWorkspaceID: String? = provider == .opencodego ? {",
            expectedProviderIDs: ["opencodego"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["opencodego@0"],
            reason: "OpenCode Go's workspace identifier is settings-backed metadata required by its mobile envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 964,
            anchor: "if provider == .workbuddy {",
            expectedProviderIDs: ["workbuddy"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["workbuddy@0"],
            reason: "WorkBuddy sync exposes only finite credit balances and prevents account or credential details from leaving Mac."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderPresentation.swift",
            line: 16,
            anchor: "if provider == .aiand || provider == .fireworks, let providerCost {",
            expectedProviderIDs: [
                "aiand",
                "copilot",
                "fireworks",
                "grok",
                "lithosai",
                "opencode",
                "xai",
                "xapi",
            ],
            expectedReferenceCount: 8,
            expectedReferenceFingerprint: [
                "aiand@0",
                "fireworks@0",
                "opencode@5",
                "xai@14",
                "lithosai@18",
                "xapi@22",
                "grok@26",
                "copilot@36",
            ],
            reason: "These provider-native balance and spend summaries preserve their distinct mobile status wording."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCLI/DashboardSnapshotBuilder.swift",
            line: 469,
            anchor: "guard provider == .grok,",
            expectedProviderIDs: ["grok"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["grok@0"],
            reason: "Grok's purchased USD wallet uses the existing dashboard credits field separately from quota and spend."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator+ProviderPresentation.swift",
            line: 69,
            anchor: "guard provider != .zenmux,",
            expectedProviderIDs: [
                "aiand",
                "claude",
                "codex",
                "fireworks",
                "grok",
                "lithosai",
                "neuralwatt",
                "opencode",
                "xai",
                "xapi",
                "zenmux",
            ],
            expectedReferenceCount: 11,
            expectedReferenceFingerprint: [
                "zenmux@0",
                "neuralwatt@1",
                "aiand@2",
                "fireworks@3",
                "lithosai@4",
                "xapi@5",
                "xai@6",
                "claude@10",
                "grok@17",
                "codex@25",
                "opencode@25",
            ],
            reason: "Balance-only providers must not be serialized as used-versus-limit budgets with a false zero limit."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1011,
            anchor: "if provider == .antigravity, let snapshot {",
            expectedProviderIDs: ["antigravity", "codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["antigravity@0", "codex@4"],
            reason: "Antigravity idle families and Codex optional-credit controls filter only their mobile extra windows."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1030,
            anchor: "guard provider == .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex reset-credit inventory maps into its dedicated versioned mobile payload."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1054,
            anchor: "guard provider == .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex credit limits map into their dedicated versioned mobile payload."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1078,
            anchor: "if provider == .amp {",
            expectedProviderIDs: ["alibabatokenplan", "amp", "cursor", "opencode", "qwencloud"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["amp@0", "opencode@7", "alibabatokenplan@14", "qwencloud@23", "cursor@29"],
            reason: "These provider-native window labels preserve the established mobile presentation contract."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1183,
            anchor: "if provider == .cursor, role == .weekly {",
            expectedProviderIDs: ["cursor"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["cursor@0"],
            reason: "Cursor's persisted request layout assigns its weekly window the matching mobile pace role."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1222,
            anchor: "if provider == .abacus {",
            expectedProviderIDs: ["abacus"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["abacus@0"],
            reason: "Abacus session-shaped windows use weekly pace semantics because its reset contract is weekly."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1333,
            anchor: "guard provider == .codex else { return nil }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex workspace context is a dedicated mobile envelope backed by Codex account settings."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1371,
            anchor: "if enabledSet.contains(.codex) {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@7"],
            reason: "Codex multi-account expansion and stale-account purging are isolated to its managed-account cache."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1496,
            anchor: "let codexProviderID = UsageProvider.codex.rawValue",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex reconciliation uses its stable provider ID when expanding managed accounts for mobile sync."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1696,
            anchor: "guard provider == .antigravity, snapshot?.identity == nil else { return false }",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["antigravity@0"],
            reason: "Unowned Antigravity offline cache snapshots must stay Mac-local instead of becoming ambiguous iCloud records."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1943,
            anchor: "guard provider == .xai,",
            expectedProviderIDs: ["xai"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["xai@0"],
            reason: "xAI usage projects provider-native cost history into its mobile cost summary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1968,
            anchor: "sourceRevisions: (snapshot?.updatedAt).map { [\"xai\": $0] })",
            expectedProviderIDs: ["xai"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["xai@0"],
            reason: "xAI's revision key identifies the independent source behind its mobile cost history."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 2006,
            anchor: "case .claude, .vertexai:",
            expectedProviderIDs: [
                "abacus",
                "aiand",
                "aixy",
                "alibaba",
                "alibabatokenplan",
                "amp",
                "antigravity",
                "atlascloud",
                "augment",
                "azureopenai",
                "bedrock",
                "bifrost",
                "chutes",
                "claude",
                "clawrouter",
                "clinepass",
                "codebuff",
                "coderabbit",
                "codex",
                "commandcode",
                "copilot",
                "cursor",
                "deepgram",
                "deepinfra",
                "deepseek",
                "devin",
                "devpass",
                "doubao",
                "elevenlabs",
                "factory",
                "fireworks",
                "gemini",
                "gitkraken",
                "grok",
                "groq",
                "helmcode",
                "huggingface",
                "hyper",
                "ibmbob",
                "jetbrains",
                "kilo",
                "kimi",
                "kiro",
                "langdock",
                "litellm",
                "lithosai",
                "llmman",
                "llmproxy",
                "longcat",
                "manus",
                "mimo",
                "minimax",
                "mistral",
                "moonshot",
                "muse",
                "museai",
                "neuralwatt",
                "notion",
                "nous",
                "ollama",
                "openai",
                "opencode",
                "opencodego",
                "openrouter",
                "perplexity",
                "pi",
                "poe",
                "qoder",
                "qwencloud",
                "raycast",
                "replicate",
                "sakana",
                "stepfun",
                "sub2api",
                "synthetic",
                "t3chat",
                "typesafe",
                "v0",
                "venice",
                "vercel",
                "vertexai",
                "warp",
                "wayfinder",
                "windsurf",
                "workbuddy",
                "xai",
                "xapi",
                "xkiro",
                "zai",
                "zed",
                "zenmux",
                "zoommate",
            ],
            expectedReferenceCount: 92,
            expectedReferenceFingerprint: [
                "claude@0",
                "vertexai@0",
                "codex@2",
                "cursor@4",
                "alibaba@8",
                "antigravity@8",
                "copilot@8",
                "factory@8",
                "gemini@8",
                "opencode@8",
                "opencodego@8",
                "zai@8",
                "amp@9",
                "augment@9",
                "jetbrains@9",
                "kilo@9",
                "kimi@9",
                "kiro@9",
                "minimax@9",
                "ollama@9",
                "synthetic@9",
                "abacus@10",
                "mistral@10",
                "openrouter@10",
                "perplexity@10",
                "warp@10",
                "deepseek@14",
                "doubao@14",
                "manus@14",
                "mimo@14",
                "openai@14",
                "windsurf@14",
                "codebuff@15",
                "commandcode@15",
                "stepfun@15",
                "venice@15",
                "bedrock@19",
                "moonshot@19",
                "v0@19",
                "deepgram@25",
                "elevenlabs@25",
                "grok@25",
                "groq@25",
                "litellm@25",
                "llmproxy@25",
                "alibabatokenplan@30",
                "azureopenai@30",
                "t3chat@30",
                "chutes@34",
                "clawrouter@34",
                "devin@34",
                "poe@34",
                "qoder@34",
                "sakana@34",
                "sub2api@34",
                "wayfinder@34",
                "zed@34",
                "aiand@35",
                "clinepass@35",
                "deepinfra@35",
                "longcat@35",
                "neuralwatt@35",
                "notion@35",
                "qwencloud@35",
                "xai@35",
                "zenmux@35",
                "zoommate@35",
                "coderabbit@36",
                "fireworks@36",
                "gitkraken@36",
                "huggingface@36",
                "hyper@36",
                "ibmbob@36",
                "replicate@36",
                "aixy@37",
                "bifrost@37",
                "devpass@37",
                "helmcode@37",
                "raycast@37",
                "typesafe@37",
                "xkiro@37",
                "atlascloud@38",
                "langdock@38",
                "lithosai@38",
                "llmman@38",
                "muse@38",
                "museai@38",
                "nous@38",
                "pi@38",
                "vercel@38",
                "workbuddy@38",
                "xapi@38",
            ],
            reason: "Cost-estimation badges follow provider-specific model-family knowledge and pricing provenance."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1804,
            anchor: "let resolvedCost = if provider == .codex, let entry {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex mobile daily costs use the local ledger when present, keeping them distinct from dashboard charges."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 1832,
            anchor: "dayEvidence: provider == .codex ? Self.syncDayEvidence(",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex mobile daily points carry account-scoped local-ledger proof for independently verified day coverage."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 2053,
            anchor: "guard provider == .codex else { return [:] }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "OpenAI dashboard service breakdowns belong only to the Codex mobile cost envelope."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1048,
            anchor: "let localized = input.provider == .sub2api",
            expectedProviderIDs: ["claude", "sub2api"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["claude@0", "sub2api@11"],
            reason: "Claude moves reset-credit rows to its dedicated live section; Sub2API localizes detail labels before raw visibility matching."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 1021,
            anchor: "if input.provider == .xai, input.snapshot?.xaiUsage != nil {",
            expectedProviderIDs: ["xai"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["xai@0"],
            reason: "QuotaKit keeps xAI charts while suppressing duplicate generic detail rows when its product-owned balance view is present."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 311,
            anchor: "let codexSources = providers.contains(.codex)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 271,
            anchor: "let providerBaselines = initialProviders.filter { $0 != .codex }.map { provider in",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SpendDashboardController.swift",
            line: 348,
            anchor: "for provider in providers where provider != .codex {",
            expectedProviderIDs: ["codex", "grok", "pi"],
            expectedReferenceCount: 10,
            expectedReferenceFingerprint: [
                "pi@0",
                "pi@1",
                "pi@2",
                "codex@11",
                "grok@14",
                "grok@16",
                "grok@17",
                "grok@21",
                "grok@22",
                "grok@25",
            ],
            reason: "This exact shared construct dispatches a provider-owned capability at the generic integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 284,
            anchor: "self.snapshots[.codex] = snapshot",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@1"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 708,
            anchor: "guard provider == .codex else { return outcome }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 800,
            anchor: "self.providerSpecs[.codex]?.descriptor",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 939,
            anchor: "let originalManualToken = provider == .stepfun ? self.settings.stepfunToken : nil",
            expectedProviderIDs: ["stepfun"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["stepfun@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 983,
            anchor: "guard let self, provider == .stepfun,",
            expectedProviderIDs: ["stepfun"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["stepfun@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1096,
            anchor: "guard let snapshot = self.lastKnownResetSnapshots[.codex],",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1114,
            anchor: "return self.lastKnownResetSnapshots[.codex]",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@7"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1316,
            anchor: "provider == .claude && snapshot?.sourceLabel == \"oauth\" && ClaudeUsageError.isClaudeOAuthUsageRateLimit(error)",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["claude@0", "codex@12"],
            reason: "These adjacent provider-specific helpers preserve Claude OAuth usage and reject mismatched Codex account data."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1463,
            anchor: "guard self.isCurrentProviderRefreshGeneration(.codex, generation: generation) else { return }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 12,
            expectedReferenceFingerprint: [
                "codex@0",
                "codex@3",
                "codex@5",
                "codex@7",
                "codex@8",
                "codex@18",
                "codex@26",
                "codex@32",
                "codex@36",
                "codex@37",
                "codex@38",
                "codex@39",
            ],
            reason: "This Codex publication cluster applies pending weekly-boundary detector corrections around validated account publication while preserving account-scoped warnings, history, refresh guards, and terminal-failure widget invalidation."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1492,
            anchor: "self.invalidateGenericWidgetUsage(for: .codex)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["codex@0", "codex@2", "codex@6", "codex@8", "codex@11"],
            reason: "This Codex failure cluster invalidates widget usage only when a validated account snapshot cannot be retained."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1539,
            anchor: "provider == .deepseek",
            expectedProviderIDs: ["claude", "deepseek"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["deepseek@0", "claude@7"],
            reason: "This QuotaKit publication cluster preserves DeepSeek profiles and Claude account-scoped pace warnings."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1566,
            anchor: "if provider == .deepseek {",
            expectedProviderIDs: ["deepseek"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["deepseek@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1633,
            anchor: "if provider == .deepseek {",
            expectedProviderIDs: ["deepseek"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["deepseek@0", "deepseek@11"],
            reason: "This QuotaKit failure path preserves DeepSeek profile-transition recovery semantics."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 286,
            anchor: "if provider == .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@1"],
            reason: "Codex alone may retain established local-ledger history while publishing newer verified day coverage."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 727,
            anchor: "if provider == .cursor,",
            expectedProviderIDs: ["cursor"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["cursor@0"],
            reason: "Cursor auto credentials may be confirmed during a fetch; unchanged unconfirmed ownership stops retries."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 468,
            anchor: "guard self.tokenSnapshotPublicationForCurrentProviderConfig(for: .codex) == nil else { return }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["codex@0", "codex@1", "codex@7", "codex@15", "codex@16"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 501,
            anchor: "self.providerPublicationRevisionIsCurrent(publicationRevision, for: .codex),",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 11,
            expectedReferenceFingerprint: [
                "codex@0",
                "codex@1",
                "codex@2",
                "codex@3",
                "codex@7",
                "codex@9",
                "codex@10",
                "codex@11",
                "codex@16",
                "codex@25",
                "codex@26",
            ],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 539,
            anchor: "return provider == .codex && self.codexCostCatchUpActivity?.phase == .indexing",
            expectedProviderIDs: ["antigravity", "claude", "codex", "vertexai"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["codex@0", "antigravity@5", "vertexai@10", "claude@11", "codex@13"],
            reason: "History scopes include Antigravity's explicit homes, Vertex's Claude fallback, and Codex ownership."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 619,
            anchor: "guard provider == .cursor else {",
            expectedProviderIDs: ["cursor"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["cursor@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 802,
            anchor: "if provider == .cursor,",
            expectedProviderIDs: ["cursor"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["cursor@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 823,
            anchor: "guard provider == .cursor,",
            expectedProviderIDs: ["cursor"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["cursor@0"],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 845,
            anchor: "case .openai:",
            expectedProviderIDs: ["grok", "mistral", "openai", "opencodego", "openrouter", "xai"],
            expectedReferenceCount: 6,
            expectedReferenceFingerprint: [
                "openai@0",
                "mistral@2",
                "opencodego@4",
                "openrouter@12",
                "xai@14",
                "grok@16",
            ],
            reason: "This exact app-runtime bridge coordinates provider-owned state through the shared controller."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenCost.swift",
            line: 920,
            anchor: "self.tokenFailureGates[.codex]?.reset()",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "claude@1"],
            reason: "This debug cache-clear action preserves its legacy Codex/Claude-only failure-gate reset; " +
                "including Vertex AI's shared transcript scanner would change its error-surfacing behavior."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCLI/CLICostCommand.swift",
            line: 539,
            anchor: "provider == .codex",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact CLI construct preserves the provider-specific command and output contract."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCLI/CLICostCommand.swift",
            line: 643,
            anchor: "let projects = provider == .codex",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact CLI construct preserves the provider-specific command and output contract."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCLI/CLICostCommand.swift",
            line: 247,
            anchor: "if includeBreakdown, provider == .claude {",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "The opt-in breakdown renders Claude's local daily token and model history format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 1028,
            anchor: "if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact cost scanner dispatch selects a provider-owned transcript, cache, or pricing format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 1078,
            anchor: "if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex report breakdowns are projected from its compact persisted ledger rather than a full usage-row reload."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 1124,
            anchor: "if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex breakdown metadata attaches transcript ownership to its native local ledger projection."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 1137,
            anchor: "historyCoverageIsEstablished: provider != .codex",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["codex@0", "claude@7", "codex@7"],
            reason: "Codex history coverage gates native temporal evidence, while Pi usage merges into eligible Claude and Codex reports."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 1306,
            anchor: "options.provider == .codex || options.provider == .claude || options.provider == .antigravity",
            expectedProviderIDs: ["antigravity", "claude", "codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["antigravity@0", "claude@0", "codex@0"],
            reason: "This exact cost scanner dispatch selects a provider-owned transcript, cache, or pricing format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 1380,
            anchor: "guard provider == .codex || provider == .claude || provider == .antigravity else { return nil }",
            expectedProviderIDs: ["antigravity", "claude", "codex"],
            expectedReferenceCount: 5,
            expectedReferenceFingerprint: ["antigravity@0", "claude@0", "codex@0", "antigravity@5", "codex@11"],
            reason: "Unknown-pricing refresh targets use the provider-specific model catalog for Codex, Claude, or Antigravity."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 703,
            anchor: "if provider == .cursor {",
            expectedProviderIDs: ["cursor", "muse"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["muse@0", "cursor@8"],
            reason: "This exact cost scanner dispatch selects a provider-owned transcript, cache, or pricing format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/PiSessionCostScanner.swift",
            line: 355,
            anchor: "guard provider == .codex || provider == .claude || provider == .pi else { return nil }",
            expectedProviderIDs: ["claude", "codex", "pi"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["claude@0", "codex@0", "pi@0"],
            reason: "This exact cost scanner dispatch selects a provider-owned transcript, cache, or pricing format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/PiSessionCostScanner.swift",
            line: 1132,
            anchor: "case .codex:",
            expectedProviderIDs: ["claude", "codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "claude@2"],
            reason: "This exact cost scanner dispatch selects a provider-owned transcript, cache, or pricing format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift",
            line: 605,
            anchor: "let bundled = lookup.pricing.providerID == self.codexModelsDevProviderID ? self.codex[key] : nil",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact cost scanner dispatch selects a provider-owned transcript, cache, or pricing format."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+SpendDashboardPublication.swift",
            line: 85,
            anchor: "guard provider == .codex || isIndependent else { return }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Shared dashboard handles multiple independent token sources."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Providers/Antigravity/AntigravityOfflineStore.swift",
            line: 17,
            anchor: "return home.appendingPathComponent(\".gemini\", isDirectory: true)",
            expectedProviderIDs: ["gemini"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["gemini@0"],
            reason: "CLI home path is a fixed external contract."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe.swift",
            line: 752,
            anchor: "if text.contains(\"claude\") {",
            expectedProviderIDs: ["claude", "gemini", "openai"],
            expectedReferenceCount: 4,
            expectedReferenceFingerprint: ["claude@0", "openai@3", "gemini@6", "gemini@9"],
            reason: "Model family classification via string matching."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/Sync/SyncCoordinator.swift",
            line: 980,
            anchor: ".atlascloud, .vercel, .llmman, .devpass, .raycast, .typesafe, .xkiro, .poe, .sakana, .copilot, .lithosai,",
            expectedProviderIDs: [
                "atlascloud",
                "copilot",
                "devpass",
                "lithosai",
                "llmman",
                "poe",
                "raycast",
                "sakana",
                "typesafe",
                "vercel",
                "xapi",
                "xkiro",
            ],
            expectedReferenceCount: 12,
            expectedReferenceFingerprint: [
                "atlascloud@0",
                "copilot@0",
                "devpass@0",
                "lithosai@0",
                "llmman@0",
                "poe@0",
                "raycast@0",
                "sakana@0",
                "typesafe@0",
                "vercel@0",
                "xkiro@0",
                "xapi@1",
            ],
            reason: "These providers have detail rows without dedicated mobile payloads; preserving those rows includes DevPass and Poe without a rate window, Copilot without a rate window, and LithosAI's prepaid balance details."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Plugins/ProviderPluginCookieBroker.swift",
            line: 599,
            anchor: "let preferredHost = provider == .helmcode && [\"helmcode.com\", \"nan.builders\"].contains(domain)",
            expectedProviderIDs: ["helmcode"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["helmcode@0"],
            reason: "Helmcode's cloud subdomain session cookie must take precedence over the parent-domain cookie."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Plugins/ProviderPluginCookieBroker.swift",
            line: 625,
            anchor: "if provider == .helmcode, [\"helmcode.com\", \"nan.builders\"].contains(domain) {",
            expectedProviderIDs: ["helmcode"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["helmcode@0"],
            reason: "Helmcode authenticates on cloud.helmcode.com or cloud.nan.builders, so cookie import must include that host."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Plugins/ProviderPluginSnapshotMapper.swift",
            line: 52,
            anchor: "if provider == UsageProvider.hyper.instanceID {",
            expectedProviderIDs: ["hyper"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["hyper@0"],
            reason: "Hyper's plugin snapshot alone may carry its provider-native hyperBalance field in addition to shared usage keys."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView+ModelHelpers.swift",
            line: 1071,
            anchor: "let title = if input.provider == .claude, namedWindow.id.hasPrefix(\"claude-weekly-scoped-\") {",
            expectedProviderIDs: ["claude", "doubao"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["claude@0", "doubao@3"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/MenuCardView.swift",
            line: 991,
            anchor: "if input.provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/PredictivePaceWarnings.swift",
            line: 217,
            anchor: "if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/PredictivePaceWarnings.swift",
            line: 270,
            anchor: "for (key, prior) in self.quotaWarningState where key.provider == .claude && key.accountDiscriminator == owner {",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/SettingsStore+Defaults.swift",
            line: 823,
            anchor: "let currentCookieSource = self.providerConfig(for: .codex)?.cookieSource",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["codex@0", "codex@2", "codex@4"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+CodexCostCatchUp.swift",
            line: 195,
            anchor: "includePiSessions: self.shouldIncludePiSessionsInTokenSnapshot(for: .codex),",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+QuotaWarnings.swift",
            line: 221,
            anchor: "guard provider != .claude || transition.window != .session || Self.isSessionWindow(rateWindow) else { return }",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["claude@0", "claude@8", "claude@16"],
            reason: "Claude's weekly OAuth fallback may occupy primary while warning transitions stay session-scoped; account warning keys reconcile through verified Claude ownership."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 1445,
            anchor: "self.widgetUsagePreservationBlockedProviders.insert(.claude)",
            expectedProviderIDs: ["claude", "grok"],
            expectedReferenceCount: 14,
            expectedReferenceFingerprint: [
                "claude@0", "claude@1", "claude@2", "claude@3", "claude@4", "claude@5", "claude@8",
                "claude@9", "claude@10", "claude@11", "claude@12", "claude@14", "claude@18", "grok@30",
            ],
            reason: "Claude credential swaps clear credential-derived usage and widget state while retaining account-scoped warning history."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 1600,
            anchor: "provider == .claude &&",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["claude@0", "claude@9"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+SpendDashboardCodexCostCatchUp.swift",
            line: 516,
            anchor: "self.settings.providerConfigRevision(for: .codex) == context.providerConfigRevision",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["codex@0", "codex@3", "codex@4"],
            reason: "The spend catch-up configuration guard rechecks Codex configuration and enablement before continuing the shared scan."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+SpendDashboardTokenCost.swift",
            line: 49,
            anchor: "if provider == .cursor, self.settings.cursorCookieSource == .off { return false }",
            expectedProviderIDs: ["cursor"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["cursor@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+SpendDashboardTokenCost.swift",
            line: 219,
            anchor: "if provider == .cursor,",
            expectedProviderIDs: ["cursor"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["cursor@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+TokenAccounts.swift",
            line: 1414,
            anchor: "guard self.isCurrentProviderRefreshGeneration(.codex, generation: generation) else { return }",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@6"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 478,
            anchor: "let swapOwnsClaude = provider == .claude && self.settings.claudeSwapEnabled &&",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 656,
            anchor: "guard let entry, entry.provider == .claude else { return nil }",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCLI/CLICostCommand.swift",
            line: 946,
            anchor: "guard provider == .cursor, settings?.cookieSource == .manual else { return nil }",
            expectedProviderIDs: ["cursor"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["cursor@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CodexHomeScope.swift",
            line: 15,
            anchor: "return URL(fileURLWithPath: executable).lastPathComponent == \"codex\" &&",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Config/CodexBarConfigStore.swift",
            line: 85,
            anchor: "var codex = denied.providerConfig(for: .codex) ?? ProviderConfig(id: .codex)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 680,
            anchor: "if provider != .cursor, provider != .antigravity {",
            expectedProviderIDs: ["antigravity", "cursor"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["antigravity@0", "cursor@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 1160,
            anchor: "if provider == .codex {",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@10"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 1789,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This branch merges eligible Pi session history into the Codex cost snapshot, so the shared loader receives Codex as the destination provider."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/CostUsageFetcher.swift",
            line: 2544,
            anchor: "if provider == .vertexai {",
            expectedProviderIDs: ["claude", "vertexai"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["vertexai@0", "claude@2"],
            reason: "Vertex AI may scan Claude-format logs while Claude excludes Vertex transcripts, so the scanner preserves provider-specific transcript selection."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/UsageFetcher.swift",
            line: 1908,
            anchor: "providerID: .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift",
            line: 903,
            anchor: "? self.codex[self.normalizeCodexModel(pricing.modelID)]?.thresholdTokens",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner+Claude.swift",
            line: 20,
            anchor: "guard let reportContext, provider == .claude || provider == .vertexai else {",
            expectedProviderIDs: ["claude", "vertexai"],
            expectedReferenceCount: 3,
            expectedReferenceFingerprint: ["claude@0", "vertexai@0", "vertexai@11"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarWidget/BurnDownWidgetProvider.swift",
            line: 187,
            anchor: "// Provider-specific by design: AppIntents requires literal catalog titles; snapshot data gates eligibility.",
            expectedProviderIDs: [
                "atlascloud",
                "devpass",
                "gitkraken",
                "hyper",
                "langdock",
                "lithosai",
                "llmman",
                "museai",
                "typesafe",
                "vercel",
                "workbuddy",
                "xkiro",
            ],
            expectedReferenceCount: 13,
            expectedReferenceFingerprint: [
                "typesafe@0",
                "hyper@2",
                "gitkraken@3",
                "devpass@4",
                "atlascloud@5",
                "vercel@6",
                "llmman@7",
                "llmman@7",
                "xkiro@8",
                "museai@9",
                "lithosai@10",
                "workbuddy@11",
                "langdock@12",
            ],
            reason: "AppIntents needs literal per-provider titles for this widget selector; snapshot data separately decides provider eligibility."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarWidget/BurnDownWidgetProvider.swift",
            line: 472,
            anchor: "provider: configuration.provider.provider ?? .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@11"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarWidget/BurnDownWidgetProvider.swift",
            line: 505,
            anchor: "provider: configuration.provider.provider ?? .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@10"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarWidget/CodexBarWidgetProvider.swift",
            line: 84,
            anchor: "@Parameter(title: \"Provider\", default: .codex)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@4"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarWidget/CodexBarWidgetProvider.swift",
            line: 116,
            anchor: "@Parameter(title: \"Provider\", default: .codex)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@7"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarWidget/CodexBarWidgetProvider.swift",
            line: 152,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarWidget/CodexBarWidgetProvider.swift",
            line: 183,
            anchor: "provider: providers.first ?? .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarWidget/CodexBarWidgetProvider.swift",
            line: 205,
            anchor: "let selected = providers.first { $0.instanceID == stored } ?? providers.first ?? .codex",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarWidget/CodexBarWidgetProvider.swift",
            line: 229,
            anchor: "return supported.isEmpty ? [.codex] : supported",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["codex@0", "codex@8"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarWidget/CodexBarWidgetProvider.swift",
            line: 287,
            anchor: "provider: .codex,",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "This exact shared construct handles provider-owned behavior at the integration boundary."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/PreferencesProviderDetailView.swift",
            line: 374,
            anchor: "if self.provider != .antigravity {",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["antigravity@0"],
            reason: "Antigravity's CLI descriptor has no version detector, so this detail pane omits the unavailable Version row."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/StatusItemController+MenuBarLayout.swift",
            line: 257,
            anchor: "codexCredits: provider == .codex ? self.store.codexConsumerProjection(",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "Codex's consumer credit snapshot is passed separately because its menu-bar balance is not a generic provider quota."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+QuotaWarnings.swift",
            line: 262,
            anchor: "} else if provider == .claude,",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 2,
            expectedReferenceFingerprint: ["claude@0", "claude@6"],
            reason: "Claude warning history migrates between unresolved and verified account keys only when reset and remaining values prove the same quota episode."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+Refresh.swift",
            line: 1084,
            anchor: "let identity = usage.identity(for: .codex)",
            expectedProviderIDs: ["codex"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["codex@0"],
            reason: "When account-scoped Codex usage lacks an email, this helper restores it from the validated refresh owner."),
        AllowedProviderConstruct(
            path: "Sources/CodexBar/UsageStore+WidgetSnapshot.swift",
            line: 445,
            anchor: "guard provider != .claude,",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "Claude queued usage is preserved only through its owner-aware path; this branch excludes it from the generic process queue."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCLI/CLIHelpers.swift",
            line: 132,
            anchor: "guard provider == .antigravity, sourceMode == .auto, !attempts.isEmpty else { return nil }",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["antigravity@0"],
            reason: "Antigravity Auto mode reports per-strategy outcomes so its multi-source fallback path is visible in CLI errors."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCLI/CLIRenderer.swift",
            line: 519,
            anchor: "if provider == .antigravity {",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["antigravity@0"],
            reason: "Antigravity quota-summary lanes with unknown usage render an explicit Unavailable line in CLI detail output."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCLI/CLIRenderer.swift",
            line: 792,
            anchor: "if provider == .antigravity,",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["antigravity@0"],
            reason: "Antigravity quota-summary lanes with unknown usage render as Unavailable instead of through the generic rate-window path."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCLI/CLIRenderer.swift",
            line: 813,
            anchor: "guard provider == .antigravity, let windows = snapshot.extraRateWindows else { return nil }",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["antigravity@0"],
            reason: "This helper selects Antigravity quota-summary windows so the CLI can render its model-family lanes correctly."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Providers/ProviderFetchPlan.swift",
            line: 399,
            anchor: "private static let log = CodexBarLog.logger(LogCategories.provider(.antigravity))",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["antigravity@0"],
            reason: "The shared strategy pipeline uses the Antigravity log category for its provider-specific Auto-source outcome diagnostic."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/Providers/ProviderFetchPlan.swift",
            line: 502,
            anchor: "guard provider == .antigravity, context.sourceMode == .auto, !attempts.isEmpty else { return }",
            expectedProviderIDs: ["antigravity"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["antigravity@0"],
            reason: "Only Antigravity Auto mode emits this pipeline's source-by-source fallback outcome diagnostic."),
        AllowedProviderConstruct(
            path: "Sources/CodexBarCore/UsageFetcher.swift",
            line: 543,
            anchor: "if resolvedIdentity?.providerID == .claude {",
            expectedProviderIDs: ["claude"],
            expectedReferenceCount: 1,
            expectedReferenceFingerprint: ["claude@0"],
            reason: "Claude reset-credit rows are removed from generic details because they render in the dedicated live reset-credit section."),
    ]
    // swiftlint:enable line_length

    private static func shippedSwiftSources(root: URL) throws -> [SourceFile] {
        var files: [SourceFile] = []
        for directoryName in ["Sources", "WidgetExtension"] {
            let directory = root.appending(path: directoryName, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { continue }
            let enumerator = try #require(FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
                try files.append(SourceFile(path: path, source: String(contentsOf: url, encoding: .utf8)))
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func providerImplementationID(
        _ path: String,
        providerIDsByFolderName: [String: String]) -> String?
    {
        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 5,
              components[0] == "Sources",
              components[2] == "Providers"
        else { return nil }
        return providerIDsByFolderName[components[3].lowercased()]
    }

    private static func analyze(
        file: SourceFile,
        providerIDs: Set<String>,
        allowedConstructs: [AllowedProviderConstruct],
        suppressedReferences: [SuppressedProviderReference] = []) -> [String]
    {
        let lines = file.source.components(separatedBy: .newlines)
        var references = self.providerReferences(in: file.source, providerIDs: providerIDs)
        var failures: [String] = []
        var usedSuppressions: Set<String> = []
        for suppression in suppressedReferences {
            guard suppression.path == file.path else {
                failures.append("\(suppression.path): suppressed reference was assigned to the wrong file")
                continue
            }
            guard !suppression.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                failures.append("\(file.path): suppressed reference '\(suppression.anchor)' has no written reason")
                continue
            }
            let line = suppression.line - 1
            guard lines.indices.contains(line),
                  lines[line].trimmingCharacters(in: .whitespaces) == suppression.anchor
            else {
                failures.append(
                    "\(file.path):\(suppression.line) suppressed reference anchor no longer matches " +
                        "'\(suppression.anchor)'")
                continue
            }
            let key = "\(line):\(suppression.expectedProviderIDs.sorted())"
            guard usedSuppressions.insert(key).inserted else {
                failures.append("\(file.path):\(suppression.line) duplicate suppressed provider reference")
                continue
            }
            guard let referenceIndex = references.firstIndex(where: {
                $0.line == line && $0.providerIDs.isSuperset(of: suppression.expectedProviderIDs)
            }) else {
                failures.append(
                    "\(file.path):\(suppression.line) suppressed provider reference no longer matches " +
                        "\(suppression.expectedProviderIDs.sorted())")
                continue
            }
            for providerID in suppression.expectedProviderIDs.sorted() {
                guard references[referenceIndex].suppressOneOccurrence(of: providerID) else {
                    failures.append(
                        "\(file.path):\(suppression.line) suppressed provider token no longer matches \(providerID)")
                    break
                }
            }
        }
        references.removeAll { $0.providerOccurrences.isEmpty }
        let clusters = self.providerReferenceClusters(references)
        let markerLines = lines.indices.filter { self.providerMarkerReason(in: lines[$0]) != nil }
        var allowedClusterIndices: Set<Int> = []

        for construct in allowedConstructs {
            guard construct.path == file.path else {
                failures.append("\(construct.path): allowlisted construct was assigned to the wrong file")
                continue
            }
            guard !construct.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                failures.append("\(file.path): allowlisted construct '\(construct.anchor)' has no written reason")
                continue
            }
            let anchorLine = construct.line - 1
            guard lines.indices.contains(anchorLine),
                  lines[anchorLine].trimmingCharacters(in: .whitespaces) == construct.anchor
            else {
                failures.append(
                    "\(file.path):\(construct.line) allowlisted construct anchor no longer matches " +
                        "'\(construct.anchor)'")
                continue
            }
            let candidateIndices = clusters.indices.filter { index in
                let range = clusters[index].lineRange
                return range
                    .contains(anchorLine) ||
                    (anchorLine < range.lowerBound && range.lowerBound - anchorLine <= self.allowlistAnchorTolerance)
            }
            guard candidateIndices.count == 1, let clusterIndex = candidateIndices.first else {
                failures.append(
                    "\(file.path):\(anchorLine + 1) allowlisted construct anchor did not identify exactly one cluster")
                continue
            }
            let cluster = clusters[clusterIndex]
            guard let expectedReferenceFingerprint = construct.expectedReferenceFingerprint else {
                failures.append(
                    "\(file.path):\(construct.line) allowlisted construct has no occurrence fingerprint; " +
                        "expectedReferenceFingerprint: \(cluster.referenceFingerprint)")
                continue
            }
            guard cluster.providerIDs == construct.expectedProviderIDs,
                  cluster.referenceCount == construct.expectedReferenceCount,
                  cluster.referenceFingerprint == expectedReferenceFingerprint
            else {
                failures.append(
                    "\(file.path):\(cluster.lineRange.lowerBound + 1) allowlisted construct fingerprint changed; " +
                        "expected \(construct.expectedProviderIDs.sorted())/\(construct.expectedReferenceCount)/" +
                        "\(expectedReferenceFingerprint), found \(cluster.providerIDs.sorted())/" +
                        "\(cluster.referenceCount)/\(cluster.referenceFingerprint)")
                continue
            }
            guard allowedClusterIndices.insert(clusterIndex).inserted else {
                failures.append("\(file.path):\(anchorLine + 1) multiple allowlist entries target the same construct")
                continue
            }
        }

        var usedMarkers: Set<Int> = []
        var previousClusterEnd = -1
        for (index, cluster) in clusters.enumerated() where !allowedClusterIndices.contains(index) {
            let lowerBound = max(previousClusterEnd + 1, cluster.lineRange.lowerBound - self.providerCaseMarkerWindow)
            let marker = markerLines.last { line in
                lowerBound...cluster.lineRange.lowerBound ~= line && !usedMarkers.contains(line)
            }
            if let marker {
                usedMarkers.insert(marker)
            } else {
                failures.append(
                    "\(file.path):\(cluster.lineRange.lowerBound + 1) has an unjustified provider-specific " +
                        "construct (\(cluster.providerIDs.sorted().joined(separator: ", ")); " +
                        "references: \(cluster.referenceCount); fingerprint: \(cluster.referenceFingerprint)); " +
                        "newly recognized: \(cluster.newlyRecognizedFingerprint); derive it or add " +
                        "'// Provider-specific by design: <specific reason>' immediately before this cluster.")
            }
            previousClusterEnd = cluster.lineRange.upperBound
        }

        return failures
    }

    private static func providerReferenceClusters(
        _ references: [ProviderReference]) -> [ProviderReferenceCluster]
    {
        self.unfilteredProviderReferenceClusters(references)
    }

    private static func unfilteredProviderReferenceClusters(
        _ references: [ProviderReference]) -> [ProviderReferenceCluster]
    {
        guard let first = references.first else { return [] }
        var clusters: [ProviderReferenceCluster] = []
        var current = [first]
        var clusterStart = first.line
        var previous = first.line

        for reference in references.dropFirst() {
            if reference.line - previous > self.providerCaseClusterGap ||
                reference.line - clusterStart >= self.providerCaseClusterWindow
            {
                clusters.append(ProviderReferenceCluster(references: current))
                current = [reference]
                clusterStart = reference.line
            } else {
                current.append(reference)
            }
            previous = reference.line
        }
        clusters.append(ProviderReferenceCluster(references: current))
        return clusters
    }

    private static func providerReferences(in source: String, providerIDs: Set<String>) -> [ProviderReference] {
        let lines = source.components(separatedBy: .newlines)
        let statementContexts = self.statementContexts(for: lines)
        return lines.enumerated().flatMap { index, line -> [ProviderReference] in
            let code = self.codeBeforeLineComment(line)
            guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
            guard code.contains(".") || code.contains("\"") else { return [] }
            let literals = self.quotedStringLiterals(in: code)
            let plainStringRanges = literals.compactMap { literal -> Range<String.Index>? in
                code[literal.range].contains("\\(") ? nil : literal.range
            }
            var matches: [String] = []
            var newlyRecognizedMatches: [String] = []
            for providerID in providerIDs where code.contains(".\(providerID)") {
                for strength in self.dottedProviderReferenceStrengths(
                    providerID,
                    in: code,
                    statement: statementContexts[index],
                    plainStringRanges: plainStringRanges)
                {
                    matches.append(providerID)
                    if strength != .strong {
                        newlyRecognizedMatches.append(providerID)
                    }
                }
            }
            for literal in literals {
                let providerID = literal.value.lowercased()
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if providerIDs.contains(providerID), self.isProviderIDLiteral(
                    providerID,
                    literal: literal.value,
                    range: literal.range,
                    line: code,
                    statement: statementContexts[index])
                {
                    matches.append(providerID)
                }
            }
            guard !matches.isEmpty else { return [] }
            return [ProviderReference(
                line: index,
                providerOccurrences: matches,
                newlyRecognizedProviderOccurrences: newlyRecognizedMatches)]
        }
    }

    private enum ProviderReferenceStrength: Equatable {
        case strong
        case weakArgument
        case fullyQualified
    }

    private static func dottedProviderReferenceStrengths(
        _ rawValue: String,
        in line: String,
        statement: StatementContext,
        plainStringRanges: [Range<String.Index>]) -> [ProviderReferenceStrength]
    {
        let needle = ".\(rawValue)"
        var searchStart = line.startIndex
        var found: [ProviderReferenceStrength] = []
        while let range = line.range(of: needle, range: searchStart..<line.endIndex) {
            if plainStringRanges.contains(where: { $0.contains(range.lowerBound) }) {
                searchStart = range.upperBound
                continue
            }
            if range.upperBound == line.endIndex || !Self.isIdentifierCharacter(line[range.upperBound]),
               let strength = self.providerPolicyPosition(
                   rawValue,
                   range: range,
                   line: line,
                   statement: statement)
            {
                found.append(strength)
            }
            searchStart = range.upperBound
        }
        return found
    }

    private static func providerPolicyPosition(
        _ rawValue: String,
        range: Range<String.Index>,
        line: String,
        statement: StatementContext) -> ProviderReferenceStrength?
    {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefix = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let suffix = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("case ") || trimmed.hasPrefix("switch ") ||
            trimmed.hasPrefix("if ") || trimmed.hasPrefix("guard ") ||
            trimmed.hasPrefix("else if ") || trimmed.hasPrefix("return .\(rawValue)")
        {
            return .strong
        }
        if ["==", "!=", "??", " ? ", ".contains(", ".filter", "rawValue"]
            .contains(where: line.contains)
        {
            return .strong
        }
        if prefix.isEmpty, suffix.hasPrefix(":") || suffix.hasPrefix(",") || suffix.isEmpty {
            return .strong
        }
        if prefix.hasSuffix("=") || prefix.hasSuffix("[") || prefix.hasSuffix(",") {
            return .strong
        }
        let qualifier = prefix.split(whereSeparator: { !Self.isIdentifierCharacter($0) }).last.map(String.init)
        if qualifier == "UsageProvider" {
            let derivedInstanceAlias = "public static let \(rawValue) = UsageProvider.\(rawValue).instanceID"
            if trimmed == derivedInstanceAlias {
                return nil
            }
            return .fullyQualified
        }
        if prefix.hasSuffix(":") || prefix.hasSuffix("(") {
            return .weakArgument
        }
        if prefix.isEmpty {
            let statementPrefix = statement.prefixBeforeLine
            if self.unmatchedOpeningParentheses(in: statementPrefix).reversed().contains(where: {
                self.currentArgumentLabel(openingParenthesis: $0, in: statementPrefix) != nil
            }) {
                return .weakArgument
            }
        }
        return suffix.hasPrefix(":") ? .strong : nil
    }

    private struct StatementContext {
        let prefixBeforeLine: String
    }

    private static func isProviderIDLiteral(
        _ providerID: String,
        literal: String,
        range: Range<String.Index>,
        line: String,
        statement: StatementContext) -> Bool
    {
        let lowercasedLiteral = literal.lowercased()
        guard self.containsWord(providerID, in: lowercasedLiteral) else { return false }
        if self.containsSuppressionToken("http://", in: lowercasedLiteral) ||
            self.containsSuppressionToken("https://", in: lowercasedLiteral)
        {
            return false
        }
        if self.isLogLiteral(range: range, in: line, statement: statement) {
            return false
        }
        if literal != lowercasedLiteral {
            return false
        }
        let normalizedLiteral = lowercasedLiteral.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard normalizedLiteral == providerID else { return false }
        return true
    }

    private static func isLogLiteral(
        range: Range<String.Index>,
        in line: String,
        statement: StatementContext) -> Bool
    {
        let prefix = statement.prefixBeforeLine + line[..<range.lowerBound]
        let activePrefix = prefix.split(separator: ";", omittingEmptySubsequences: false).last
            .map(String.init) ?? prefix
        let openingParentheses = self.unmatchedOpeningParentheses(in: activePrefix)
        if openingParentheses.reversed().contains(where: {
            self.isLoggingCall(openingParenthesis: $0, in: activePrefix)
        }) {
            return true
        }
        guard let openingParenthesis = openingParentheses.last,
              self.currentArgumentLabel(openingParenthesis: openingParenthesis, in: activePrefix) == "category"
        else {
            return false
        }
        return self.isLogCategoryConstructor(openingParenthesis: openingParenthesis, in: activePrefix)
    }

    private static func unmatchedOpeningParentheses(in text: String) -> [String.Index] {
        var openingParentheses: [String.Index] = []
        var previous: Character?
        var isInsideString = false
        for index in text.indices {
            let character = text[index]
            if character == "\"", previous != "\\" {
                isInsideString.toggle()
            } else if !isInsideString {
                if character == "(" {
                    openingParentheses.append(index)
                } else if character == ")" {
                    _ = openingParentheses.popLast()
                }
            }
            previous = character
        }
        return openingParentheses
    }

    private static func isLoggingCall(openingParenthesis: String.Index, in text: String) -> Bool {
        let identifiers = self.callIdentifiers(openingParenthesis: openingParenthesis, in: text)
        guard let callName = identifiers.last else { return false }
        if callName == "log" || callName == "logger" || callName.hasSuffix("Logger") {
            return true
        }
        let loggingMethods: Set = ["debug", "error", "fault", "info", "log", "notice", "trace", "verbose", "warning"]
        guard loggingMethods.contains(callName.lowercased()) else { return false }
        return identifiers.dropLast().contains { identifier in
            identifier == "log" || identifier == "logger" || identifier == "CodexBarLog" ||
                identifier.hasSuffix("Logger")
        }
    }

    private static func isLogCategoryConstructor(openingParenthesis: String.Index, in text: String) -> Bool {
        let identifiers = self.callIdentifiers(openingParenthesis: openingParenthesis, in: text)
        guard let callName = identifiers.last else { return false }
        return callName == "OSLog" || callName == "Logger" || callName == "logger" ||
            callName.hasSuffix("LogCategory") || callName.hasSuffix("LogCategories")
    }

    private static func callIdentifiers(openingParenthesis: String.Index, in text: String) -> [String] {
        let expression = self.callExpression(openingParenthesis: openingParenthesis, in: text)
        var identifiers: [String] = []
        var identifier = ""
        var depth = 0
        for character in expression {
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(0, depth - 1)
            } else if depth == 0, self.isIdentifierCharacter(character) {
                identifier.append(character)
            } else if depth == 0, !identifier.isEmpty {
                identifiers.append(identifier)
                identifier = ""
            }
        }
        if !identifier.isEmpty {
            identifiers.append(identifier)
        }
        return identifiers
    }

    private static func callExpression(openingParenthesis: String.Index, in text: String) -> Substring {
        var start = openingParenthesis
        while start > text.startIndex {
            let previous = text.index(before: start)
            let character = text[previous]
            if character.isWhitespace || self.isIdentifierCharacter(character) || character == "." {
                start = previous
            } else if character == ")", let matchingOpening = self.matchingOpeningParenthesis(
                for: previous,
                in: text)
            {
                start = matchingOpening
            } else {
                break
            }
        }
        return text[start..<openingParenthesis]
    }

    private static func matchingOpeningParenthesis(
        for closingParenthesis: String.Index,
        in text: String) -> String.Index?
    {
        var openingParentheses: [String.Index] = []
        var previous: Character?
        var isInsideString = false
        for index in text.indices where index <= closingParenthesis {
            let character = text[index]
            if character == "\"", previous != "\\" {
                isInsideString.toggle()
            } else if !isInsideString {
                if character == "(" {
                    openingParentheses.append(index)
                } else if character == ")" {
                    guard let opening = openingParentheses.popLast() else { return nil }
                    if index == closingParenthesis {
                        return opening
                    }
                }
            }
            previous = character
        }
        return nil
    }

    private static func currentArgumentLabel(openingParenthesis: String.Index, in text: String) -> String? {
        let argumentStart = text.index(after: openingParenthesis)
        var currentStart = argumentStart
        var delimiterDepth = 0
        var previous: Character?
        var isInsideString = false
        var index = argumentStart
        while index < text.endIndex {
            let character = text[index]
            if character == "\"", previous != "\\" {
                isInsideString.toggle()
            } else if !isInsideString {
                if character == "(" || character == "[" || character == "{" {
                    delimiterDepth += 1
                } else if character == ")" || character == "]" || character == "}" {
                    delimiterDepth -= 1
                } else if character == ",", delimiterDepth == 0 {
                    currentStart = text.index(after: index)
                }
            }
            previous = character
            index = text.index(after: index)
        }
        let argumentPrefix = text[currentStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard argumentPrefix.hasSuffix(":") else { return nil }
        let label = argumentPrefix.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        return label.allSatisfy(self.isIdentifierCharacter) ? label : nil
    }

    private static func statementContexts(for lines: [String]) -> [StatementContext] {
        var contexts = Array(
            repeating: StatementContext(prefixBeforeLine: ""),
            count: lines.count)
        var statementLines: [Int] = []
        var fragments: [String] = []
        var delimiterDepth = 0

        func finishStatement() {
            guard !fragments.isEmpty else { return }
            var prefix = ""
            for (offset, line) in statementLines.enumerated() {
                contexts[line] = StatementContext(prefixBeforeLine: prefix)
                prefix += fragments[offset] + "\n"
            }
            statementLines.removeAll(keepingCapacity: true)
            fragments.removeAll(keepingCapacity: true)
        }

        for (index, line) in lines.enumerated() {
            let code = self.codeBeforeLineComment(line)
            statementLines.append(index)
            fragments.append(code)
            delimiterDepth += self.statementDelimiterDelta(in: code)
            let trimmed = code.trimmingCharacters(in: .whitespaces)
            let explicitlyContinued = trimmed.hasSuffix("=") || trimmed.hasSuffix("->")
            if delimiterDepth <= 0, !explicitlyContinued {
                finishStatement()
                delimiterDepth = 0
            }
        }
        if !statementLines.isEmpty {
            finishStatement()
        }
        return contexts
    }

    private static func statementDelimiterDelta(in line: String) -> Int {
        var delta = 0
        var previous: Character?
        var isInsideString = false
        for character in line {
            if character == "\"", previous != "\\" {
                isInsideString.toggle()
            } else if !isInsideString {
                if character == "(" || character == "[" {
                    delta += 1
                } else if character == ")" || character == "]" {
                    delta -= 1
                }
            }
            previous = character
        }
        return delta
    }

    private static func providerMarkerReason(in line: String) -> String? {
        guard let comment = self.lineComment(in: line) else { return nil }
        let trimmed = comment.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard trimmed.hasPrefix(self.providerCaseMarker) else { return nil }
        let reason = trimmed.dropFirst(self.providerCaseMarker.count)
            .trimmingCharacters(in: .whitespaces)
        return reason.isEmpty ? nil : reason
    }

    private static func lineComment(in line: String) -> String? {
        var previous: Character?
        var isInsideString = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"", previous != "\\" {
                isInsideString.toggle()
            } else if character == "/", !isInsideString {
                let next = line.index(after: index)
                if next < line.endIndex, line[next] == "/" {
                    return String(line[line.index(after: next)...])
                }
            }
            previous = character
            index = line.index(after: index)
        }
        return nil
    }

    private static func containsWord(_ word: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: word, range: searchStart..<text.endIndex) {
            let hasLeftBoundary = range.lowerBound == text.startIndex ||
                !self.isIdentifierCharacter(text[text.index(before: range.lowerBound)])
            let hasRightBoundary = range.upperBound == text.endIndex ||
                !self.isIdentifierCharacter(text[range.upperBound])
            if hasLeftBoundary, hasRightBoundary {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func containsSuppressionToken(_ token: String, in text: some StringProtocol) -> Bool {
        guard let first = token.first, let last = token.last else { return false }
        var searchStart = text.startIndex
        while let range = text.range(of: token, range: searchStart..<text.endIndex) {
            let hasLeftBoundary = !self.isIdentifierCharacter(first) || range.lowerBound == text.startIndex ||
                !self.isIdentifierCharacter(text[text.index(before: range.lowerBound)])
            let hasRightBoundary = !self.isIdentifierCharacter(last) || range.upperBound == text.endIndex ||
                !self.isIdentifierCharacter(text[range.upperBound])
            if hasLeftBoundary, hasRightBoundary {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private struct QuotedStringLiteral {
        let value: String
        let range: Range<String.Index>
    }

    private static func quotedStringLiterals(in line: String) -> [QuotedStringLiteral] {
        var literals: [QuotedStringLiteral] = []
        var current = ""
        var literalStart: String.Index?
        var isInsideString = false
        var isEscaped = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if isInsideString {
                if isEscaped {
                    current.append(character)
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    let end = line.index(after: index)
                    if let literalStart {
                        literals.append(QuotedStringLiteral(value: current, range: literalStart..<end))
                    }
                    current = ""
                    literalStart = nil
                    isInsideString = false
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                literalStart = index
                isInsideString = true
            }
            index = line.index(after: index)
        }
        return literals
    }

    private static func codeBeforeLineComment(_ line: String) -> String {
        var previous: Character?
        var isInsideString = false
        var characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"", previous != "\\" {
                isInsideString.toggle()
            } else if character == "/", !isInsideString, index + 1 < characters.count {
                if characters[index + 1] == "/" {
                    return String(characters[..<index])
                }
                if characters[index + 1] == "*" {
                    // Blank single-line block comments with spaces so punctuation adjacency stays
                    // visible to position heuristics while every character index is preserved.
                    var end = index + 2
                    while end + 1 < characters.count, !(characters[end] == "*" && characters[end + 1] == "/") {
                        end += 1
                    }
                    guard end + 1 < characters.count else {
                        return String(characters[..<index])
                    }
                    for blank in index...(end + 1) {
                        characters[blank] = " "
                    }
                    previous = " "
                    index = end + 2
                    continue
                }
            }
            previous = character
            index += 1
        }
        return String(characters)
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    private static func repoRoot() throws -> URL {
        var directory = URL(filePath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: directory.appending(path: "Package.swift").path(percentEncoded: false))
            {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private static func hash(_ color: ProviderColor, into fingerprint: inout UInt64) {
        for component in [color.red, color.green, color.blue] {
            var bits = component.bitPattern
            for _ in 0..<MemoryLayout<UInt64>.size {
                fingerprint = (fingerprint ^ UInt64(UInt8(truncatingIfNeeded: bits))) &* 1_099_511_628_211
                bits >>= 8
            }
        }
    }

    private static func hash(_ bytes: String.UTF8View, into fingerprint: inout UInt64) {
        for byte in bytes {
            fingerprint = (fingerprint ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
