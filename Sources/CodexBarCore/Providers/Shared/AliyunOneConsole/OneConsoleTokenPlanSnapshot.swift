import Foundation

protocol OneConsoleTokenPlanSnapshot {
    var planName: String? { get }
    var usedQuota: Double? { get }
    var totalQuota: Double? { get }
    var remainingQuota: Double? { get }
    var resetsAt: Date? { get }
    var fiveHourUsedPercent: Double? { get }
    var fiveHourTotalQuota: Double? { get }
    var fiveHourResetsAt: Date? { get }
    var weeklyUsedPercent: Double? { get }
    var weeklyTotalQuota: Double? { get }
    var weeklyResetsAt: Date? { get }
    var monthlyWindow: RateWindow? { get }
    var updatedAt: Date { get }

    init(
        planName: String?,
        usedQuota: Double?,
        totalQuota: Double?,
        remainingQuota: Double?,
        resetsAt: Date?,
        fiveHourUsedPercent: Double?,
        fiveHourTotalQuota: Double?,
        fiveHourResetsAt: Date?,
        weeklyUsedPercent: Double?,
        weeklyTotalQuota: Double?,
        weeklyResetsAt: Date?,
        monthlyWindow: RateWindow?,
        updatedAt: Date)
}

extension OneConsoleTokenPlanSnapshot {
    private static func quotaDetail(usedPercent: Double, total: Double?) -> String? {
        guard let total, total > 0 else { return nil }
        let used = total * usedPercent / 100
        return "\(Self.format(used)) / \(Self.format(total)) credits used"
    }

    private static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

extension OneConsoleTokenPlanSnapshot {
    static func personalUsage(
        in expanded: Any,
        subscriptionData: Data?,
        quotaConfigData: Data?,
        defaultPlanName: String? = nil,
        now: Date,
        ratio: (Any?) -> Double? = OneConsoleJSON.number,
        resetDate: (Any?) -> Date? = OneConsoleJSON.date,
        requiresUsageForReset: Bool = false) -> Self?
    {
        guard let usage = OneConsoleJSON.findObject(
            containingAnyOf: ["per5HourPercentage", "per1WeekPercentage", "per1MonthPercentage"],
            in: expanded)
        else {
            return nil
        }

        let fiveHourPercent = OneConsoleJSON.percentagePoints(
            fromRatio: ratio(usage["per5HourPercentage"]))
        let weeklyPercent = OneConsoleJSON.percentagePoints(
            fromRatio: ratio(usage["per1WeekPercentage"]))
        let monthlyPercent = OneConsoleJSON.percentagePoints(fromRatio: ratio(usage["per1MonthPercentage"]))
        guard fiveHourPercent != nil || weeklyPercent != nil || monthlyPercent != nil else {
            return nil
        }

        func reset(_ key: String, percent: Double?) -> Date? {
            requiresUsageForReset && percent == nil ? nil : resetDate(usage[key])
        }

        let planCode = subscriptionData.flatMap(self.planCode)
        let quota = quotaConfigData.flatMap {
            self.quotaTotals(from: $0, planCode: planCode)
        }
        return Self(
            planName: planCode.map(self.displayPlanName) ?? defaultPlanName,
            usedQuota: nil,
            totalQuota: nil,
            remainingQuota: nil,
            resetsAt: nil,
            fiveHourUsedPercent: fiveHourPercent,
            fiveHourTotalQuota: quota?.fiveHour,
            fiveHourResetsAt: reset("per5HourResetTime", percent: fiveHourPercent),
            weeklyUsedPercent: weeklyPercent,
            weeklyTotalQuota: quota?.weekly,
            weeklyResetsAt: reset("per1WeekResetTime", percent: weeklyPercent),
            monthlyWindow: monthlyPercent.map {
                RateWindow(
                    usedPercent: $0,
                    windowMinutes: 30 * 24 * 60,
                    resetsAt: resetDate(usage["per1MonthResetTime"]),
                    resetDescription: Self.quotaDetail(usedPercent: $0, total: quota?.monthly))
            },
            updatedAt: now)
    }

    private static func planCode(from data: Data) -> String? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let expanded = OneConsoleJSON.expandEmbeddedJSON(raw)
        guard let plan = OneConsoleJSON.findObject(
            containingAnyOf: ["specCode", "spec_code", "planName", "plan_name"],
            in: expanded)
        else {
            return nil
        }
        for key in ["specCode", "spec_code", "planName", "plan_name"] {
            if let value = OneConsoleJSON.string(plan[key])?.lowercased(), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func displayPlanName(_ planCode: String) -> String {
        ["lite", "standard", "pro", "max"].contains(planCode) ? planCode.capitalized : planCode
    }

    private static func quotaTotals(
        from data: Data,
        planCode: String?) -> (fiveHour: Double?, weekly: Double?, monthly: Double?)?
    {
        guard let planCode,
              let raw = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }
        let expanded = OneConsoleJSON.expandEmbeddedJSON(raw)
        guard let value = OneConsoleJSON.findFirstValue(forKeys: [planCode], in: expanded),
              let quota = value as? [String: Any]
        else {
            return nil
        }
        let fiveHour = OneConsoleJSON.number(quota["five_hour"] ?? quota["fiveHour"])
        let weekly = OneConsoleJSON.number(quota["weekly"])
        let monthly = OneConsoleJSON.number(quota["monthly"])
        guard fiveHour != nil || weekly != nil || monthly != nil else { return nil }
        return (fiveHour, weekly, monthly)
    }
}
