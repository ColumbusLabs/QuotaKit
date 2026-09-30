import Foundation
import Testing
@testable import CodexBarCore

extension ProcessEnvironment: CustomTestStringConvertible {
    public var testDescription: String {
        self.description
    }
}

struct ProcessEnvironmentTests {
    private static let sentinel = "sentinel-environment-value-must-not-be-rendered"
    private static let sentinelKey = "CODEXBAR_TEST_SENTINEL_SECRET"

    @Test
    func `wrapper preserves dictionary access and reports only its current count`() {
        let input = [Self.sentinelKey: Self.sentinel, "ORDINARY_NAME": "second-value"]
        var environment = ProcessEnvironment(wrappedValue: input)

        #expect(environment.wrappedValue == input)
        #expect(environment.wrappedValue[Self.sentinelKey] == Self.sentinel)
        #expect(environment.description == "ProcessEnvironment(2 entries; redacted)")
        #expect(environment.debugDescription == environment.description)
        #expect(String(describingForTest: environment) == environment.description)
        Self.expectRedacted(String(describing: environment))
        Self.expectRedacted(String(reflecting: environment))
        Self.expectRedacted(Self.dumped(environment))

        let children = Array(Mirror(reflecting: environment).children)
        #expect(children.count == 1)
        #expect(children.first?.label == "entryCount")
        #expect(children.first?.value as? Int == 2)

        environment.wrappedValue["THIRD_NAME"] = "third-value"
        #expect(environment.wrappedValue.count == 3)
        #expect(environment.description == "ProcessEnvironment(3 entries; redacted)")
        Self.expectRedacted(Self.dumped(environment))
    }

    @Test
    func `optional environments preserve absence equality mutation and round trips`() {
        var absent = OptionalConfiguration()
        let empty = OptionalConfiguration(environment: [:])
        #expect(absent.environment == nil)
        #expect(absent != empty)
        #expect(absent == OptionalConfiguration())

        absent.environment = [Self.sentinelKey: Self.sentinel]
        #expect(absent.environment == [Self.sentinelKey: Self.sentinel])
        #expect(absent == OptionalConfiguration(environment: [Self.sentinelKey: Self.sentinel]))

        var copy = absent
        copy.environment?["ORDINARY_NAME"] = "another-value"
        #expect(copy != absent)
        #expect(absent.environment?.count == 1)
        #expect(copy.environment?.count == 2)
        #expect(String(describing: copy) == String(describing: OptionalConfiguration(
            environment: ["different": "contents", "other": "values"])))
        Self.expectRedacted(String(describing: copy))
        Self.expectRedacted(String(reflecting: copy))
        Self.expectRedacted(Self.dumped(copy))

        absent.environment = nil
        #expect(absent == OptionalConfiguration())
        Self.expectRedacted(String(describing: absent))
    }

    @Test
    func `retained fetcher environments stay redacted in descriptions and mirrors`() {
        let environment = [Self.sentinelKey: Self.sentinel, "ORDINARY_NAME": "another-value"]
        let fetcher = UsageFetcher(environment: environment)
        let browserDetection = BrowserDetection(homeDirectory: "/synthetic-home")
        let claudeFetcher = ClaudeUsageFetcher(browserDetection: browserDetection, environment: environment)
        let context = ProviderFetchContext(
            runtime: .cli,
            sourceMode: .auto,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: nil,
            fetcher: fetcher,
            claudeFetcher: claudeFetcher,
            browserDetection: browserDetection)

        let values: [Any] = [fetcher, claudeFetcher, context, CodexStatusProbe(environment: environment)]
        for value in values {
            Self.expectRedacted(String(describing: value))
            Self.expectRedacted(String(reflecting: value))
            Self.expectRedacted(String(describingForTest: value))
            Self.expectRedacted(Self.dumped(value))
            Self.expectMirrorRedacted(value)
        }
    }

    @Test
    func `failed expectations do not render captured environment contents`() {
        let value = UsageFetcher(environment: [Self.sentinelKey: Self.sentinel])
        let captured = CapturedValue(value: value)
        let other = CapturedValue(value: nil)

        withKnownIssue("Deliberate failure exercises Swift Testing operand expansion") {
            #expect(captured == other)
        } matching: { issue in
            var rendered = ""
            dump(issue, to: &rendered)
            return !rendered.contains(Self.sentinel) && !rendered.contains(Self.sentinelKey)
        }
    }

    private struct OptionalConfiguration: Equatable {
        @ProcessEnvironment var environment: [String: String]?
    }

    private struct CapturedValue: Equatable {
        let value: Any?

        static func == (_: Self, _: Self) -> Bool { false }
    }

    private static func expectRedacted(_ output: String) {
        #expect(!output.contains(self.sentinel))
        #expect(!output.contains(self.sentinelKey))
        #expect(!output.contains("ORDINARY_NAME"))
        #expect(!output.contains("THIRD_NAME"))
    }

    private static func expectMirrorRedacted(_ value: Any, depth: Int = 0) {
        guard depth < 20 else { return }
        for child in Mirror(reflecting: value).children {
            self.expectRedacted(String(describing: child.value))
            self.expectMirrorRedacted(child.value, depth: depth + 1)
        }
    }

    private static func dumped(_ value: Any) -> String {
        var output = ""
        dump(value, to: &output)
        return output
    }
}
