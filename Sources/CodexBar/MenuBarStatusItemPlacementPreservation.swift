import Foundation

/// Keeps `NSStatusItem Preferred Position <autosaveName>` across status-item mutations.
///
/// macOS can clear that default when an item is removed or hidden while the app is still running.
/// QuotaKit removes and hides status items for recovery and visibility changes, so restore the saved
/// position when AppKit clears it. Retiring the autosave name before removal keeps its later cleanup
/// from erasing the restored stable position.
@MainActor
enum MenuBarStatusItemPlacementPreservation {
    @discardableResult
    static func preservingPreferredPosition<T>(
        autosaveName: String,
        defaults: UserDefaults,
        _ body: () -> T)
        -> T
    {
        guard !autosaveName.isEmpty else { return body() }
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: autosaveName)
        let savedPosition = defaults.object(forKey: key)
        let result = body()
        if let savedPosition, defaults.object(forKey: key) == nil {
            defaults.set(savedPosition, forKey: key)
        }
        return result
    }
}
