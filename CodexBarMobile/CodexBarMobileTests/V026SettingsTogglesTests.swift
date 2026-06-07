import Foundation
import XCTest

@testable import CodexBarMobile

/// Pins the UserDefaults persistence contract for the two new settings
/// toggles added in iOS 1.7.0 (mirrors of upstream PRs #918 and #929).
///
/// Why pin these as separate tests: both toggles are observed through
/// `@AppStorage`, which silently uses the canonical UserDefaults key
/// — a typo in the key constant means the toggle would *appear* to
/// flip in the UI but the UsageCardView observer would never read the
/// new value and the markers would keep showing. Pin the exact keys
/// and the default-false behavior to catch that regression class.
final class V026SettingsTogglesTests: XCTestCase {

    override func setUp() {
        super.setUp()
        let d = UserDefaults.standard
        d.removeObject(forKey: MobileSettingsKeys.hideQuotaWarningMarkers)
        d.removeObject(forKey: MobileSettingsKeys.showProviderChangelogLinks)
        d.removeObject(forKey: MobileSettingsKeys.appearanceMode)
    }

    override func tearDown() {
        let d = UserDefaults.standard
        d.removeObject(forKey: MobileSettingsKeys.hideQuotaWarningMarkers)
        d.removeObject(forKey: MobileSettingsKeys.showProviderChangelogLinks)
        d.removeObject(forKey: MobileSettingsKeys.appearanceMode)
        super.tearDown()
    }

    func testHideQuotaWarningMarkersKeyMatchesContract() {
        // Pin the wire-key string. UsageCardView reads via
        // `@AppStorage(MobileSettingsKeys.hideQuotaWarningMarkers)` and
        // any rename here would silently sever the observer.
        XCTAssertEqual(MobileSettingsKeys.hideQuotaWarningMarkers, "hideQuotaWarningMarkers")
    }

    func testShowProviderChangelogLinksKeyMatchesContract() {
        XCTAssertEqual(MobileSettingsKeys.showProviderChangelogLinks, "showProviderChangelogLinks")
    }

    func testHideQuotaWarningMarkersDefaultsToFalse() {
        // Default-off: existing markers stay visible until the user
        // opts in. Mirrors Mac PR #918 behavior.
        let stored = UserDefaults.standard.object(forKey: MobileSettingsKeys.hideQuotaWarningMarkers)
        XCTAssertNil(stored)
        let read = UserDefaults.standard.bool(forKey: MobileSettingsKeys.hideQuotaWarningMarkers)
        XCTAssertFalse(read)
    }

    func testShowProviderChangelogLinksDefaultsToFalse() {
        let stored = UserDefaults.standard.object(forKey: MobileSettingsKeys.showProviderChangelogLinks)
        XCTAssertNil(stored)
        let read = UserDefaults.standard.bool(forKey: MobileSettingsKeys.showProviderChangelogLinks)
        XCTAssertFalse(read)
    }

    func testHideQuotaWarningMarkersPersistsWriteAndRead() {
        UserDefaults.standard.set(true, forKey: MobileSettingsKeys.hideQuotaWarningMarkers)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: MobileSettingsKeys.hideQuotaWarningMarkers))
        UserDefaults.standard.set(false, forKey: MobileSettingsKeys.hideQuotaWarningMarkers)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: MobileSettingsKeys.hideQuotaWarningMarkers))
    }

    func testShowProviderChangelogLinksPersistsWriteAndRead() {
        UserDefaults.standard.set(true, forKey: MobileSettingsKeys.showProviderChangelogLinks)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: MobileSettingsKeys.showProviderChangelogLinks))
        UserDefaults.standard.set(false, forKey: MobileSettingsKeys.showProviderChangelogLinks)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: MobileSettingsKeys.showProviderChangelogLinks))
    }

    func testAppearanceModeKeyMatchesContract() {
        XCTAssertEqual(MobileSettingsKeys.appearanceMode, "appearanceMode")
    }

    func testAppearanceModeDefaultsToUnset() {
        XCTAssertNil(UserDefaults.standard.string(forKey: MobileSettingsKeys.appearanceMode))
    }
}
