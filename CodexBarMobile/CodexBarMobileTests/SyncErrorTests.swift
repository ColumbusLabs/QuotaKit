import CloudKit
import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Sync Error Mapping Tests")
struct SyncErrorTests {
    // MARK: - CloudSyncError from CKError

    @Test("Network unavailable maps correctly")
    func networkUnavailable() {
        let ckError = CKError(.networkUnavailable)
        let syncError = CloudSyncError(from: ckError)
        #expect(syncError.description == "Network unavailable")
    }

    @Test("Network failure maps to networkUnavailable")
    func networkFailure() {
        let ckError = CKError(.networkFailure)
        let syncError = CloudSyncError(from: ckError)
        #expect(syncError.description == "Network unavailable")
    }

    @Test("Not authenticated maps correctly")
    func notAuthenticated() {
        let ckError = CKError(.notAuthenticated)
        let syncError = CloudSyncError(from: ckError)
        #expect(syncError.description == "iCloud account not signed in")
    }

    @Test("Quota exceeded maps correctly")
    func quotaExceeded() {
        let ckError = CKError(.quotaExceeded)
        let syncError = CloudSyncError(from: ckError)
        #expect(syncError.description == "iCloud storage quota exceeded")
    }

    @Test("Server response lost maps to server error")
    func serverResponseLost() {
        let ckError = CKError(.serverResponseLost)
        let syncError = CloudSyncError(from: ckError)
        if case .serverError = syncError {
            // Correct mapping
        } else {
            Issue.record("Expected .serverError, got \(syncError)")
        }
    }

    @Test("Unknown error includes description")
    func unknownError() {
        let ckError = CKError(.internalError)
        let syncError = CloudSyncError(from: ckError)
        if case .unknown(let msg) = syncError {
            #expect(!msg.isEmpty)
        } else {
            Issue.record("Expected .unknown, got \(syncError)")
        }
    }

    @Test("Queryable recordName error maps to Production index issue")
    func queryableRecordNameError() {
        let ckError = CKError(
            .invalidArguments,
            userInfo: [
                NSLocalizedDescriptionKey: "Field 'recordName' is not marked queryable",
            ])
        let syncError = CloudSyncError(from: ckError)

        if case .productionSchemaMissingQueryableIndex(let fieldName) = syncError {
            #expect(fieldName == "recordName")
        } else {
            Issue.record("Expected .productionSchemaMissingQueryableIndex, got \(syncError)")
        }
    }

    // MARK: - SyncStatus properties

    @Test("SyncStatus.error isError returns true")
    func statusErrorIsError() {
        let status = SyncStatus.error(message: "test")
        #expect(status.isError == true)
    }

    @Test("SyncStatus.noData isError returns true")
    func statusNoDataIsError() {
        let status = SyncStatus.noData
        #expect(status.isError == true)
    }

    @Test("SyncStatus.incompatibleData isError returns true")
    func statusIncompatibleIsError() {
        let status = SyncStatus.incompatibleData
        #expect(status.isError == true)
    }

    @Test("SyncStatus.synced isError returns false")
    func statusSyncedNotError() {
        let status = SyncStatus.synced(lastConfirmedSync: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(status.isError == false)
    }

    @Test("SyncStatus.syncing isError returns false")
    func statusSyncingNotError() {
        let status = SyncStatus.syncing
        #expect(status.isError == false)
    }

    // MARK: - Sync Freshness Formatting

    @Test("Sync freshness formatter ticks seconds from confirmed sync")
    func freshnessFormatterTicksSeconds() {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(SyncFreshnessFormatter.ageText(
            since: syncedAt,
            now: syncedAt.addingTimeInterval(3.2)) == "3 sec ago")
        #expect(SyncFreshnessFormatter.ageText(
            since: syncedAt,
            now: syncedAt.addingTimeInterval(4.1)) == "4 sec ago")
    }

    @Test("Sync freshness formatter handles minute hour and day thresholds")
    func freshnessFormatterThresholds() {
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

    @Test("Refreshing label preserves last confirmed sync age")
    func refreshingLabelPreservesLastConfirmedSyncAge() {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let now = syncedAt.addingTimeInterval(12)

        #expect(SyncFreshnessFormatter.refreshingText(
            lastConfirmedSync: syncedAt,
            now: now) == "Refreshing · last synced 12 sec ago")
    }

    @Test("Refresh failed label preserves last confirmed sync age")
    func refreshFailedLabelPreservesLastConfirmedSyncAge() {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let now = syncedAt.addingTimeInterval(120)

        #expect(SyncFreshnessFormatter.refreshFailedText(
            lastConfirmedSync: syncedAt,
            now: now) == "Refresh failed · last synced 2 min ago")
    }

    @Test("Sync freshness state uses injected now for stale resolution")
    func freshnessStateUsesInjectedNowForStaleResolution() {
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

    @Test("MultiDeviceSyncResult.empty has no snapshots")
    func emptyResult() {
        let result = MultiDeviceSyncResult.empty
        if case .empty = result {
            // Expected
        } else {
            Issue.record("Expected .empty")
        }
    }

    @Test("MultiDeviceSyncResult.error carries CloudSyncError")
    func errorResult() {
        let result = MultiDeviceSyncResult.error(.networkUnavailable)
        if case .error(let error) = result {
            #expect(error.description == "Network unavailable")
        } else {
            Issue.record("Expected .error")
        }
    }

    // MARK: - SyncPushResult

    @Test("SyncPushResult.success has no message")
    func pushSuccess() {
        let result = SyncPushResult.success
        #expect(result.succeeded == true)
        #expect(result.message == nil)
    }

    @Test("SyncPushResult.failure carries error message")
    func pushFailure() {
        let result = SyncPushResult.failure("Network unavailable")
        #expect(result.succeeded == false)
        #expect(result.message == "Network unavailable")
    }
}
