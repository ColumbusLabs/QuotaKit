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
        let status = SyncStatus.synced(ago: 60)
        #expect(status.isError == false)
    }

    @Test("SyncStatus.syncing isError returns false")
    func statusSyncingNotError() {
        let status = SyncStatus.syncing
        #expect(status.isError == false)
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
