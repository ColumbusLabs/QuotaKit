import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SettingsStoreTestIsolationTests {
    @Test
    func `test settings do not discover app group defaults`() {
        #expect(SettingsStore.isRunningTests)
        var didResolve = false
        let resolved = SettingsStore.resolveSharedDefaults {
            didResolve = true
            return InMemoryUserDefaults()
        }
        #expect(resolved == nil)
        #expect(!didResolve)
        #expect(!SettingsStore.shouldBridgeSharedDefaults(for: InMemoryUserDefaults()))
    }

    @Test
    func `test settings use the injected keychain policy`() {
        var setValues: [Bool] = []
        let policy = SettingsStoreKeychainAccessPolicy(
            setDisabled: { setValues.append($0) },
            isExplicitlyDisabled: { false })
        let store = testSettingsStore(
            suiteName: "SettingsStoreTestIsolationTests-keychain",
            userDefaults: InMemoryUserDefaults(),
            keychainAccessPolicy: policy)
        store.debugDisableKeychainAccess = true
        #expect(setValues.first == false)
        #expect(setValues.last == true)
    }
}
