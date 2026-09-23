import Foundation
import Testing
@testable import CodexBarCore

struct ProviderPluginCurrencyTests {
    @Test(arguments: [ProviderPluginEngineKind.javaScriptCore, .quickJS])
    func `currency formatting matches native usage formatting across engines`(
        engine: ProviderPluginEngineKind) async throws
    {
        for code in ["USD", "CNY", "EUR", "JPY", "KWD"] {
            for amount in [49.585, 49.595, -0.0, 0.0, 1e-7, -49.585, 1234.5] {
                let runtime = try ProviderPluginRuntime(source: """
                defineProvider({
                  id: "synthetic",
                  name: "Currency Fixture",
                  endpoints: ["https://api.synthetic.test"],
                  settings: [],
                  async fetchUsage(ctx) {
                    return {
                      primary: { usedPercent: 1 },
                      identity: { loginMethod: ctx.format.currency(\(amount), '\(code)') },
                    };
                  },
                });
                """, engine: engine)

                let usage = try await runtime.fetchUsage()
                #expect(usage.identity?.loginMethod == UsageFormatter.currencyString(amount, currencyCode: code))
            }
        }
    }
}
