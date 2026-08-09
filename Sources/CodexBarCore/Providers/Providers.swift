import Foundation
import SweetCookieKit

public struct ProviderDebugPaneCapabilities: Sendable {
    public let probeLogOrder: Int?
    public let notificationSimulationOrder: Int?
    public let errorSimulationOrder: Int?

    public init(
        probeLogOrder: Int? = nil,
        notificationSimulationOrder: Int? = nil,
        errorSimulationOrder: Int? = nil)
    {
        self.probeLogOrder = probeLogOrder
        self.notificationSimulationOrder = notificationSimulationOrder
        self.errorSimulationOrder = errorSimulationOrder
    }
}

// swiftformat:disable sortDeclarations
public enum UsageProvider: String, CaseIterable, Sendable, Codable {
    case codex
    case claude
    case cursor
    case grok
}

// swiftformat:enable sortDeclarations

public struct IconStyle: RawRepresentable, Hashable, Sendable, CaseIterable, CustomStringConvertible {
    public let rawValue: String

    public var description: String {
        self.rawValue
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(provider: UsageProvider) {
        self.init(rawValue: provider.rawValue)
    }

    public static var allCases: [IconStyle] {
        UsageProvider.allCases.map(Self.init(provider:)) + [.combined]
    }

    // Provider-specific by design: named styles preserve source-compatible renderer entry points.
    public static let codex = Self(provider: .codex)
    public static let claude = Self(provider: .claude)
    public static let cursor = Self(provider: .cursor)
    public static let grok = Self(provider: .grok)
    public static let combined = Self(rawValue: "combined")
}

public struct ProviderMetadata: Sendable {
    public let id: UsageProvider
    public let displayName: String
    public let shortDisplayName: String
    public let sessionLabel: String
    public let weeklyLabel: String
    public let opusLabel: String?
    public let supportsOpus: Bool
    public let supportsCredits: Bool
    public let creditsHint: String
    public let toggleTitle: String
    public let cliName: String
    public let defaultEnabled: Bool
    public let widgetSelectable: Bool
    public let isPrimaryProvider: Bool
    public let usesAccountFallback: Bool
    public let sharePlanLabels: [String: String]
    public let debugLogUnavailableMessage: String?
    public let debugPane: ProviderDebugPaneCapabilities
    public let balanceOnly: Bool
    public let usesDetailBackedWindow: Bool
    public let browserCookieOrder: BrowserCookieImportOrder?
    public let dashboardURL: String?
    public let subscriptionDashboardURL: String?
    /// Provider-specific release notes or changelog URL for CLI/provider updates.
    public let changelogURL: String?
    /// Statuspage.io base URL for incident polling (append /api/v2/status.json).
    public let statusPageURL: String?
    /// Browser-only status link (no API polling); used when statusPageURL is nil.
    public let statusLinkURL: String?
    /// Google Workspace product ID for status polling (appsstatus dashboard).
    public let statusWorkspaceProductID: String?
    /// Optional top-level component/group names to show from a provider status feed.
    public let statusComponentAllowlist: Set<String>?

    public init(
        id: UsageProvider,
        displayName: String,
        shortDisplayName: String? = nil,
        sessionLabel: String,
        weeklyLabel: String,
        opusLabel: String?,
        supportsOpus: Bool,
        supportsCredits: Bool,
        creditsHint: String,
        toggleTitle: String,
        cliName: String,
        defaultEnabled: Bool,
        widgetSelectable: Bool = true,
        isPrimaryProvider: Bool = false,
        usesAccountFallback: Bool = false,
        sharePlanLabels: [String: String] = [:],
        debugLogUnavailableMessage: String? = nil,
        debugPane: ProviderDebugPaneCapabilities = .init(),
        balanceOnly: Bool = false,
        usesDetailBackedWindow: Bool = false,
        browserCookieOrder: BrowserCookieImportOrder? = nil,
        dashboardURL: String?,
        subscriptionDashboardURL: String? = nil,
        changelogURL: String? = nil,
        statusPageURL: String?,
        statusLinkURL: String? = nil,
        statusWorkspaceProductID: String? = nil,
        statusComponentAllowlist: Set<String>? = nil)
    {
        self.id = id
        self.displayName = displayName
        self.shortDisplayName = shortDisplayName ?? displayName
        self.sessionLabel = sessionLabel
        self.weeklyLabel = weeklyLabel
        self.opusLabel = opusLabel
        self.supportsOpus = supportsOpus
        self.supportsCredits = supportsCredits
        self.creditsHint = creditsHint
        self.toggleTitle = toggleTitle
        self.cliName = cliName
        self.defaultEnabled = defaultEnabled
        self.widgetSelectable = widgetSelectable
        self.isPrimaryProvider = isPrimaryProvider
        self.usesAccountFallback = usesAccountFallback
        self.sharePlanLabels = sharePlanLabels
        self.debugLogUnavailableMessage = debugLogUnavailableMessage
        self.debugPane = debugPane
        self.balanceOnly = balanceOnly
        self.usesDetailBackedWindow = usesDetailBackedWindow
        self.browserCookieOrder = browserCookieOrder
        self.dashboardURL = dashboardURL
        self.subscriptionDashboardURL = subscriptionDashboardURL
        self.changelogURL = changelogURL
        self.statusPageURL = statusPageURL
        self.statusLinkURL = statusLinkURL
        self.statusWorkspaceProductID = statusWorkspaceProductID
        self.statusComponentAllowlist = statusComponentAllowlist
    }
}

// SwiftFormat 0.61.1's Linux `enumNamespaces` rule times out on these explicit namespaces.
// swiftformat:disable enumNamespaces
public enum ProviderDefaults {
    public static var metadata: [UsageProvider: ProviderMetadata] {
        ProviderDescriptorRegistry.metadata
    }
}

public enum ProviderBrowserCookieDefaults {
    public static var defaultImportOrder: BrowserCookieImportOrder? {
        #if os(macOS)
        Browser.defaultImportOrder
        #else
        nil
        #endif
    }
}

// swiftformat:enable enumNamespaces
