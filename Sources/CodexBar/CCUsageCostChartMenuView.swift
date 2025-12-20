import Charts
import CodexBarCore
import SwiftUI

@MainActor
struct CCUsageCostChartMenuView: View {
    private struct Point: Identifiable {
        let id: String
        let date: Date
        let costUSD: Double
        let totalTokens: Int?

        init(date: Date, costUSD: Double, totalTokens: Int?) {
            self.date = date
            self.costUSD = costUSD
            self.totalTokens = totalTokens
            self.id = "\(Int(date.timeIntervalSince1970))-\(costUSD)"
        }
    }

    private let provider: UsageProvider
    private let daily: [CCUsageDailyReport.Entry]
    private let totalCostUSD: Double?
    @State private var selectedDateKey: String?

    init(provider: UsageProvider, daily: [CCUsageDailyReport.Entry], totalCostUSD: Double?) {
        self.provider = provider
        self.daily = daily
        self.totalCostUSD = totalCostUSD
    }

    var body: some View {
        let model = Self.makeModel(provider: self.provider, daily: self.daily)
        VStack(alignment: .leading, spacing: 10) {
            if model.points.isEmpty {
                Text("No cost history data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart(model.points) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Cost", point.costUSD))
                        .foregroundStyle(model.barColor)
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: model.axisDates) { _ in
                        AxisGridLine().foregroundStyle(Color.clear)
                        AxisTick().foregroundStyle(Color.clear)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(.secondary)
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 130)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        MouseLocationReader { location in
                            self.updateSelection(location: location, model: model, proxy: proxy, geo: geo)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                }

                Text(self.detailText(model: model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 16, alignment: .leading)
            }

            if let total = self.totalCostUSD {
                Text("Total (30d): \(UsageFormatter.usdString(total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
    }

    private struct Model {
        let points: [Point]
        let pointsByDateKey: [String: Point]
        let dateKeys: [(key: String, date: Date)]
        let axisDates: [Date]
        let barColor: Color
    }

    private static func makeModel(provider: UsageProvider, daily: [CCUsageDailyReport.Entry]) -> Model {
        let sorted = daily.sorted { lhs, rhs in lhs.date < rhs.date }
        var points: [Point] = []
        points.reserveCapacity(sorted.count)

        var pointsByKey: [String: Point] = [:]
        pointsByKey.reserveCapacity(sorted.count)

        var dateKeys: [(key: String, date: Date)] = []
        dateKeys.reserveCapacity(sorted.count)

        for entry in sorted {
            guard let costUSD = entry.costUSD, costUSD > 0 else { continue }
            guard let date = self.dateFromDayKey(entry.date) else { continue }
            let point = Point(date: date, costUSD: costUSD, totalTokens: entry.totalTokens)
            points.append(point)
            pointsByKey[entry.date] = point
            dateKeys.append((entry.date, date))
        }

        let axisDates: [Date] = {
            guard let first = dateKeys.first?.date, let last = dateKeys.last?.date else { return [] }
            if Calendar.current.isDate(first, inSameDayAs: last) { return [first] }
            return [first, last]
        }()

        let barColor = Self.barColor(for: provider)
        return Model(
            points: points,
            pointsByDateKey: pointsByKey,
            dateKeys: dateKeys,
            axisDates: axisDates,
            barColor: barColor)
    }

    private static func barColor(for provider: UsageProvider) -> Color {
        switch provider {
        case .codex:
            Color(red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        case .claude:
            Color(red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        case .gemini:
            Color(red: 171 / 255, green: 135 / 255, blue: 234 / 255)
        }
    }

    private static func dateFromDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }

        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = TimeZone.current
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return comps.date
    }

    private func updateSelection(
        location: CGPoint?,
        model: Model,
        proxy: ChartProxy,
        geo: GeometryProxy)
    {
        guard let location else {
            if self.selectedDateKey != nil { self.selectedDateKey = nil }
            return
        }

        guard let plotAnchor = proxy.plotFrame else { return }
        let plotFrame = geo[plotAnchor]
        guard plotFrame.contains(location) else { return }

        let xInPlot = location.x - plotFrame.origin.x
        guard let date: Date = proxy.value(atX: xInPlot) else { return }
        guard let nearest = self.nearestDateKey(to: date, model: model) else { return }

        if self.selectedDateKey != nearest {
            self.selectedDateKey = nearest
        }
    }

    private func nearestDateKey(to date: Date, model: Model) -> String? {
        guard !model.dateKeys.isEmpty else { return nil }
        var best: (key: String, distance: TimeInterval)?
        for entry in model.dateKeys {
            let dist = abs(entry.date.timeIntervalSince(date))
            if let cur = best {
                if dist < cur.distance { best = (entry.key, dist) }
            } else {
                best = (entry.key, dist)
            }
        }
        return best?.key
    }

    private func detailText(model: Model) -> String {
        guard let key = self.selectedDateKey,
              let point = model.pointsByDateKey[key],
              let date = Self.dateFromDayKey(key)
        else {
            return "Hover a bar for details"
        }

        let dayLabel = date.formatted(.dateTime.month(.abbreviated).day())
        let cost = UsageFormatter.usdString(point.costUSD)
        if let tokens = point.totalTokens {
            return "\(dayLabel): \(cost) · \(UsageFormatter.tokenCountString(tokens)) tokens"
        }
        return "\(dayLabel): \(cost)"
    }
}
