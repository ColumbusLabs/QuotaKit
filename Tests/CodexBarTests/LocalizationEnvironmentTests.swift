import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct LocalizationEnvironmentTests {
    @Test
    func `Arabic formatted counts use the selected resource number system`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("ar") {
            #expect(L("%d%% in reserve", 12).contains(codexBarLocalizedInteger(12)))
        }
    }

    @Test(arguments: [
        ("ar", LayoutDirection.rightToLeft),
        ("fa", LayoutDirection.rightToLeft),
        ("en", LayoutDirection.leftToRight),
        ("zz", LayoutDirection.leftToRight),
    ])
    func `layout direction follows selected resources and English fallback`(
        language: String,
        expected: LayoutDirection)
    {
        CodexBarLocalizationOverride.$appLanguage.withValue(language) {
            #expect(codexBarLocalizedLayoutDirection() == expected)
        }
    }
}
