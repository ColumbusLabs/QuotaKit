import CloudKit
import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Sync Error Mapping Tests")
struct SyncErrorTests {
    // MARK: - CloudSyncError from CKError

    @Test
    func `Network unavailable maps correctly`() {
        let ckError = CKError(.networkUnavailable)
        let syncError = CloudSyncError(from: ckError)
        #expect(syncError.description == "Network unavailable")
    }

    @Test
    func `Network failure maps to networkUnavailable`() {
        let ckError = CKError(.networkFailure)
        let syncError = CloudSyncError(from: ckError)
        #expect(syncError.description == "Network unavailable")
    }

    @Test
    func `Not authenticated maps correctly`() {
        let ckError = CKError(.notAuthenticated)
        let syncError = CloudSyncError(from: ckError)
        #expect(syncError.description == "iCloud account not signed in")
    }

    @Test
    func `Quota exceeded maps correctly`() {
        let ckError = CKError(.quotaExceeded)
        let syncError = CloudSyncError(from: ckError)
        #expect(syncError.description == "iCloud storage quota exceeded")
    }

    @Test
    func `Server response lost maps to server error`() {
        let ckError = CKError(.serverResponseLost)
        let syncError = CloudSyncError(from: ckError)
        if case .serverError = syncError {
            // Correct mapping
        } else {
            Issue.record("Expected .serverError, got \(syncError)")
        }
    }

    @Test
    func `Unknown error includes description`() {
        let ckError = CKError(.internalError)
        let syncError = CloudSyncError(from: ckError)
        if case let .unknown(msg) = syncError {
            #expect(!msg.isEmpty)
        } else {
            Issue.record("Expected .unknown, got \(syncError)")
        }
    }

    @Test
    func `Queryable recordName error maps to Production index issue`() {
        let ckError = CKError(
            .invalidArguments,
            userInfo: [
                NSLocalizedDescriptionKey: "Field 'recordName' is not marked queryable",
            ])
        let syncError = CloudSyncError(from: ckError)

        if case let .productionSchemaMissingQueryableIndex(fieldName) = syncError {
            #expect(fieldName == "recordName")
        } else {
            Issue.record("Expected .productionSchemaMissingQueryableIndex, got \(syncError)")
        }
    }

    // MARK: - SyncStatus properties

    @Test
    func `SyncStatus.error isError returns true`() {
        let status = SyncStatus.error(message: "test")
        #expect(status.isError == true)
    }

    @Test
    func `SyncStatus.noData isError returns true`() {
        let status = SyncStatus.noData
        #expect(status.isError == true)
    }

    @Test
    func `SyncStatus.incompatibleData isError returns true`() {
        let status = SyncStatus.incompatibleData
        #expect(status.isError == true)
    }

    @Test
    func `SyncStatus.synced isError returns false`() {
        let status = SyncStatus.synced(lastConfirmedSync: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(status.isError == false)
    }

    @Test
    func `SyncStatus.syncing isError returns false`() {
        let status = SyncStatus.syncing
        #expect(status.isError == false)
    }

    // MARK: - Full fetch state handling

    @Test
    @MainActor
    func `Authoritative empty full fetch clears cached snapshot and shows no data`() {
        let data = SyncedUsageData()
        data.snapshot = PreviewData.sampleSnapshot
        data.syncStatus = .synced(lastConfirmedSync: PreviewData.sampleSnapshot.syncTimestamp)

        data.applyFullFetchResults(
            perProvider: .empty,
            legacy: .empty,
            kvsFallback: nil)

        #expect(data.snapshot == nil)
        #expect(data.deviceSnapshots.isEmpty)
        #expect(data.syncStatus == .noData)
    }

    @Test
    @MainActor
    func `Full fetch error preserves cached snapshot and synced status`() {
        let data = SyncedUsageData()
        data.snapshot = PreviewData.sampleSnapshot
        data.syncStatus = .syncing

        data.applyFullFetchResults(
            perProvider: .error(.productionSchemaMissingQueryableIndex("recordName")),
            legacy: .error(.networkUnavailable),
            kvsFallback: nil)

        #expect(data.snapshot == PreviewData.sampleSnapshot)
        #expect(data.syncStatus == .synced(lastConfirmedSync: PreviewData.sampleSnapshot.syncTimestamp))
    }

    @Test
    @MainActor
    func `Cold full fetch production index error surfaces as error status`() {
        let data = SyncedUsageData()

        data.applyFullFetchResults(
            perProvider: .error(.productionSchemaMissingQueryableIndex("recordName")),
            legacy: .error(.networkUnavailable),
            kvsFallback: nil)

        #expect(data.snapshot == nil)
        if case let .error(message) = data.syncStatus {
            #expect(message.contains("recordName"))
        } else {
            Issue.record("Expected .error, got \(data.syncStatus)")
        }
    }

    // MARK: - Sync Freshness Formatting

    @Test
    func `Sync freshness formatter ticks seconds from confirmed sync`() {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(SyncFreshnessFormatter.ageText(
            since: syncedAt,
            now: syncedAt.addingTimeInterval(3.2)) == "3 sec ago")
        #expect(SyncFreshnessFormatter.ageText(
            since: syncedAt,
            now: syncedAt.addingTimeInterval(4.1)) == "4 sec ago")
    }

    @Test
    func `Sync freshness formatter handles minute hour and day thresholds`() {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(SyncFreshnessFormatter.ageText(
            since: syncedAt,
            now: syncedAt.addingTimeInterval(60)) == "1 min ago")
        #expect(SyncFreshnessFormatter.ageText(
            since: syncedAt,
            now: syncedAt.addingTimeInterval(3600)) == "1h ago")
        #expect(SyncFreshnessFormatter.ageText(
            since: syncedAt,
            now: syncedAt.addingTimeInterval(86400)) == "1d ago")
    }

    @Test
    func `Refreshing label preserves last confirmed sync age`() {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let now = syncedAt.addingTimeInterval(12)

        #expect(SyncFreshnessFormatter.refreshingText(
            lastConfirmedSync: syncedAt,
            now: now) == "Refreshing · last synced 12 sec ago")
    }

    @Test
    func `Refresh failed label preserves last confirmed sync age`() {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let now = syncedAt.addingTimeInterval(120)

        #expect(SyncFreshnessFormatter.refreshFailedText(
            lastConfirmedSync: syncedAt,
            now: now) == "Refresh failed · last synced 2 min ago")
    }

    @Test
    func `Sync freshness state uses injected now for stale resolution`() {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let status = SyncStatus.synced(lastConfirmedSync: syncedAt)

        let fresh = SyncFreshnessState.resolve(
            isDemoMode: false,
            snapshot: nil,
            syncStatus: status,
            now: syncedAt.addingTimeInterval(120))
        let stale = SyncFreshnessState.resolve(
            isDemoMode: false,
            snapshot: nil,
            syncStatus: status,
            now: syncedAt.addingTimeInterval(SyncFreshnessState.staleThreshold + 1))

        #expect(fresh?.isStale == false)
        #expect(stale?.isStale == true)
    }

    // MARK: - MultiDeviceSyncResult

    @Test
    func `MultiDeviceSyncResult.empty has no snapshots`() {
        let result = MultiDeviceSyncResult.empty
        if case .empty = result {
            // Expected
        } else {
            Issue.record("Expected .empty")
        }
    }

    @Test
    func `MultiDeviceSyncResult.error carries CloudSyncError`() {
        let result = MultiDeviceSyncResult.error(.networkUnavailable)
        if case let .error(error) = result {
            #expect(error.description == "Network unavailable")
        } else {
            Issue.record("Expected .error")
        }
    }

    // MARK: - SyncPushResult

    @Test
    func `SyncPushResult.success has no message`() {
        let result = SyncPushResult.success
        #expect(result.succeeded == true)
        #expect(result.message == nil)
    }

    @Test
    func `SyncPushResult.failure carries error message`() {
        let result = SyncPushResult.failure("Network unavailable")
        #expect(result.succeeded == false)
        #expect(result.message == "Network unavailable")
    }
}
