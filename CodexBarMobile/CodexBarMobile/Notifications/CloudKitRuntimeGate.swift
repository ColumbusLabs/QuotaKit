import Foundation

enum CloudKitRuntimeGate {
    static var isDisabledForLocalLaunch: Bool {
        if ProcessInfo.processInfo.environment["QUOTAKIT_DISABLE_CLOUDKIT"] == "1" {
            return true
        }

        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
