import CodexBarCore
import CryptoKit
import Foundation

extension SpendDashboardSource {
    static func snapshotRevision(
        _ snapshot: CostUsageTokenSnapshot,
        coverageCalendar: Calendar? = nil) -> String
    {
        var encoder = SnapshotBackedRevisionEncoder()
        encoder.append(snapshot.currencyCode)
        encoder.append(snapshot.historyDays)
        encoder.append(snapshot.historyCoverageIsEstablished)
        encoder.append(snapshot.detailsAreComplete)
        // Content-backed sources still advance at their coverage-day boundary, not every fetch.
        let coverageDate = coverageCalendar?.startOfDay(for: snapshot.updatedAt) ?? snapshot.updatedAt
        encoder.append(coverageDate.timeIntervalSinceReferenceDate)
        encoder.append(snapshot.historyScanIsPartial)
        encoder.append(snapshot.historySinceDayKey ?? "")
        encoder.append(snapshot.historyUntilDayKey ?? "")
        encoder.append(snapshot.historyLabel ?? "")
        encoder.append(snapshot.meteredCostUSD)
        encoder.append(snapshot.costProvenance.rawValue)
        encoder.append(snapshot.last30DaysTokens)
        encoder.append(snapshot.last30DaysCostUSD)
        encoder.append(snapshot.last30DaysRequests)
        // Reuse the daily model's complete encoding rather than a second field list that can drift.
        let contentEncoder = JSONEncoder()
        contentEncoder.outputFormatting = [.sortedKeys]
        contentEncoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        encoder.append((try? contentEncoder.encode(snapshot.daily)) ?? Data())
        encoder.append(snapshot.hourly.count)
        for entry in snapshot.hourly {
            encoder.append(entry.hour.timeIntervalSinceReferenceDate)
            encoder.append(entry.tokensAreComplete)
            encoder.append(entry.costIsComplete)
            encoder.append(entry.totalTokens)
            encoder.append(entry.costUSD)
        }
        encoder.append(snapshot.projects.count)
        encoder.append(snapshot.sessions.count)
        for project in snapshot.projects {
            encoder.append(project.name)
            encoder.append(project.isProjectless)
            encoder.append(project.path ?? "")
            encoder.append(project.totalTokens)
            encoder.append(project.totalCostUSD)
            encoder.append((try? contentEncoder.encode(project.daily)) ?? Data())
            encoder.append((try? contentEncoder.encode(project.modelBreakdowns ?? [])) ?? Data())
        }
        for session in snapshot.sessions {
            encoder.append(session.sessionID)
            encoder.append(session.lastActivity.timeIntervalSinceReferenceDate)
            encoder.append(session.totalTokens)
            encoder.append(session.costUSD)
            encoder.append(session.requestCount)
            encoder.append(session.title ?? "")
            encoder.append(session.projectPath ?? "")
            encoder.append((try? contentEncoder.encode(session.modelBreakdowns)) ?? Data())
        }
        return encoder.finalize()
    }
}

private struct SnapshotBackedRevisionEncoder {
    private var hasher = SHA256()

    mutating func append(_ value: String) {
        self.append(Data(value.utf8))
    }

    mutating func append(_ data: Data) {
        self.append(UInt64(data.count))
        self.hasher.update(data: data)
    }

    mutating func append(_ value: Int) {
        self.append(UInt64(bitPattern: Int64(value)))
    }

    mutating func append(_ value: Int?) {
        guard let value else {
            self.appendPresence(false)
            return
        }
        self.appendPresence(true)
        self.append(value)
    }

    mutating func append(_ value: Bool) {
        self.appendPresence(value)
    }

    mutating func append(_ value: Double) {
        self.append(value.bitPattern)
    }

    mutating func append(_ value: Double?) {
        guard let value else {
            self.appendPresence(false)
            return
        }
        self.appendPresence(true)
        self.append(value)
    }

    mutating func finalize() -> String {
        self.hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private mutating func appendPresence(_ isPresent: Bool) {
        var byte: UInt8 = isPresent ? 1 : 0
        withUnsafeBytes(of: &byte) { bytes in
            self.hasher.update(data: Data(bytes))
        }
    }

    private mutating func append(_ value: UInt64) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { bytes in
            self.hasher.update(data: Data(bytes))
        }
    }
}
