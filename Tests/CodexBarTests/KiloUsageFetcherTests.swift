import Foundation
import Testing
@testable import CodexBarCore

@Suite
struct KiloUsageFetcherTests {
    @Test
    func batchURLUsesAuthenticatedTRPCBatchFormat() throws {
        let baseURL = try #require(URL(string: "https://kilo.example/trpc"))
        let url = try KiloUsageFetcher._buildBatchURLForTesting(baseURL: baseURL)

        #expect(url.path.contains("user.getCreditBlocks,kiloPass.getState,user.getAutoTopUpPaymentMethod"))

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let batch = components.queryItems?.first(where: { $0.name == "batch" })?.value
        let inputValue = components.queryItems?.first(where: { $0.name == "input" })?.value

        #expect(batch == "1")
        let requiredInput = try #require(inputValue)
        let inputData = Data(requiredInput.utf8)
        let inputObject = try #require(try JSONSerialization.jsonObject(with: inputData) as? [String: Any])
        let first = try #require(inputObject["0"] as? [String: Any])
        let second = try #require(inputObject["1"] as? [String: Any])
        let third = try #require(inputObject["2"] as? [String: Any])

        #expect(inputObject.keys.contains("0"))
        #expect(inputObject.keys.contains("1"))
        #expect(inputObject.keys.contains("2"))
        #expect(first["json"] is NSNull)
        #expect(second["json"] is NSNull)
        #expect(third["json"] is NSNull)
    }

    @Test
    func parseSnapshotMapsBusinessFieldsAndIdentity() throws {
        let json = """
        [
          {
            "result": {
              "data": {
                "json": {
                  "blocks": [
                    {
                      "usedCredits": 25,
                      "totalCredits": 100,
                      "remainingCredits": 75
                    }
                  ]
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "plan": {
                    "name": "Kilo Pass Pro"
                  }
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "enabled": true,
                  "paymentMethod": "visa"
                }
              }
            }
          }
        ]
        """

        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let snapshot = parsed.toUsageSnapshot()

        #expect(snapshot.primary?.usedPercent == 25)
        #expect(snapshot.identity?.providerID == .kilo)
        #expect(snapshot.loginMethod(for: .kilo)?.contains("Kilo Pass Pro") == true)
        #expect(snapshot.loginMethod(for: .kilo)?.contains("Auto top-up") == true)
    }

    @Test
    func parseSnapshotTreatsEmptyAndNullBusinessFieldsAsNoDataSuccess() throws {
        let json = """
        [
          {
            "result": {
              "data": {
                "json": {
                  "blocks": []
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "plan": {
                    "name": null
                  }
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "enabled": null,
                  "paymentMethod": null
                }
              }
            }
          }
        ]
        """

        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let snapshot = parsed.toUsageSnapshot()

        #expect(snapshot.primary == nil)
        #expect(snapshot.identity?.providerID == .kilo)
        #expect(snapshot.loginMethod(for: .kilo) == nil)
    }

    @Test
    func parseSnapshotKeepsSparseIndexedObjectRoutingByProcedureIndex() throws {
        let json = """
        {
          "0": {
            "result": {
              "data": {
                "json": {
                  "creditsUsed": 10,
                  "creditsRemaining": 90
                }
              }
            }
          },
          "2": {
            "result": {
              "data": {
                "json": {
                  "planName": "wrong-route",
                  "enabled": true,
                  "method": "visa"
                }
              }
            }
          }
        }
        """

        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let snapshot = parsed.toUsageSnapshot()

        #expect(snapshot.primary?.usedPercent == 10)
        #expect(snapshot.loginMethod(for: .kilo) == "Auto top-up: visa")
    }

    @Test
    func parseSnapshotUsesTopLevelCreditsUsedFallback() throws {
        let json = """
        [
          {
            "result": {
              "data": {
                "json": {
                  "creditsUsed": 40,
                  "creditsRemaining": 60
                }
              }
            }
          }
        ]
        """

        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let snapshot = parsed.toUsageSnapshot()

        #expect(snapshot.primary?.usedPercent == 40)
        #expect(snapshot.primary?.resetDescription == "Credits: 40/100")
    }

    @Test
    func parseSnapshotMapsUnauthorizedTRPCError() {
        let json = """
        [
          {
            "error": {
              "json": {
                "message": "Unauthorized",
                "data": {
                  "code": "UNAUTHORIZED"
                }
              }
            }
          }
        ]
        """

        #expect {
            _ = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        } throws: { error in
            guard let kiloError = error as? KiloUsageError else { return false }
            guard case .unauthorized = kiloError else { return false }
            return true
        }
    }

    @Test
    func parseSnapshotMapsInvalidJSONToParseError() {
        #expect {
            _ = try KiloUsageFetcher._parseSnapshotForTesting(Data("not-json".utf8))
        } throws: { error in
            guard let kiloError = error as? KiloUsageError else { return false }
            guard case .parseFailed = kiloError else { return false }
            return true
        }
    }

    @Test
    func statusErrorMappingCoversAuthAndServerFailures() {
        #expect(KiloUsageFetcher._statusErrorForTesting(401) == .unauthorized)
        #expect(KiloUsageFetcher._statusErrorForTesting(403) == .unauthorized)
        #expect(KiloUsageFetcher._statusErrorForTesting(404) == .endpointNotFound)

        guard let serviceError = KiloUsageFetcher._statusErrorForTesting(503) else {
            Issue.record("Expected service unavailable mapping")
            return
        }
        guard case let .serviceUnavailable(statusCode) = serviceError else {
            Issue.record("Expected service unavailable mapping")
            return
        }
        #expect(statusCode == 503)
    }

    @Test
    func fetchUsageWithoutCredentialsFailsFast() async {
        await #expect(throws: KiloUsageError.missingCredentials) {
            _ = try await KiloUsageFetcher.fetchUsage(apiKey: "  ", environment: [:])
        }
    }
}
