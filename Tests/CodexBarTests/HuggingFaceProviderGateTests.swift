import Foundation
import Testing
@testable import CodexBarCore

struct HuggingFaceProviderGateTests {
    @Test
    func `serializes fetches and cancels queued work`() async {
        let gate = HuggingFaceOperationGate()
        let owner = UUID()
        let cancelled = UUID()
        let next = UUID()

        #expect(await gate.acquire(id: owner))
        let cancelledTask = Task { await gate.acquire(id: cancelled) }
        while await gate.pendingCount == 0 {
            await Task.yield()
        }
        cancelledTask.cancel()
        #expect(await cancelledTask.value == false)
        #expect(await gate.pendingCount == 0)

        await gate.release(id: owner)
        #expect(await gate.acquire(id: next))
        await gate.release(id: next)
    }
}
