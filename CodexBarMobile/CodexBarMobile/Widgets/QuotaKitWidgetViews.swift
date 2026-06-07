import CodexBarSync
import SwiftUI
import WidgetKit

struct QuotaKitWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaKitWidgetSnapshot?
    let isUnlocked: Bool
    let isPreview: Bool
}

struct QuotaKitWidgetView: View {
    let entry: QuotaKitWidgetEntry
    let overrideFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var family

    init(entry: QuotaKitWidgetEntry, overrideFamily: WidgetFamily? = nil) {
        self.entry = entry
        self.overrideFamily = overrideFamily
    }

    var body: some View {
        let family = self.overrideFamily ?? self.family
        Group {
            if !self.entry.isUnlocked {
                QuotaKitWidgetLockedView(family: family)
            } else if let snapshot = self.entry.snapshot,
                      let provider = snapshot.primaryProvider
            {
                switch family {
                case .systemMedium:
                    QuotaKitWidgetMediumView(snapshot: snapshot)
                case .accessoryRectangular:
                    QuotaKitWidgetAccessoryRectangularView(provider: provider)
                case .accessoryCircular:
                    QuotaKitWidgetAccessoryCircularView(provider: provider)
                default:
                    QuotaKitWidgetSmallView(provider: provider)
                }
            } else {
                QuotaKitWidgetEmptyView(family: family)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

private struct QuotaKitWidgetSmallView: View {
    let provider: QuotaKitWidgetSnapshot.Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "QuotaKit"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(self.provider.providerName)
                .font(.headline)
                .lineLimit(2)

            if let window = self.provider.primaryWindow {
                Gauge(value: window.remainingPercent, in: 0...100) {
                    Text(window.title)
                } currentValueLabel: {
                    Text("\(Int(window.remainingPercent.rounded()))%")
                }
                .gaugeStyle(.accessoryCircularCapacity)

                Text(String(localized: "quota left"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(self.provider.statusMessage ?? String(localized: "No quota window"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }
}

private struct QuotaKitWidgetMediumView: View {
    let snapshot: QuotaKitWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "QuotaKit"))
                    .font(.headline)
                Spacer()
                Text(self.snapshot.generatedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let providers = Array(self.snapshot.providers.prefix(3))
            ForEach(providers) { provider in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.providerName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(provider.primaryWindow?.title ?? provider.statusMessage ?? String(localized: "No quota window"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let remaining = provider.primaryWindow?.remainingPercent {
                        Text("\(Int(remaining.rounded()))%")
                            .font(.subheadline.monospacedDigit())
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: provider.isError ? "exclamationmark.triangle" : "minus")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}

private struct QuotaKitWidgetAccessoryRectangularView: View {
    let provider: QuotaKitWidgetSnapshot.Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(provider.providerName)
                .font(.headline)
                .lineLimit(1)
            if let window = provider.primaryWindow {
                Text(String(
                    format: String(localized: "%lld%% left · %@"),
                    Int64(window.remainingPercent.rounded()),
                    window.title))
                    .font(.caption)
            } else {
                Text(provider.statusMessage ?? String(localized: "No quota window"))
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }
}

private struct QuotaKitWidgetAccessoryCircularView: View {
    let provider: QuotaKitWidgetSnapshot.Provider

    var body: some View {
        if let window = provider.primaryWindow {
            Gauge(value: window.remainingPercent, in: 0...100) {
                Text(String(localized: "Quota"))
            } currentValueLabel: {
                Text("\(Int(window.remainingPercent.rounded()))")
                    .font(.caption2.monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            Image(systemName: provider.isError ? "exclamationmark.triangle" : "minus")
        }
    }
}

private struct QuotaKitWidgetLockedView: View {
    let family: WidgetFamily

    var body: some View {
        switch self.family {
        case .accessoryCircular:
            Image(systemName: "lock.fill")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "QuotaKit Pro"))
                    .font(.headline)
                Text(String(localized: "Unlock widgets"))
                    .font(.caption)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title2)
                Text(String(localized: "QuotaKit Pro"))
                    .font(.headline)
                Text(String(
                    format: String(localized: "Widgets are included with the %@ lifetime unlock."),
                    ProductConfig.launchPriceCopy))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding()
        }
    }
}

private struct QuotaKitWidgetEmptyView: View {
    let family: WidgetFamily

    var body: some View {
        switch self.family {
        case .accessoryCircular:
            Image(systemName: "hourglass")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "QuotaKit"))
                    .font(.headline)
                Text(String(localized: "Open the app after Mac sync"))
                    .font(.caption)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "QuotaKit"))
                    .font(.headline)
                Text(String(localized: "Open the app after your Mac syncs to refresh widget data."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding()
        }
    }
}

enum QuotaKitWidgetPreviewData {
    static let snapshot = QuotaKitWidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_803_000_000),
        providers: [
            .init(
                id: "codex",
                providerName: "Codex",
                lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
                statusMessage: nil,
                isError: false,
                windows: [
                    .init(
                        title: "Session",
                        usedPercent: 37,
                        remainingPercent: 63,
                        resetsAt: Date(timeIntervalSince1970: 1_803_018_000)),
                ]),
            .init(
                id: "claude",
                providerName: "Claude",
                lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
                statusMessage: nil,
                isError: false,
                windows: [
                    .init(
                        title: "Session",
                        usedPercent: 61,
                        remainingPercent: 39,
                        resetsAt: Date(timeIntervalSince1970: 1_803_012_000)),
                ]),
        ])
}
