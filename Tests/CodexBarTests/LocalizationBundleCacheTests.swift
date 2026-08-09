import Foundation
import Testing
@testable import CodexBar

struct LocalizationBundleCacheTests {
    @Test
    func `localized bundle resolves English resources`() {
        let bundle = codexBarLocalizedBundleForTesting()

        #expect(bundle.bundleURL.lastPathComponent == "en.lproj")
    }

    @Test
    func `repeated calls resolve the same English bundle`() {
        let first = codexBarLocalizedBundleForTesting()
        let second = codexBarLocalizedBundleForTesting()

        #expect(first.bundleURL == second.bundleURL)
    }

    @Test
    func `format locale follows English resources`() {
        let locale = codexBarLocalizedResourceLocale()

        #expect(locale.language.languageCode?.identifier == "en")
    }

    @Test
    func `English stringsdict expands singular forms`() {
        let rendered = String(
            format: L("≈%d full 5h windows of weekly left · %d windows until reset"),
            locale: codexBarLocalizedResourceLocale(),
            arguments: [1, 1])

        #expect(rendered == "≈1 full 5h window of weekly left · 1 window until reset")
    }

    @Test
    func `resolution survives an explicit cache reset`() {
        let first = codexBarLocalizedBundleForTesting()
        resetCodexBarLocalizationCacheForTesting()
        let afterReset = codexBarLocalizedBundleForTesting()

        #expect(first.bundleURL == afterReset.bundleURL)
        #expect(afterReset.bundleURL.lastPathComponent == "en.lproj")
    }
}
