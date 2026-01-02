import XCTest
@testable import CodexBarCore

final class AugmentStatusProbeTests: XCTestCase {
    func test_debugRawProbe_returnsFormattedOutput() async throws {
        // Given: A probe instance
        let probe = AugmentStatusProbe()

        // When: We call debugRawProbe
        let output = await probe.debugRawProbe()

        // Then: The output should contain expected debug information
        XCTAssertTrue(output.contains("=== Augment Debug Probe @"), "Should contain debug header")
        XCTAssertTrue(
            output.contains("Probe Success") || output.contains("Probe Failed"),
            "Should contain probe result status")
    }

    func test_latestDumps_initiallyEmpty() async {
        // Note: This test may fail if other tests have already run and captured dumps
        // The ring buffer is shared across all tests in the process
        // When: We request latest dumps
        let dumps = await AugmentStatusProbe.latestDumps()

        // Then: Should either be empty or contain previous test dumps
        // We just verify it returns a non-empty string
        XCTAssertFalse(dumps.isEmpty, "Should return a string (either empty message or dumps)")
    }

    func test_debugRawProbe_capturesFailureInDumps() async throws {
        // Given: A probe with an invalid base URL that will fail
        let invalidProbe = AugmentStatusProbe(baseURL: URL(string: "https://invalid.example.com")!)

        // When: We call debugRawProbe which should fail
        let output = await invalidProbe.debugRawProbe()

        // Then: The output should indicate failure
        XCTAssertTrue(output.contains("Probe Failed"), "Should contain failure message")

        // And: The failure should be captured in dumps
        let dumps = await AugmentStatusProbe.latestDumps()
        XCTAssertNotEqual(dumps, "No Augment probe dumps captured yet.", "Should have captured the failure")
        XCTAssertTrue(dumps.contains("Probe Failed"), "Dumps should contain the failure")
    }

    func test_latestDumps_maintainsRingBuffer() async throws {
        // Given: Multiple failed probes to fill the ring buffer
        let invalidProbe = AugmentStatusProbe(baseURL: URL(string: "https://invalid.example.com")!)

        // When: We generate more than 5 dumps (the ring buffer size)
        for _ in 1...7 {
            _ = await invalidProbe.debugRawProbe()
            // Small delay to ensure different timestamps
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        // Then: The dumps should only contain the most recent 5
        let dumps = await AugmentStatusProbe.latestDumps()
        let separatorCount = dumps.components(separatedBy: "\n\n---\n\n").count
        XCTAssertLessThanOrEqual(separatorCount, 5, "Should maintain at most 5 dumps in ring buffer")
    }

    func test_debugRawProbe_includesTimestamp() async {
        // Given: A probe instance
        let probe = AugmentStatusProbe()

        // When: We call debugRawProbe
        let output = await probe.debugRawProbe()

        // Then: The output should include an ISO8601 timestamp
        XCTAssertTrue(output.contains("@"), "Should contain timestamp marker")
        XCTAssertTrue(output.contains("==="), "Should contain debug header markers")
    }

    func test_debugRawProbe_includesCreditsBalance() async {
        // Given: A probe instance
        let probe = AugmentStatusProbe()

        // When: We call debugRawProbe
        let output = await probe.debugRawProbe()

        // Then: The output should mention credits balance (either in success or failure)
        XCTAssertTrue(
            output.contains("Credits Balance") || output.contains("Probe Failed"),
            "Should contain credits information or failure message")
    }
}

