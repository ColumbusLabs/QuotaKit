import Foundation

enum CloudKitRuntimeGate {
    static var isDisabledForLocalLaunch: Bool {
        ProcessInfo.processInfo.environment["QUOTAKIT_DISABLE_CLOUDKIT"] == "1"
    }
}
