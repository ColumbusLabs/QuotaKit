import Foundation

public struct HyperProviderSettings: ProviderCookieSettings {
    public let cookieSource: ProviderCookieSource
    public let manualCookieHeader: String?

    public init(cookieSource: ProviderCookieSource, manualCookieHeader: String?) {
        self.cookieSource = cookieSource
        self.manualCookieHeader = manualCookieHeader
    }
}

public enum HyperProviderSettingsKey: ProviderSettingsSectionKey {
    public static let providerID = ProviderInstanceID.hyper
    public typealias Section = HyperProviderSettings
}

extension ProviderSettingsSnapshot {
    public typealias HyperProviderSettings = CodexBarCore.HyperProviderSettings

    public var hyper: HyperProviderSettings? {
        self[HyperProviderSettingsKey.self]
    }
}

extension ProviderSettingsSnapshotContribution {
    public static func hyper(_ section: HyperProviderSettings) -> Self {
        Self(section, for: HyperProviderSettingsKey.self)
    }
}
