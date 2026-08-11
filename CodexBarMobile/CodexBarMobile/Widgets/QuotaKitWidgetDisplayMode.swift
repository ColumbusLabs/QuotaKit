import CodexBarSync
import Foundation

enum QuotaKitWidgetDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case both
    case session
    case weekly

    var id: String {
        self.rawValue
    }

    var localizedTitle: String {
        switch self {
        case .both:
            String(localized: "Both")
        case .session:
            String(localized: "Session")
        case .weekly:
            String(localized: "Weekly")
        }
    }
}

enum QuotaKitWidgetDisplayModeStore {
    static let key = "com.columbuslabs.quotakit.widgets.displayMode"

    static func appGroupDefaults(
        appGroupIdentifier: String = ProductConfig.appGroupIdentifier) -> UserDefaults?
    {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func load(
        defaults: UserDefaults? = nil,
        appGroupDefaults: () -> UserDefaults? = { Self.appGroupDefaults() }) -> QuotaKitWidgetDisplayMode
    {
        guard let storage = defaults ?? appGroupDefaults() else {
            return .both
        }
        guard let rawValue = storage.string(forKey: Self.key),
              let mode = QuotaKitWidgetDisplayMode(rawValue: rawValue)
        else {
            return .both
        }
        return mode
    }

    static func save(
        _ mode: QuotaKitWidgetDisplayMode,
        defaults: UserDefaults? = nil,
        appGroupDefaults: () -> UserDefaults? = { Self.appGroupDefaults() })
    {
        guard let storage = defaults ?? appGroupDefaults() else {
            return
        }
        storage.set(mode.rawValue, forKey: Self.key)
    }
}

enum QuotaKitWidgetEntryDisplayModeResolver {
    static func resolve(
        isPreview: Bool,
        defaults: UserDefaults? = nil,
        appGroupDefaults: () -> UserDefaults? = { QuotaKitWidgetDisplayModeStore.appGroupDefaults() })
        -> QuotaKitWidgetDisplayMode
    {
        isPreview
            ? .both
            : QuotaKitWidgetDisplayModeStore.load(
                defaults: defaults,
                appGroupDefaults: appGroupDefaults)
    }
}

struct QuotaKitWidgetProviderPreferences: Equatable, Sendable {
    var providerOrderIDs: [String]
    var selectedProviderID: String?

    static let empty = QuotaKitWidgetProviderPreferences(
        providerOrderIDs: [],
        selectedProviderID: nil)
}

enum QuotaKitWidgetProviderPreferencesStore {
    static let providerOrderKey = "com.columbuslabs.quotakit.widgets.providerOrder"
    static let selectedProviderKey = "com.columbuslabs.quotakit.widgets.selectedProvider"

    static func appGroupDefaults(
        appGroupIdentifier: String = ProductConfig.appGroupIdentifier) -> UserDefaults?
    {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func load(
        defaults: UserDefaults? = nil,
        appGroupDefaults: () -> UserDefaults? = { Self.appGroupDefaults() })
        -> QuotaKitWidgetProviderPreferences
    {
        QuotaKitWidgetProviderPreferences(
            providerOrderIDs: self.loadProviderOrderIDs(
                defaults: defaults,
                appGroupDefaults: appGroupDefaults),
            selectedProviderID: self.loadSelectedProviderID(
                defaults: defaults,
                appGroupDefaults: appGroupDefaults))
    }

    static func loadProviderOrderIDs(
        defaults: UserDefaults? = nil,
        appGroupDefaults: () -> UserDefaults? = { Self.appGroupDefaults() }) -> [String]
    {
        guard let storage = defaults ?? appGroupDefaults() else { return [] }
        return Self.sanitizedProviderIDs(storage.stringArray(forKey: Self.providerOrderKey) ?? [])
    }

    static func saveProviderOrderIDs(
        _ providerIDs: [String],
        defaults: UserDefaults? = nil,
        appGroupDefaults: () -> UserDefaults? = { Self.appGroupDefaults() })
    {
        guard let storage = defaults ?? appGroupDefaults() else { return }
        storage.set(Self.sanitizedProviderIDs(providerIDs), forKey: Self.providerOrderKey)
    }

    static func loadSelectedProviderID(
        defaults: UserDefaults? = nil,
        appGroupDefaults: () -> UserDefaults? = { Self.appGroupDefaults() }) -> String?
    {
        guard let storage = defaults ?? appGroupDefaults(),
              let providerID = sanitizedProviderID(storage.string(forKey: selectedProviderKey))
        else {
            return nil
        }
        return providerID
    }

    static func saveSelectedProviderID(
        _ providerID: String?,
        defaults: UserDefaults? = nil,
        appGroupDefaults: () -> UserDefaults? = { Self.appGroupDefaults() })
    {
        guard let storage = defaults ?? appGroupDefaults() else { return }
        guard let providerID = Self.sanitizedProviderID(providerID) else {
            storage.removeObject(forKey: Self.selectedProviderKey)
            return
        }
        storage.set(providerID, forKey: Self.selectedProviderKey)
    }

    static func orderedItems<T>(
        _ items: [T],
        preferences: QuotaKitWidgetProviderPreferences,
        providerID: (T) -> String,
        providerName: (T) -> String) -> [T]
    {
        guard !preferences.providerOrderIDs.isEmpty else { return items }

        let orderIndex = Dictionary(
            uniqueKeysWithValues: preferences.providerOrderIDs.enumerated().map { index, providerID in
                (providerID, index)
            })

        return items.enumerated().sorted { left, right in
            let leftID = providerID(left.element)
            let rightID = providerID(right.element)
            let leftIndex = orderIndex[leftID]
            let rightIndex = orderIndex[rightID]

            switch (leftIndex, rightIndex) {
            case let (.some(leftIndex), .some(rightIndex)) where leftIndex != rightIndex:
                return leftIndex < rightIndex
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                let nameComparison = providerName(left.element)
                    .localizedCaseInsensitiveCompare(providerName(right.element))
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                return leftID.localizedCaseInsensitiveCompare(rightID) == .orderedAscending
            default:
                return left.offset < right.offset
            }
        }.map(\.element)
    }

    static func selectedProviderID(
        availableProviderIDs: [String],
        preferences: QuotaKitWidgetProviderPreferences) -> String?
    {
        let available = Set(Self.sanitizedProviderIDs(availableProviderIDs))
        guard !available.isEmpty else { return nil }

        if let selected = Self.sanitizedProviderID(preferences.selectedProviderID),
           available.contains(selected)
        {
            return selected
        }

        for providerID in preferences.providerOrderIDs where available.contains(providerID) {
            return providerID
        }

        return availableProviderIDs.first.flatMap(Self.sanitizedProviderID)
    }

    static func moveSelectedProviderFirst<T>(
        _ items: [T],
        preferences: QuotaKitWidgetProviderPreferences,
        providerID: (T) -> String) -> [T]
    {
        guard let selected = selectedProviderID(
            availableProviderIDs: items.map { providerID($0) },
            preferences: preferences),
            let selectedIndex = items.firstIndex(where: { providerID($0) == selected })
        else {
            return items
        }

        var result = items
        let selectedItem = result.remove(at: selectedIndex)
        result.insert(selectedItem, at: 0)
        return result
    }

    static func sanitizedProviderIDs(_ providerIDs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for providerID in providerIDs {
            guard let sanitized = Self.sanitizedProviderID(providerID),
                  !seen.contains(sanitized)
            else {
                continue
            }
            seen.insert(sanitized)
            result.append(sanitized)
        }
        return result
    }

    private static func sanitizedProviderID(_ providerID: String?) -> String? {
        guard let providerID else { return nil }
        let sanitized = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }
}
