import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

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

    @Test
    func `ordinary settings fixtures own their keychain policy`() {
        KeychainAccessGate.withTaskOverrideForTesting(true) {
            let first = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
            let second = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())

            #expect(!first.keychainAccessPolicy.isExplicitlyDisabled())
            first.debugDisableKeychainAccess = true
            #expect(first.keychainAccessPolicy.isExplicitlyDisabled())
            #expect(!second.keychainAccessPolicy.isExplicitlyDisabled())
            first.debugDisableKeychainAccess = false
            #expect(!first.keychainAccessPolicy.isExplicitlyDisabled())
            #expect(KeychainAccessGate.isDisabled)
        }
    }
}
