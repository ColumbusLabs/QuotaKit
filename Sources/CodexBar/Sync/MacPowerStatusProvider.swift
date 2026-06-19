import CodexBarSync
import Foundation
#if os(macOS)
import IOKit.ps
#endif

enum MacPowerStatusProvider {
    static func currentStatus(now: Date = Date()) -> SyncDevicePowerStatus {
        #if os(macOS)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return SyncDevicePowerStatus(batteryPercent: nil, state: .unknown, updatedAt: now)
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                Self.isPresentInternalBattery(description)
            else {
                continue
            }

            let percent = Self.batteryPercent(from: description)
            let state = Self.powerState(from: description, percent: percent)
            return SyncDevicePowerStatus(
                batteryPercent: percent,
                state: state,
                updatedAt: now)
        }

        return SyncDevicePowerStatus(batteryPercent: nil, state: .noBattery, updatedAt: now)
        #else
        return SyncDevicePowerStatus(batteryPercent: nil, state: .unknown, updatedAt: now)
        #endif
    }

    #if os(macOS)
    private static func isPresentInternalBattery(_ description: [String: Any]) -> Bool {
        let type = description[Self.key(kIOPSTypeKey)] as? String
        let isPresent = Self.boolValue(for: kIOPSIsPresentKey, in: description) ?? true
        return isPresent && type == Self.key(kIOPSInternalBatteryType)
    }

    private static func batteryPercent(from description: [String: Any]) -> Int? {
        guard let current = intValue(for: kIOPSCurrentCapacityKey, in: description),
              let capacityMax = intValue(for: kIOPSMaxCapacityKey, in: description),
              capacityMax > 0
        else {
            return nil
        }
        let percent = Double(current) / Double(capacityMax) * 100
        return Int(percent.rounded())
    }

    private static func powerState(
        from description: [String: Any],
        percent: Int?) -> SyncDevicePowerStatus.State
    {
        let sourceState = description[Self.key(kIOPSPowerSourceStateKey)] as? String
        let isCharging = Self.boolValue(for: kIOPSIsChargingKey, in: description) ?? false

        if sourceState == Self.key(kIOPSBatteryPowerValue) {
            return .battery
        }
        if sourceState == Self.key(kIOPSACPowerValue) {
            if isCharging { return .charging }
            if (percent ?? 0) >= 100 { return .charged }
            return .pluggedIn
        }
        return .unknown
    }

    private static func key(_ value: String) -> String {
        value
    }

    private static func intValue(
        for key: String,
        in description: [String: Any]) -> Int?
    {
        let rawValue = description[Self.key(key)]
        if let value = rawValue as? Int { return value }
        if let value = rawValue as? NSNumber { return value.intValue }
        return nil
    }

    private static func boolValue(
        for key: String,
        in description: [String: Any]) -> Bool?
    {
        let rawValue = description[Self.key(key)]
        if let value = rawValue as? Bool { return value }
        if let value = rawValue as? NSNumber { return value.boolValue }
        return nil
    }
    #endif
}
