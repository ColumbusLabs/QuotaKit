import Testing
@testable import CodexBar
@testable import CodexBarCore

struct ProviderCookieSourceUITests {
    @Test
    func `selects the supplied localized subtitle without rewriting its text`() {
        let manual = L("Paste a Cookie header from %@.", "modelstudio.console.alibabacloud.com")
        let subtitles = ProviderCookieSourceUI.Subtitles(
            auto: "Localized browser import copy",
            manual: manual,
            off: "Localized disabled copy")

        #expect(ProviderCookieSourceUI.subtitle(source: .auto, keychainDisabled: false, subtitles: subtitles)
            == subtitles.auto)
        #expect(ProviderCookieSourceUI.subtitle(source: .manual, keychainDisabled: false, subtitles: subtitles)
            == manual)
        #expect(ProviderCookieSourceUI.subtitle(source: .off, keychainDisabled: false, subtitles: subtitles)
            == subtitles.off)
    }

    @Test
    func `keychain disabled uses localized warning with manual copy except when off`() {
        let subtitles = ProviderCookieSourceUI.Subtitles(
            auto: "Localized automatic copy",
            manual: "Localized manual copy",
            off: "Localized off copy")
        let warning = L(ProviderCookieSourceUI.keychainDisabledPrefixKey)

        #expect(ProviderCookieSourceUI.subtitle(source: .auto, keychainDisabled: true, subtitles: subtitles)
            == "\(warning) \(subtitles.manual)")
        #expect(ProviderCookieSourceUI.subtitle(source: .manual, keychainDisabled: true, subtitles: subtitles)
            == "\(warning) \(subtitles.manual)")
        #expect(ProviderCookieSourceUI.subtitle(source: .off, keychainDisabled: true, subtitles: subtitles)
            == subtitles.off)
    }

    @Test
    func `Alibaba Token Plan localizes a dynamic host and its fallback`() {
        let host = "modelstudio.console.alibabacloud.com"
        let hostSubtitle = AlibabaTokenPlanProviderImplementation.manualCookieHeaderSubtitle(host: host)
        let fallbackSubtitle = AlibabaTokenPlanProviderImplementation.manualCookieHeaderSubtitle(host: nil)
        let subtitles = ProviderCookieSourceUI.Subtitles(
            auto: "Localized automatic copy",
            manual: fallbackSubtitle,
            off: "Localized off copy")

        #expect(hostSubtitle == L("Paste a Cookie header from %@.", host))
        #expect(fallbackSubtitle == L("Paste a Cookie header from the selected console."))
        #expect(ProviderCookieSourceUI.subtitle(source: .manual, keychainDisabled: false, subtitles: subtitles)
            == fallbackSubtitle)
    }
}
