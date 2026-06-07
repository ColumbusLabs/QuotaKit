import CodexBarSync
import Foundation
import Observation

protocol RemoteConfigFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

struct URLSessionRemoteConfigFetcher: RemoteConfigFetching {
    func data(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw RemoteConfigStore.Error.invalidResponse
        }
        return data
    }
}

@Observable
@MainActor
final class RemoteConfigStore {
    enum Source: Equatable {
        case bundled
        case cache
        case remote
    }

    enum Error: Swift.Error, Equatable, Sendable {
        case invalidResponse
        case unsupportedSchema(Int)
        case decodeFailed
    }

    private struct CacheEnvelope: Codable {
        let config: RemoteConfig
        let fetchedAt: Date
    }

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    nonisolated private static let cacheKey = "com.columbuslabs.quotakit.remoteConfig.v1"

    private let defaults: UserDefaults
    private let fetcher: any RemoteConfigFetching
    private let configURL: URL
    private var inFlightTask: Task<Void, Never>?

    private(set) var config: RemoteConfig
    private(set) var source: Source
    private(set) var lastFetchedAt: Date?
    private(set) var lastError: String?
    private(set) var isRefreshing = false

    var setupURL: URL {
        self.config.effectiveMacSetupURL
    }

    var setupDisplayURL: String {
        self.config.effectiveMacSetupDisplayURL
    }

    var activeAnnouncement: RemoteConfig.Announcement? {
        self.config.activeAnnouncements.first
    }

    var configStatusSummary: String {
        switch self.source {
        case .bundled:
            String(localized: "Bundled defaults")
        case .cache:
            String(localized: "Cached config")
        case .remote:
            String(localized: "Remote config active")
        }
    }

    init(
        defaults: UserDefaults? = nil,
        fetcher: any RemoteConfigFetching = URLSessionRemoteConfigFetcher(),
        configURL: URL = ProductConfig.remoteConfigURL)
    {
        self.defaults = defaults ?? Self.appGroupDefaults() ?? .standard
        self.fetcher = fetcher
        self.configURL = configURL

        if let envelope = Self.loadCache(defaults: self.defaults) {
            self.config = envelope.config
            self.source = .cache
            self.lastFetchedAt = envelope.fetchedAt
        } else {
            self.config = .defaults
            self.source = .bundled
            self.lastFetchedAt = nil
        }
    }

    func start() {
        guard self.inFlightTask == nil else { return }
        self.inFlightTask = Task { [weak self] in
            await self?.refresh()
            await MainActor.run {
                self?.inFlightTask = nil
            }
        }
    }

    func refresh() async {
        guard !self.isRefreshing else { return }
        self.isRefreshing = true
        defer { self.isRefreshing = false }

        do {
            let data = try await self.fetcher.data(from: self.configURL)
            let fetched = try Self.decodeSupportedConfig(data)
            let fetchedAt = Date()
            self.config = fetched
            self.source = .remote
            self.lastFetchedAt = fetchedAt
            self.lastError = nil
            Self.saveCache(
                CacheEnvelope(config: fetched, fetchedAt: fetchedAt),
                defaults: self.defaults)
        } catch {
            self.lastError = Self.describe(error)
        }
    }

    func isDisabled(_ feature: FeatureGate) -> Bool {
        self.config.disables(feature)
    }

    nonisolated static func decodeSupportedConfig(_ data: Data) throws -> RemoteConfig {
        let decoder = JSONDecoder()
        do {
            let schema = try decoder.decode(SchemaProbe.self, from: data)
            guard schema.schemaVersion == RemoteConfig.supportedSchemaVersion else {
                throw Error.unsupportedSchema(schema.schemaVersion)
            }

            let config = try decoder.decode(RemoteConfig.self, from: data)
            return config
        } catch let error as Error {
            throw error
        } catch {
            throw Error.decodeFailed
        }
    }

    nonisolated static func appGroupDefaults(
        appGroupIdentifier: String = ProductConfig.appGroupIdentifier
    ) -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private nonisolated static func loadCache(defaults: UserDefaults) -> CacheEnvelope? {
        guard let data = defaults.data(forKey: Self.cacheKey),
              let envelope = try? JSONDecoder().decode(CacheEnvelope.self, from: data),
              envelope.config.isSupported
        else {
            return nil
        }
        return envelope
    }

    private nonisolated static func saveCache(_ envelope: CacheEnvelope, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }

    private nonisolated static func describe(_ error: Swift.Error) -> String {
        switch error {
        case Error.invalidResponse:
            String(localized: "Invalid remote config response")
        case Error.unsupportedSchema(let version):
            String(format: String(localized: "Unsupported remote config schema %lld"), version)
        case Error.decodeFailed:
            String(localized: "Remote config could not be decoded")
        default:
            error.localizedDescription
        }
    }
}
