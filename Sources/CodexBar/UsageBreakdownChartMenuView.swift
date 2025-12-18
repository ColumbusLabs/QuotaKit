import Charts
import CodexBarCore
import SwiftUI

@MainActor
struct UsageBreakdownChartMenuView: View {
    private struct Point: Identifiable {
        let id: String
        let date: Date
        let service: String
        let creditsUsed: Double

        init(date: Date, service: String, creditsUsed: Double) {
            self.date = date
            self.service = service
            self.creditsUsed = creditsUsed
            self.id = "\(service)-\(Int(date.timeIntervalSince1970))- \(creditsUsed)"
        }
    }

    private let breakdown: [OpenAIDashboardDailyBreakdown]

    init(breakdown: [OpenAIDashboardDailyBreakdown]) {
        self.breakdown = breakdown
    }

    var body: some View {
        let model = Self.makeModel(from: self.breakdown)
        VStack(alignment: .leading, spacing: 10) {
            if model.points.isEmpty {
                Text("No usage breakdown data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart(model.points) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Credits used", point.creditsUsed))
                        .foregroundStyle(by: .value("Service", point.service))
                }
                .chartForegroundStyleScale(domain: model.services, range: model.serviceColors)
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
                .allowsHitTesting(false)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
                    alignment: .leading,
                    spacing: 6)
                {
                    ForEach(model.services, id: \.self) { service in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(model.color(for: service))
                                .frame(width: 7, height: 7)
                            Text(service)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
    }

    private struct Model {
        let points: [Point]
        let services: [String]
        let serviceColors: [Color]
        let axisDates: [Date]

        func color(for service: String) -> Color {
            guard let idx = self.services.firstIndex(of: service), idx < self.serviceColors.count else {
                return .secondary
            }
            return self.serviceColors[idx]
        }
    }

    private static func makeModel(from breakdown: [OpenAIDashboardDailyBreakdown]) -> Model {
        let sorted = breakdown
            .sorted { lhs, rhs in lhs.day < rhs.day }

        var points: [Point] = []
        points.reserveCapacity(sorted.count * 2)

        for day in sorted {
            guard let date = self.dateFromDayKey(day.day) else { continue }
            for service in day.services where service.creditsUsed > 0 {
                points.append(Point(date: date, service: service.service, creditsUsed: service.creditsUsed))
            }
        }

        let services = Self.serviceOrder(from: sorted)
        let colors = services.map { Self.colorForService($0) }
        let axisDates = Self.axisDates(fromSortedDays: sorted)

        return Model(points: points, services: services, serviceColors: colors, axisDates: axisDates)
    }

    private static func serviceOrder(from breakdown: [OpenAIDashboardDailyBreakdown]) -> [String] {
        var totals: [String: Double] = [:]
        for day in breakdown {
            for service in day.services {
                totals[service.service, default: 0] += service.creditsUsed
            }
        }

        return totals
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map(\.key)
    }

    private static func colorForService(_ service: String) -> Color {
        let lower = service.lowercased()
        if lower == "cli" {
            return Color(red: 0.26, green: 0.55, blue: 0.96)
        }
        if lower.contains("github"), lower.contains("review") {
            return Color(red: 0.94, green: 0.53, blue: 0.18)
        }
        let palette: [Color] = [
            Color(red: 0.46, green: 0.75, blue: 0.36),
            Color(red: 0.80, green: 0.45, blue: 0.92),
            Color(red: 0.26, green: 0.78, blue: 0.86),
            Color(red: 0.94, green: 0.74, blue: 0.26),
        ]
        let idx = abs(service.hashValue) % palette.count
        return palette[idx]
    }

    private static func axisDates(fromSortedDays sortedDays: [OpenAIDashboardDailyBreakdown]) -> [Date] {
        guard let first = sortedDays.first, let last = sortedDays.last else { return [] }
        guard let firstDate = self.dateFromDayKey(first.day),
              let lastDate = self.dateFromDayKey(last.day)
        else {
            return []
        }
        if Calendar.current.isDate(firstDate, inSameDayAs: lastDate) {
            return [firstDate]
        }
        return [firstDate, lastDate]
    }

    private static func dateFromDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = TimeZone.current
        comps.year = year
        comps.month = month
        comps.day = day
        // Noon avoids off-by-one-day shifts if anything ends up interpreted in UTC.
        comps.hour = 12
        return comps.date
    }
}
