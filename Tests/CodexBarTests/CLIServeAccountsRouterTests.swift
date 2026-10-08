import Foundation
import Testing
@testable import CodexBarCLI

struct CLIServeAccountsRouterTests {
    @Test
    func `routes account list and opaque id lookup`() throws {
        let id = "token-account:claude:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

        #expect(try CLIServeRouter.route(method: "GET", path: "/accounts", queryItems: [:]) == .accounts(id: nil))
        #expect(try CLIServeRouter.route(method: "GET", path: "/accounts/\(id)", queryItems: [:]) == .accounts(id: id))
    }

    @Test
    func `account lookup rejects empty and nested ids`() {
        for path in ["/accounts/", "/accounts/one/two"] {
            do {
                _ = try CLIServeRouter.route(method: "GET", path: path, queryItems: [:])
                Issue.record("Expected notFound for \(path)")
            } catch let error as CLIServeRouteError {
                #expect(error == .notFound)
            } catch {
                Issue.record("Unexpected error for \(path): \(error)")
            }
        }
    }
}
