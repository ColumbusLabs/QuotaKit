import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

enum ProviderPluginCancellationTestSupport {
    static func checkCallerCancellation(
        engine: ProviderPluginEngineKind,
        optionalMethod: String) async throws
    {
        let (starts, started) = AsyncStream<String>.makeStream()
        let (cancellations, cancelled) = AsyncStream<String>.makeStream()
        defer {
            started.finish()
            cancelled.finish()
        }
        let optional = optionalMethod == "POST"
            ? "{url:'https://example.test/optional',method:'POST',body:{}}"
            : "'https://example.test/optional'"
        let runtime = try ProviderPluginRuntime(
            source: """
            defineProvider({
              id: 'cancellation-fixture',
              name: 'Cancellation fixture',
              endpoints: ['https://example.test'],
              settings: [],
              async fetchUsage(ctx) {
                await ctx.http.getWithOptional(
                  'https://example.test/primary',
                  \(optional),
                  {optionalBudgetSeconds: 5});
                return {empty: true};
              }
            });
            """,
            transport: ProviderHTTPTransportHandler { request in
                let path = request.url?.path ?? "missing"
                started.yield(path)
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    cancelled.yield(path)
                    throw error
                }
                return (Data("late".utf8), HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil)!)
            },
            allowsDynamicID: true,
            engine: engine)
        let task = Task { try await runtime.fetchUsage() }
        var startIterator = starts.makeAsyncIterator()
        let first = try #require(await startIterator.next())
        let second = try #require(await startIterator.next())
        #expect(Set([first, second]) == ["/primary", "/optional"])
        task.cancel()
        switch await BoundedTaskJoin(sourceTask: task).value(joinGrace: .seconds(10)) {
        case let .failure(error):
            #expect(error is CancellationError)
        case .value, .timedOut:
            Issue.record("Cancelled plugin fetch did not return CancellationError")
            return
        }
        var cancellationIterator = cancellations.makeAsyncIterator()
        let firstCancelled = try #require(await cancellationIterator.next())
        let secondCancelled = try #require(await cancellationIterator.next())
        #expect(Set([firstCancelled, secondCancelled]) == ["/primary", "/optional"])
    }
}
