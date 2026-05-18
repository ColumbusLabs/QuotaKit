import CodexBarCore
import SwiftUI

extension UsageMenuCardView.Model {
    static func openAIAPIUsageNotes(_ usage: OpenAIAPIUsageSnapshot) -> [String] {
        let today = usage.latestDay
        let seven = usage.last7Days
        let thirty = usage.last30Days
        let todayNote = "Today: \(UsageFormatter.usdString(today.costUSD)) · " +
            "\(UsageFormatter.tokenCountString(today.totalTokens)) tokens"
        let sevenDayNote = "7d: \(UsageFormatter.usdString(seven.costUSD)) · " +
            "\(UsageFormatter.tokenCountString(seven.requests)) requests"
        let thirtyDayNote = "30d: \(UsageFormatter.tokenCountString(thirty.totalTokens)) tokens · " +
            "\(UsageFormatter.tokenCountString(thirty.requests)) requests"
        var notes: [String] = [
            todayNote,
            sevenDayNote,
            thirtyDayNote,
        ]
        if let topModel = usage.topModels.first {
            notes.append("Top model: \(topModel.name)")
        }
        return notes
    }
}

struct OpenAIAPIInlineDashboardContent: View {
    private let snapshot: OpenAIAPIUsageSnapshot
    private let points: [Point]
    private let today: OpenAIAPIUsageSnapshot.Summary
    private let last7: OpenAIAPIUsageSnapshot.Summary
    private let last30: OpenAIAPIUsageSnapshot.Summary
    @Environment(\.menuItemHighlighted) private var isHighlighted

    init(snapshot: OpenAIAPIUsageSnapshot) {
        self.snapshot = snapshot
        self.points = snapshot.daily.suffix(30).map {
            Point(
                day: $0.day,
                spend: $0.costUSD,
                requests: $0.requests,
                tokens: $0.totalTokens)
        }
        self.today = snapshot.latestDay
        self.last7 = snapshot.last7Days
        self.last30 = snapshot.last30Days
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.kpis
            MiniSpendBars(points: self.points)
                .frame(height: 58)
                .accessibilityLabel("OpenAI API 30 day spend trend")
            self.detailLines
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpis: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 118), alignment: .leading),
                GridItem(.flexible(minimum: 100), alignment: .leading),
            ],
            alignment: .leading,
            spacing: 6)
        {
            KPIBlock(title: "Today", value: UsageFormatter.usdString(self.today.costUSD), emphasis: true)
            KPIBlock(title: "7d spend", value: UsageFormatter.usdString(self.last7.costUSD), emphasis: false)
            KPIBlock(title: "30d spend", value: UsageFormatter.usdString(self.last30.costUSD), emphasis: false)
            KPIBlock(title: "Today req", value: UsageFormatter.tokenCountString(self.today.requests), emphasis: false)
        }
    }

    private var detailLines: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("30d: \(UsageFormatter.tokenCountString(self.last30.totalTokens)) tokens · " +
                "\(UsageFormatter.tokenCountString(self.last30.requests)) requests")
                .font(.caption)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
            if let topModel = self.snapshot.topModels.first {
                Text("Top model: \(Self.shortModelName(topModel.name))")
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }
        }
    }

    private static func shortModelName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 26 else { return trimmed }
        return String(trimmed.prefix(25)) + "…"
    }

    private struct Point: Identifiable {
        let day: String
        let spend: Double
        let requests: Int
        let tokens: Int

        var id: String {
            self.day
        }
    }

    private struct KPIBlock: View {
        let title: String
        let value: String
        let emphasis: Bool
        @Environment(\.menuItemHighlighted) private var isHighlighted

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(self.title)
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                Text(self.value)
                    .font(self.emphasis ? .headline : .subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct MiniSpendBars: View {
        let points: [Point]
        @Environment(\.menuItemHighlighted) private var isHighlighted

        var body: some View {
            let maxSpend = max(self.points.map(\.spend).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(self.points) { point in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.fill(for: point, maxSpend: maxSpend))
                        .frame(maxWidth: .infinity)
                        .frame(height: self.height(for: point, maxSpend: maxSpend))
                        .accessibilityLabel("\(point.day): \(UsageFormatter.usdString(point.spend))")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(0.22))
                    .frame(height: 1)
            }
        }

        private func height(for point: Point, maxSpend: Double) -> CGFloat {
            let ratio = point.spend / maxSpend
            guard ratio > 0 else { return 1 }
            return CGFloat(max(3, min(58, ratio * 58)))
        }

        private func fill(for point: Point, maxSpend: Double) -> Color {
            let ratio = max(0.18, min(1, point.spend / maxSpend))
            if self.isHighlighted {
                return Color.white.opacity(0.55 + ratio * 0.35)
            }
            return Color(red: 0.81, green: 0.56, blue: 0.24).opacity(0.42 + ratio * 0.58)
        }
    }
}
