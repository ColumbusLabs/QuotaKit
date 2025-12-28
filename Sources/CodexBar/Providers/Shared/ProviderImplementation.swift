import CodexBarCore
import Foundation

/// App-side provider implementation.
///
/// Rules:
/// - Provider implementations return *data/behavior descriptors*; the app owns UI.
/// - Do not mix identity fields across providers (email/org/plan/loginMethod stays siloed).
protocol ProviderImplementation: Sendable {
    var id: UsageProvider { get }
    var supportsLoginFlow: Bool { get }

    /// Optional provider-specific settings toggles to render in the Providers pane.
    ///
    /// Important: Providers must not return custom SwiftUI views here. Only shared toggle/action descriptors.
    @MainActor
    func settingsToggles(context: ProviderSettingsContext) -> [ProviderSettingsToggleDescriptor]

    /// Optional provider-specific settings fields to render in the Providers pane.
    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor]

    /// Optional provider-specific login flow. Returns whether to refresh after completion.
    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool

    /// Optional override for source label in Providers settings.
    @MainActor
    func sourceLabel(context: ProviderSourceLabelContext) -> String?
}

extension ProviderImplementation {
    var supportsLoginFlow: Bool { false }
    @MainActor
    func settingsToggles(context _: ProviderSettingsContext) -> [ProviderSettingsToggleDescriptor] {
        []
    }

    @MainActor
    func settingsFields(context _: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        []
    }

    @MainActor
    func runLoginFlow(context _: ProviderLoginContext) async -> Bool {
        false
    }

    @MainActor
    func sourceLabel(context _: ProviderSourceLabelContext) -> String? {
        nil
    }
}

struct ProviderLoginContext {
    unowned let controller: StatusItemController
}

struct ProviderSourceLabelContext {
    let settings: SettingsStore
    let descriptor: ProviderDescriptor
}
