import CodexBarSync
import Foundation

struct RemoteConfig: Codable, Equatable, Sendable {
    static let supportedSchemaVersion = 1
    static let defaults = RemoteConfig(
        schemaVersion: Self.supportedSchemaVersion,
        configVersion: "bundled",
        minimumSupportedBuild: 1,
        recommendedBuild: nil,
        macSetupURL: ProductConfig.macSetupURL.absoluteString,
        disabledFeatureIDs: [],
        announcements: [])

    struct Announcement: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let body: String
        let isEnabled: Bool

        init(
            id: String,
            title: String,
            body: String,
            isEnabled: Bool = true)
        {
            self.id = id
            self.title = title
            self.body = body
            self.isEnabled = isEnabled
        }
    }

    let schemaVersion: Int
    let configVersion: String
    let minimumSupportedBuild: Int?
    let recommendedBuild: Int?
    let macSetupURL: String?
    let disabledFeatureIDs: [String]
    let announcements: [Announcement]

    init(
        schemaVersion: Int,
        configVersion: String,
        minimumSupportedBuild: Int? = nil,
        recommendedBuild: Int? = nil,
        macSetupURL: String? = nil,
        disabledFeatureIDs: [String] = [],
        announcements: [Announcement] = [])
    {
        self.schemaVersion = schemaVersion
        self.configVersion = configVersion
        self.minimumSupportedBuild = minimumSupportedBuild
        self.recommendedBuild = recommendedBuild
        self.macSetupURL = macSetupURL
        self.disabledFeatureIDs = disabledFeatureIDs
        self.announcements = announcements
    }

    var isSupported: Bool {
        self.schemaVersion == Self.supportedSchemaVersion
    }

    var effectiveMacSetupURL: URL {
        guard let macSetupURL,
              let url = URL(string: macSetupURL),
              url.scheme == "https"
        else {
            return ProductConfig.macSetupURL
        }
        return url
    }

    var effectiveMacSetupDisplayURL: String {
        let url = self.effectiveMacSetupURL
        guard let host = url.host else { return ProductConfig.macSetupDisplayURL }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? host : "\(host)/\(path)"
    }

    var activeAnnouncements: [Announcement] {
        self.announcements.filter(\.isEnabled)
    }

    func disables(_ feature: FeatureGate) -> Bool {
        Set(self.disabledFeatureIDs).contains(feature.rawValue)
    }
}
