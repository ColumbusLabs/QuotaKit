import WidgetKit

/// App-target-only seam for `WidgetCenter.reloadAllTimelines()`.
/// Pro transitions reload from `CodexBarMobileApp`; snapshot writes reload from
/// `WidgetSnapshotPublisher` when encoded payload changes.
enum WidgetTimelineRefresher {
    static func reloadAllTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
