import Foundation
import Testing
@testable import CodexBarCore

struct CodexConfigCookieDenialTests {
    @Test
    func `CLI config reads honor a stored web denial before the app save completes`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexConfigCookieDenialTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")

        for source in [ProviderCookieSource.auto, .manual] {
            var config = CodexBarConfig.makeDefault()
            var codex = config.providerConfig(for: .codex) ?? ProviderConfig(id: .codex)
            codex.cookieSource = source
            config.setProviderConfig(codex)

            let deniedStore = CodexBarConfigStore(fileURL: url, openAIWebAccessEnabledOverride: false)
            try deniedStore.save(config)
            #expect(try deniedStore.load()?.providerConfig(for: .codex)?.cookieSource == .off)

            let onDisk = try JSONDecoder().decode(CodexBarConfig.self, from: Data(contentsOf: url))
            #expect(onDisk.providerConfig(for: .codex)?.cookieSource == source)

            let allowedStore = CodexBarConfigStore(fileURL: url, openAIWebAccessEnabledOverride: true)
            #expect(try allowedStore.load()?.providerConfig(for: .codex)?.cookieSource == source)
        }
    }
}
