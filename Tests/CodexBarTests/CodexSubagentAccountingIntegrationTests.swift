import Foundation
import Testing
@testable import CodexBarCore
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

struct CodexSubagentAccountingIntegrationTests {
    private typealias Usage = (input: Int, cached: Int, output: Int)

    @Test
    func `copied parent prefix keeps the inherited baseline after late lineage metadata`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 16)
        let forkTimestamp = env.isoString(for: day)
        let parentModel = "openai/gpt-5.3"
        let leafModel = "openai/gpt-5.4"
        let fileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-\(forkTimestamp)-child-session.jsonl",
            contents: env.jsonl([
                [
                    "type": "session_meta",
                    "timestamp": forkTimestamp,
                    "payload": [
                        "id": "child-session",
                        "timestamp": forkTimestamp,
                        "source": [
                            "subagent": [
                                "thread_spawn": ["parent_thread_id": "parent-session"],
                            ],
                        ],
                    ],
                ],
                self.turnContext(timestamp: forkTimestamp, model: parentModel),
                self.tokenCount(
                    timestamp: env.isoString(for: day.addingTimeInterval(1)),
                    model: parentModel,
                    total: (input: 1000, cached: 900, output: 100),
                    last: (input: 50, cached: 10, output: 5)),
                [
                    "type": "session_meta",
                    "timestamp": forkTimestamp,
                    "payload": [
                        "id": "child-session",
                        "forked_from_id": "parent-session",
                        "timestamp": forkTimestamp,
                    ],
                ],
                [
                    "type": "session_meta",
                    "timestamp": forkTimestamp,
                    "payload": [
                        "id": "parent-session",
                        "timestamp": forkTimestamp,
                    ],
                ],
                self.turnContext(timestamp: forkTimestamp, model: leafModel),
                self.tokenCount(
                    timestamp: env.isoString(for: day.addingTimeInterval(2)),
                    model: leafModel,
                    total: (input: 1050, cached: 910, output: 105),
                    last: (input: 50, cached: 10, output: 5)),
            ]))

        var resolvedParentBaseline = false
        let parsed = CostUsageScanner.parseCodexFile(
            fileURL: fileURL,
            range: CostUsageScanner.CostUsageDayRange(since: day, until: day),
            inheritedTotalsResolver: { parentSessionID, _ in
                resolvedParentBaseline = true
                #expect(parentSessionID == "parent-session")
                return .resolved(.init(input: 1000, cached: 900, output: 100))
            })

        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        let normalizedLeafModel = CostUsagePricing.normalizeCodexModel(leafModel)
        #expect(parsed.days[dayKey]?[normalizedLeafModel] == [50, 10, 5])
        #expect(parsed.days[dayKey]?[CostUsagePricing.normalizeCodexModel(parentModel)] == nil)
        #expect(resolvedParentBaseline)
        #expect(parsed.dependsOnParentTotals)
    }

    @Test
    func `local marker owns only its suffix and persists lineage-only cache mode`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 16)
        let forkTimestamp = env.isoString(for: day)
        let parentModel = "openai/gpt-5.3"
        let leafModel = "openai/gpt-5.4"
        let fastContents = try env.jsonl([
            [
                "type": "session_meta",
                "timestamp": forkTimestamp,
                "payload": [
                    "id": "marker-child",
                    "timestamp": forkTimestamp,
                    "source": [
                        "subagent": [
                            "thread_spawn": ["parent_thread_id": "parent-session"],
                        ],
                    ],
                ],
            ],
            self.turnContext(timestamp: forkTimestamp, model: parentModel),
            self.tokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(1)),
                model: parentModel,
                total: (input: 1000, cached: 900, output: 100),
                last: (input: 50, cached: 10, output: 5)),
            [
                "type": "session_meta",
                "timestamp": forkTimestamp,
                "payload": [
                    "id": "marker-child",
                    "forked_from_id": "parent-session",
                    "timestamp": forkTimestamp,
                ],
            ],
            [
                "type": "session_meta",
                "timestamp": forkTimestamp,
                "payload": ["id": "ancestor-session"],
            ],
            self.turnContext(timestamp: env.isoString(for: day.addingTimeInterval(2)), model: leafModel),
            [
                "type": "inter_agent_communication_metadata",
                "timestamp": env.isoString(for: day.addingTimeInterval(2)),
                "payload": ["trigger_turn": true],
            ],
            self.tokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(2.5)),
                model: parentModel,
                total: (input: 1000, cached: 900, output: 100),
                last: (input: 50, cached: 10, output: 5)),
            self.tokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(3)),
                model: leafModel,
                total: (input: 1050, cached: 910, output: 105),
                last: (input: 50, cached: 10, output: 5)),
        ])
        let fastFileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-\(forkTimestamp)-marker-child.jsonl",
            contents: fastContents)
        let fallbackFileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-\(forkTimestamp)-marker-child-fallback.jsonl",
            contents: fastContents
                .replacingOccurrences(of: "marker-child", with: "marker-child-fallback")
                .replacingOccurrences(
                    of: "\"type\":\"session_meta\"",
                    with: "\"ty\\u0070e\":\"session_meta\"")
                .replacingOccurrences(
                    of: "\"type\":\"turn_context\"",
                    with: "\"ty\\u0070e\":\"turn_context\"")
                .replacingOccurrences(
                    of: "\"type\":\"inter_agent_communication_metadata\"",
                    with: "\"ty\\u0070e\":\"inter_agent_communication_metadata\""))
        let escapedTimestampFileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-\(forkTimestamp)-marker-child-escaped-timestamp.jsonl",
            contents: fastContents
                .replacingOccurrences(of: "marker-child", with: "marker-child-escaped-timestamp")
                .replacingOccurrences(of: "\"timestamp\":", with: "\"time\\u0073tamp\":"))

        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        let normalizedLeafModel = CostUsagePricing.normalizeCodexModel(leafModel)
        for fileURL in [fastFileURL, fallbackFileURL, escapedTimestampFileURL] {
            var resolvedParentBaseline = false
            let parsed = CostUsageScanner.parseCodexFile(
                fileURL: fileURL,
                range: CostUsageScanner.CostUsageDayRange(since: day, until: day),
                inheritedTotalsResolver: { _, _ in
                    resolvedParentBaseline = true
                    return .resolved(.init(input: 10, cached: 0, output: 0))
                })
            #expect(parsed.days[dayKey]?[normalizedLeafModel] == [50, 10, 5])
            #expect(parsed.days[dayKey]?[CostUsagePricing.normalizeCodexModel(parentModel)] == nil)
            #expect(!parsed.dependsOnParentTotals)
            #expect(!resolvedParentBaseline)
        }

        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot)
        options.refreshMinIntervalSeconds = 0
        let report = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)
        #expect(report.data.first?.totalTokens == 165)

        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let childUsages = cache.files.values.filter { $0.sessionId?.hasPrefix("marker-child") == true }
        #expect(childUsages.count == 3)
        #expect(childUsages.allSatisfy {
            $0.forkBaselineDependencyKey == CostUsageScanner.codexForkDependencyNotRequiredKey
        })
        let sessions = CostUsageScanner.buildCodexSessionBreakdownsFromCache(
            cache: cache,
            range: CostUsageScanner.CostUsageDayRange(since: day, until: day))
        #expect(sessions.count == 3)
        #expect(sessions.allSatisfy { $0.totalTokens == 55 })
    }

    @Test
    func `copied prefix infers its parent and ignores a spoofed trigger outside the payload`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 16)
        let forkTimestamp = env.isoString(for: day)
        let fileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-\(forkTimestamp)-inferred-parent.jsonl",
            contents: env.jsonl([
                [
                    "type": "session_meta",
                    "timestamp": forkTimestamp,
                    "payload": [
                        "id": "inferred-child",
                        "timestamp": forkTimestamp,
                        "source": ["subagent": ["thread_spawn": [:]]],
                    ],
                ],
                self.tokenCount(
                    timestamp: env.isoString(for: day.addingTimeInterval(1)),
                    model: "openai/gpt-5.3",
                    total: (input: 1000, cached: 900, output: 100),
                    last: (input: 50, cached: 10, output: 5)),
                [
                    "type": "session_meta",
                    "timestamp": forkTimestamp,
                    "payload": ["id": "inferred-parent"],
                ],
                self.turnContext(
                    timestamp: env.isoString(for: day.addingTimeInterval(2)),
                    model: "openai/gpt-5.4"),
                [
                    "type": "inter_agent_communication_metadata",
                    "timestamp": env.isoString(for: day.addingTimeInterval(2)),
                    "trigger_turn": true,
                    "payload": ["trigger_turn": false],
                ],
                self.tokenCount(
                    timestamp: env.isoString(for: day.addingTimeInterval(3)),
                    model: "openai/gpt-5.4",
                    total: (input: 1050, cached: 910, output: 105),
                    last: (input: 50, cached: 10, output: 5)),
            ]))

        var resolvedParentBaseline = false
        let parsed = CostUsageScanner.parseCodexFile(
            fileURL: fileURL,
            range: CostUsageScanner.CostUsageDayRange(since: day, until: day),
            inheritedTotalsResolver: { parentSessionID, _ in
                resolvedParentBaseline = true
                #expect(parentSessionID == "inferred-parent")
                return .resolved(.init(input: 1000, cached: 900, output: 100))
            })

        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        let model = CostUsagePricing.normalizeCodexModel("openai/gpt-5.4")
        #expect(parsed.days[dayKey]?[model] == [50, 10, 5])
        #expect(parsed.forkedFromId == "inferred-parent")
        #expect(parsed.dependsOnParentTotals)
        #expect(resolvedParentBaseline)
    }

    @Test
    func `oversized ancestor metadata remains conservative copied-prefix evidence`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 16)
        let timestamp = env.isoString(for: day)
        let opening = try env.jsonl([
            [
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": [
                    "id": "oversized-child",
                    "source": ["subagent": ["thread_spawn": [:]]],
                ],
            ],
            self.tokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(1)),
                model: "openai/gpt-5.3",
                total: (input: 1000, cached: 900, output: 100),
                last: (input: 50, cached: 10, output: 5)),
        ])
        let oversizedAncestor = "{\"type\":\"session_meta\",\"timestamp\":\"\(timestamp)\"," +
            "\"payload\":{\"id\":\"oversized-parent\",\"padding\":\"" +
            String(repeating: "x", count: 300_000) + "\"}}\n"
        let tail = try env.jsonl([
            self.tokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(2)),
                model: "openai/gpt-5.4",
                total: (input: 1050, cached: 910, output: 105),
                last: (input: 50, cached: 10, output: 5)),
        ])
        let fileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-\(timestamp)-oversized-ancestor.jsonl",
            contents: opening + oversizedAncestor + tail)

        var resolvedParentBaseline = false
        let parsed = CostUsageScanner.parseCodexFile(
            fileURL: fileURL,
            range: CostUsageScanner.CostUsageDayRange(since: day, until: day),
            inheritedTotalsResolver: { parentSessionID, _ in
                resolvedParentBaseline = true
                #expect(parentSessionID == "oversized-parent")
                return .resolved(.init(input: 1000, cached: 900, output: 100))
            })

        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        let model = CostUsagePricing.normalizeCodexModel("openai/gpt-5.4")
        #expect(parsed.days[dayKey]?[model] == [50, 10, 5])
        #expect(parsed.forkedFromId == "oversized-parent")
        #expect(parsed.dependsOnParentTotals)
        #expect(resolvedParentBaseline)
    }

    @Test
    func `invalid timestamp suffix markers preserve parent dependency on both parser paths`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 16)
        let timestamp = env.isoString(for: day)
        let contents = try env.jsonl([
            [
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": [
                    "id": "invalid-marker-child",
                    "source": ["subagent": ["thread_spawn": [:]]],
                ],
            ],
            self.tokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(1)),
                model: "openai/gpt-5.3",
                total: (input: 1000, cached: 900, output: 100),
                last: (input: 50, cached: 10, output: 5)),
            [
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": ["id": "invalid-marker-parent"],
            ],
            [
                "type": "turn_context",
                "payload": ["model": "openai/gpt-5.4"],
            ],
            [
                "type": "inter_agent_communication_metadata",
                "payload": ["trigger_turn": true],
            ],
            self.tokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(2)),
                model: "openai/gpt-5.4",
                total: (input: 1050, cached: 910, output: 105),
                last: (input: 50, cached: 10, output: 5)),
        ])
        let fastFileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-\(timestamp)-invalid-marker.jsonl",
            contents: contents)
        let fallbackFileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-\(timestamp)-invalid-marker-fallback.jsonl",
            contents: contents
                .replacingOccurrences(of: "invalid-marker-child", with: "invalid-marker-child-fallback")
                .replacingOccurrences(of: "\"type\":\"turn_context\"", with: "\"ty\\u0070e\":\"turn_context\"")
                .replacingOccurrences(
                    of: "\"type\":\"inter_agent_communication_metadata\"",
                    with: "\"ty\\u0070e\":\"inter_agent_communication_metadata\""))

        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        let model = CostUsagePricing.normalizeCodexModel("openai/gpt-5.4")
        for fileURL in [fastFileURL, fallbackFileURL] {
            var resolvedParentBaseline = false
            let parsed = CostUsageScanner.parseCodexFile(
                fileURL: fileURL,
                range: CostUsageScanner.CostUsageDayRange(since: day, until: day),
                inheritedTotalsResolver: { parentSessionID, _ in
                    resolvedParentBaseline = true
                    #expect(parentSessionID == "invalid-marker-parent")
                    return .resolved(.init(input: 1000, cached: 900, output: 100))
                })
            #expect(parsed.days[dayKey]?[model] == [50, 10, 5])
            #expect(parsed.dependsOnParentTotals)
            #expect(resolvedParentBaseline)
        }
    }

    @Test
    func `oversized invalid suffix markers preserve parent dependency`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 16)
        let timestamp = env.isoString(for: day)
        let opening = try env.jsonl([
            [
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": [
                    "id": "oversized-marker-child",
                    "source": ["subagent": ["thread_spawn": [:]]],
                ],
            ],
            self.tokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(1)),
                model: "openai/gpt-5.3",
                total: (input: 1000, cached: 900, output: 100),
                last: (input: 50, cached: 10, output: 5)),
            [
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": ["id": "oversized-marker-parent"],
            ],
        ])
        let padding = String(repeating: "x", count: 300_000)
        let invalidTimestamp = "{\"type\":\"turn_context\",\"timestamp\":\"invalid\"," +
            "\"payload\":{\"model\":\"openai/gpt-5.4\",\"padding\":\"\(padding)\"}}\n"
        let nestedType = "{\"type\":\"event_msg\",\"timestamp\":\"\(timestamp)\"," +
            "\"payload\":{\"type\":\"turn_context\",\"padding\":\"\(padding)\"}}\n"
        let tail = try env.jsonl([
            [
                "type": "inter_agent_communication_metadata",
                "timestamp": env.isoString(for: day.addingTimeInterval(2)),
                "payload": ["trigger_turn": true],
            ],
            self.tokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(3)),
                model: "openai/gpt-5.4",
                total: (input: 1050, cached: 910, output: 105),
                last: (input: 50, cached: 10, output: 5)),
        ])

        let files = try [invalidTimestamp, nestedType].enumerated().map { index, marker in
            try env.writeCodexSessionFile(
                day: day,
                filename: "rollout-\(timestamp)-oversized-invalid-marker-\(index).jsonl",
                contents: opening + marker + tail)
        }
        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        let model = CostUsagePricing.normalizeCodexModel("openai/gpt-5.4")
        for fileURL in files {
            var resolvedParentBaseline = false
            let parsed = CostUsageScanner.parseCodexFile(
                fileURL: fileURL,
                range: CostUsageScanner.CostUsageDayRange(since: day, until: day),
                inheritedTotalsResolver: { parentSessionID, _ in
                    resolvedParentBaseline = true
                    #expect(parentSessionID == "oversized-marker-parent")
                    return .resolved(.init(input: 1000, cached: 900, output: 100))
                })
            #expect(parsed.days[dayKey]?[model] == [50, 10, 5])
            #expect(parsed.dependsOnParentTotals)
            #expect(resolvedParentBaseline)
        }
    }

    @Test
    func `idless copied prefix without a parent or local marker is suppressed`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 16)
        let timestamp = env.isoString(for: day)
        let fileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-\(timestamp)-ambiguous-prefix.jsonl",
            contents: env.jsonl([
                [
                    "type": "session_meta",
                    "timestamp": timestamp,
                    "payload": [
                        "id": "ambiguous-child",
                        "source": ["subagent": ["thread_spawn": [:]]],
                    ],
                ],
                self.tokenCount(
                    timestamp: env.isoString(for: day.addingTimeInterval(1)),
                    model: "openai/gpt-5.3",
                    total: (input: 1000, cached: 900, output: 100)),
                ["type": "session_meta", "timestamp": timestamp, "payload": [:]],
                self.tokenCount(
                    timestamp: env.isoString(for: day.addingTimeInterval(2)),
                    model: "openai/gpt-5.4",
                    total: (input: 1050, cached: 910, output: 105)),
            ]))

        let parsed = CostUsageScanner.parseCodexFile(
            fileURL: fileURL,
            range: CostUsageScanner.CostUsageDayRange(since: day, until: day))

        #expect(parsed.days.isEmpty)
        #expect(parsed.rows.isEmpty)
    }

    @Test
    func `protocol ordinal isolates the child suffix without resolving its parent`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 16)
        let timestamp = env.isoString(for: day)
        let parentModel = "openai/gpt-5.3"
        let leafModel = "openai/gpt-5.4"
        var sessionMetadata: [String: Any] = [
            "type": "session_meta",
            "timestamp": timestamp,
            "payload": [
                "id": "ordinal-child",
                "forked_from_id": "ordinal-parent",
                "timestamp": timestamp,
                "subagent_history_start_ordinal": 10,
                "source": [
                    "subagent": [
                        "thread_spawn": ["parent_thread_id": "ordinal-parent"],
                    ],
                ],
            ],
        ]
        sessionMetadata["ordinal"] = 0
        var copiedTotal = self.tokenCount(
            timestamp: env.isoString(for: day.addingTimeInterval(1)),
            model: parentModel,
            total: (input: 1000, cached: 900, output: 100),
            last: (input: 50, cached: 10, output: 5))
        copiedTotal["ordinal"] = 9
        var ownedContext = self.turnContext(
            timestamp: env.isoString(for: day.addingTimeInterval(2)),
            model: leafModel)
        ownedContext["ordinal"] = 10
        var ownedTotal = self.tokenCount(
            timestamp: env.isoString(for: day.addingTimeInterval(3)),
            model: leafModel,
            total: (input: 1050, cached: 910, output: 105),
            last: (input: 50, cached: 10, output: 5))
        ownedTotal["ordinal"] = 11
        let fileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-\(timestamp)-ordinal-child.jsonl",
            contents: env.jsonl([sessionMetadata, copiedTotal, ownedContext, ownedTotal]))

        var resolvedParentBaseline = false
        let parsed = CostUsageScanner.parseCodexFile(
            fileURL: fileURL,
            range: CostUsageScanner.CostUsageDayRange(since: day, until: day),
            inheritedTotalsResolver: { _, _ in
                resolvedParentBaseline = true
                return .resolved(.init(input: 1, cached: 1, output: 1))
            })

        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        let normalizedLeafModel = CostUsagePricing.normalizeCodexModel(leafModel)
        #expect(parsed.days[dayKey]?[normalizedLeafModel] == [50, 10, 5])
        #expect(parsed.days[dayKey]?[CostUsagePricing.normalizeCodexModel(parentModel)] == nil)
        #expect(!parsed.dependsOnParentTotals)
        #expect(!resolvedParentBaseline)
    }

    @Test
    func `legacy child proves its inherited baseline from first owned total minus last`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 16)
        let timestamp = env.isoString(for: day)
        let parentModel = "openai/gpt-5.3"
        let leafModel = "openai/gpt-5.4"
        let fileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-\(timestamp)-legacy-self-confirmed.jsonl",
            contents: env.jsonl([
                [
                    "type": "session_meta",
                    "timestamp": timestamp,
                    "payload": [
                        "id": "legacy-self-confirmed",
                        "forked_from_id": "legacy-parent",
                        "timestamp": timestamp,
                        "source": [
                            "subagent": [
                                "thread_spawn": ["parent_thread_id": "legacy-parent"],
                            ],
                        ],
                    ],
                ],
                self.tokenCount(
                    timestamp: env.isoString(for: day.addingTimeInterval(1)),
                    model: parentModel,
                    total: (input: 1000, cached: 900, output: 100)),
                self.turnContext(
                    timestamp: env.isoString(for: day.addingTimeInterval(2)),
                    model: leafModel),
                [
                    "type": "inter_agent_communication_metadata",
                    "timestamp": env.isoString(for: day.addingTimeInterval(2)),
                    "payload": ["trigger_turn": true],
                ],
                self.tokenCount(
                    timestamp: env.isoString(for: day.addingTimeInterval(3)),
                    model: leafModel,
                    total: (input: 1050, cached: 910, output: 105),
                    last: (input: 50, cached: 10, output: 5)),
                self.tokenCount(
                    timestamp: env.isoString(for: day.addingTimeInterval(4)),
                    model: leafModel,
                    total: (input: 1070, cached: 915, output: 110),
                    last: (input: 20, cached: 5, output: 5)),
            ]))

        var resolvedParentBaseline = false
        let parsed = CostUsageScanner.parseCodexFile(
            fileURL: fileURL,
            range: CostUsageScanner.CostUsageDayRange(since: day, until: day),
            inheritedTotalsResolver: { _, _ in
                resolvedParentBaseline = true
                return .unresolved
            })

        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        let normalizedLeafModel = CostUsagePricing.normalizeCodexModel(leafModel)
        #expect(parsed.days[dayKey]?[normalizedLeafModel] == [70, 15, 10])
        #expect(parsed.days[dayKey]?[CostUsagePricing.normalizeCodexModel(parentModel)] == nil)
        #expect(!parsed.dependsOnParentTotals)
        #expect(!resolvedParentBaseline)
    }

    @Test
    func `bounded append fallback reclassifies the complete subagent rollout`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 16)
        let timestamp = env.isoString(for: day)
        let filename = "rollout-\(timestamp)-growing-subagent.jsonl"
        let fileURL = try env.writeCodexSessionFile(
            day: day,
            filename: filename,
            contents: env.jsonl([
                [
                    "type": "session_meta",
                    "timestamp": timestamp,
                    "payload": [
                        "id": "growing-child",
                        "source": ["subagent": ["thread_spawn": [:]]],
                    ],
                ],
                self.turnContext(timestamp: timestamp, model: "openai/gpt-5.3"),
                self.tokenCount(
                    timestamp: env.isoString(for: day.addingTimeInterval(1)),
                    model: "openai/gpt-5.3",
                    total: (input: 1000, cached: 900, output: 100)),
            ]))

        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            maxCodexSessionFileBytes: 4096,
            maxCodexScanBytesPerRefresh: 4096)
        options.refreshMinIntervalSeconds = 0
        let first = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)
        #expect(first.data.first?.totalTokens == 1100)

        let appended = try env.jsonl([
            ["type": "session_meta", "timestamp": timestamp, "payload": ["id": "growing-parent"]],
            self.turnContext(
                timestamp: env.isoString(for: day.addingTimeInterval(2)),
                model: "openai/gpt-5.4"),
            [
                "type": "inter_agent_communication_metadata",
                "timestamp": env.isoString(for: day.addingTimeInterval(2)),
                "payload": ["trigger_turn": true],
            ],
            self.tokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(3)),
                model: "openai/gpt-5.4",
                total: (input: 1050, cached: 910, output: 105),
                last: (input: 50, cached: 10, output: 5)),
        ])
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appended.utf8))
        try handle.close()

        let second = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        #expect(second.data.first?.totalTokens == 55)

        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let usage = try #require(cache.files.values.first { $0.sessionId == "growing-child" })
        #expect(usage.sessionId == "growing-child")
        #expect(usage.forkedFromId == "growing-parent")
        #expect(usage.forkBaselineDependencyKey == CostUsageScanner.codexForkDependencyNotRequiredKey)
        #expect(usage.codexScanComplete == true)

        let cleanEnv = try CostUsageTestEnvironment()
        defer { cleanEnv.cleanup() }
        let finalContents = try String(contentsOf: fileURL, encoding: .utf8)
        _ = try cleanEnv.writeCodexSessionFile(
            day: day,
            filename: filename,
            contents: finalContents)
        var cleanOptions = CostUsageScanner.Options(
            codexSessionsRoot: cleanEnv.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: cleanEnv.cacheRoot,
            maxCodexSessionFileBytes: 0,
            maxCodexScanBytesPerRefresh: 0)
        cleanOptions.refreshMinIntervalSeconds = 0
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: cleanOptions)
        let actualLedger = try PersistedCodexLedger.read(
            databaseURL: CostUsageStore(cacheRoot: env.cacheRoot).databaseURL)
        let cleanLedger = try PersistedCodexLedger.read(
            databaseURL: CostUsageStore(cacheRoot: cleanEnv.cacheRoot).databaseURL)
        #expect(actualLedger.usageRows == cleanLedger.usageRows)
    }

    private func turnContext(timestamp: String, model: String) -> [String: Any] {
        [
            "type": "turn_context",
            "timestamp": timestamp,
            "payload": ["model": model],
        ]
    }

    private func tokenCount(
        timestamp: String,
        model: String,
        total: Usage? = nil,
        last: Usage? = nil) -> [String: Any]
    {
        var info: [String: Any] = ["model": model]
        if let total {
            info["total_token_usage"] = [
                "input_tokens": total.input,
                "cached_input_tokens": total.cached,
                "output_tokens": total.output,
            ]
        }
        if let last {
            info["last_token_usage"] = [
                "input_tokens": last.input,
                "cached_input_tokens": last.cached,
                "output_tokens": last.output,
            ]
        }
        return [
            "type": "event_msg",
            "timestamp": timestamp,
            "payload": [
                "type": "token_count",
                "info": info,
            ],
        ]
    }
}

extension CodexSubagentAccountingIntegrationTests {
    @Test
    func `growing subagent replacement preserves committed accounting across resumed passes`() throws {
        let scenario = try GrowingSubagentReplacementScenario()
        try scenario.run()
    }

    @Test
    func `ordinary bounded rollout survives repeated reloads without ledger drift`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 17)
        let timestamp = env.isoString(for: day)
        let filename = "rollout-\(timestamp)-ordinary-long.jsonl"
        let contents = try env.jsonl([
            [
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": ["id": "ordinary-long"],
            ],
            self.turnContext(timestamp: timestamp, model: "openai/gpt-5.4"),
            self.tokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(1)),
                model: "openai/gpt-5.4",
                total: (input: 1000, cached: 900, output: 100)),
        ] + (0..<12).map { index in
            [
                "type": "response_item",
                "timestamp": timestamp,
                "payload": [
                    "sequence": index,
                    "text": String(repeating: "padding", count: 32),
                ],
            ] as [String: Any]
        } + [
            self.tokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(2)),
                model: "openai/gpt-5.4",
                total: (input: 1200, cached: 1000, output: 200)),
        ])
        let fileURL = try env.writeCodexSessionFile(day: day, filename: filename, contents: contents)
        let metadata = CostUsageScanner.codexFileMetadata(fileURL: fileURL)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            maxCodexSessionFileBytes: 512,
            maxCodexScanBytesPerRefresh: 512)
        options.refreshMinIntervalSeconds = 0
        options.useCodexCatchUpWorkingSet = true

        var offsets: [Int64] = []
        var boundedReport: CostUsageDailyReport?
        for pass in 0..<12 {
            let reopened = CostUsageStoreAccess.load(cacheRoot: env.cacheRoot, calendar: options.calendar)
            if let previous = offsets.last {
                #expect(reopened.cache.files.values.first?.parsedBytes == previous)
            }
            boundedReport = CostUsageScanner.loadDailyReport(
                provider: .codex,
                since: day,
                until: day,
                now: day.addingTimeInterval(Double(pass + 1)),
                options: options)
            let usage = try #require(
                CostUsageStoreAccess.read(cacheRoot: env.cacheRoot).files.values.first {
                    $0.sessionId == "ordinary-long"
                })
            let parsedBytes = try #require(usage.parsedBytes)
            offsets.append(parsedBytes)
            if usage.codexScanComplete == true { break }
        }
        #expect(offsets.count > 1)
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(offsets.last == metadata.size)

        let cleanEnv = try CostUsageTestEnvironment()
        defer { cleanEnv.cleanup() }
        let cleanFileURL = try cleanEnv.writeCodexSessionFile(
            day: day,
            filename: filename,
            contents: contents)
        #expect(cleanFileURL.lastPathComponent == filename)
        var cleanOptions = CostUsageScanner.Options(
            codexSessionsRoot: cleanEnv.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: cleanEnv.cacheRoot,
            maxCodexSessionFileBytes: 0,
            maxCodexScanBytesPerRefresh: 0)
        cleanOptions.refreshMinIntervalSeconds = 0
        cleanOptions.useCodexCatchUpWorkingSet = true
        let cleanReport = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: cleanOptions)
        let cleanUsage = try #require(
            CostUsageStoreAccess.read(cacheRoot: cleanEnv.cacheRoot).files.values.first {
                $0.sessionId == "ordinary-long"
            })
        let cleanLedger = try PersistedCodexLedger.read(
            databaseURL: CostUsageStore(cacheRoot: cleanEnv.cacheRoot).databaseURL)
        let finalUsage = try #require(
            CostUsageStoreAccess.read(cacheRoot: env.cacheRoot).files.values.first {
                $0.sessionId == "ordinary-long"
            })
        let finalLedger = try PersistedCodexLedger.read(
            databaseURL: CostUsageStore(cacheRoot: env.cacheRoot).databaseURL)
        #expect(boundedReport?.data == cleanReport.data)
        #expect(boundedReport?.summary == cleanReport.summary)
        #expect(finalUsage.codexRows == cleanUsage.codexRows)
        #expect(finalUsage.codexTokenSnapshots == cleanUsage.codexTokenSnapshots)
        #expect(finalUsage.codexCostNanos == cleanUsage.codexCostNanos)
        #expect(finalLedger.usageRows == cleanLedger.usageRows)
        #expect(finalLedger.tokenSnapshots == cleanLedger.tokenSnapshots)
        #expect(finalLedger.fileDayAggregates == cleanLedger.fileDayAggregates)
        #expect(finalLedger.dayAggregates == cleanLedger.dayAggregates)
        #expect(finalLedger.verifiedDayAggregates == cleanLedger.verifiedDayAggregates)
    }
}

private final class GrowingSubagentReplacementScenario {
    private typealias Usage = (input: Int, cached: Int, output: Int)

    private let env: CostUsageTestEnvironment
    private let day: Date
    private let timestamp: String
    private let childID = "growing-child-multi-pass"
    private let parentID = "growing-parent-multi-pass"
    private let filename: String
    private let parentFilename: String
    private let parentContents: String
    private let fileURL: URL
    private let storeURL: URL
    private let committedEntry: CostUsageDailyReport.Entry
    private let committedLedger: PersistedCodexLedger
    private let committedParsedBytes: Int64
    private let appendChunks: [String]
    private var options: CostUsageScanner.Options

    init() throws {
        let environment = try CostUsageTestEnvironment()
        do {
            let day = try environment.makeLocalNoon(year: 2026, month: 7, day: 16)
            let timestamp = environment.isoString(for: day)
            let childID = "growing-child-multi-pass"
            let parentID = "growing-parent-multi-pass"
            let filename = "rollout-\(timestamp)-\(childID).jsonl"
            let initial = try Self.makeInitialContents(
                environment: environment,
                day: day,
                timestamp: timestamp,
                childID: childID)
            let fileURL = try environment.writeCodexSessionFile(
                day: day,
                filename: filename,
                contents: initial)
            let parentFilename = "rollout-\(timestamp)-\(parentID).jsonl"
            let parentContents = try Self.makeParentContents(
                environment: environment,
                day: day,
                timestamp: timestamp,
                parentID: parentID)
            _ = try environment.writeCodexSessionFile(
                day: day,
                filename: parentFilename,
                contents: parentContents)

            var options = CostUsageScanner.Options(
                codexSessionsRoot: environment.codexSessionsRoot,
                claudeProjectsRoots: nil,
                cacheRoot: environment.cacheRoot,
                maxCodexSessionFileBytes: 64 * 1024,
                maxCodexScanBytesPerRefresh: 64 * 1024)
            options.refreshMinIntervalSeconds = 0
            options.useCodexCatchUpWorkingSet = true
            let committed = CostUsageScanner.loadDailyReport(
                provider: .codex,
                since: day,
                until: day,
                now: day,
                options: options)
            let committedEntry = try #require(committed.data.first)
            #expect(committedEntry.totalTokens == 2200)
            let storeURL = CostUsageStore(cacheRoot: environment.cacheRoot).databaseURL
            let committedLedger = try PersistedCodexLedger.read(databaseURL: storeURL)
            let committedParsedBytes = try #require(
                CostUsageStoreAccess.read(cacheRoot: environment.cacheRoot).files.values.first {
                    $0.sessionId == childID
                }?.parsedBytes)

            self.env = environment
            self.day = day
            self.timestamp = timestamp
            self.filename = filename
            self.parentFilename = parentFilename
            self.parentContents = parentContents
            self.fileURL = fileURL
            self.storeURL = storeURL
            self.committedEntry = committedEntry
            self.committedLedger = committedLedger
            self.committedParsedBytes = committedParsedBytes
            self.options = options
            self.appendChunks = try Self.makeAppendChunks(
                environment: environment,
                day: day,
                timestamp: timestamp,
                childID: childID,
                parentID: parentID)
        } catch {
            environment.cleanup()
            throw error
        }
    }

    deinit {
        self.env.cleanup()
    }

    func run() throws {
        try self.runBoundedPasses()
        let finalContents = try String(contentsOf: self.fileURL, encoding: .utf8)
        let cleanEnv = try CostUsageTestEnvironment()
        defer { cleanEnv.cleanup() }
        let clean = try self.prepareCleanScan(finalContents: finalContents, environment: cleanEnv)
        try self.finish(clean: clean)
    }

    private func runBoundedPasses() throws {
        self.options.maxCodexSessionFileBytes = 512
        self.options.maxCodexScanBytesPerRefresh = 512
        var lastParsedBytes = self.committedParsedBytes
        var lastStagedParsedBytes: Int64 = 0
        for (pass, chunk) in self.appendChunks.enumerated() {
            let reopened = CostUsageStoreAccess.load(
                cacheRoot: self.env.cacheRoot,
                calendar: self.options.calendar)
            let reopenedUsage = try #require(reopened.cache.files.values.first { $0.sessionId == self.childID })
            #expect(reopenedUsage.parsedBytes == lastParsedBytes)
            let beforeLedger = try PersistedCodexLedger.read(databaseURL: self.storeURL)
            Self.assertLedger(beforeLedger, equals: self.committedLedger)

            let handle = try FileHandle(forWritingTo: self.fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(chunk.utf8))
            try handle.close()

            let report = CostUsageScanner.loadDailyReport(
                provider: .codex,
                since: self.day,
                until: self.day,
                now: self.day.addingTimeInterval(Double(pass + 1)),
                options: self.options)
            let entry = try #require(report.data.first)
            #expect(entry == self.committedEntry)
            let pendingCache = CostUsageStoreAccess.read(cacheRoot: self.env.cacheRoot)
            let pendingUsage = try #require(pendingCache.files.values.first { $0.sessionId == self.childID })
            #expect(pendingUsage.codexReplacementScanPending == true)
            #expect(pendingUsage.parsedBytes ?? 0 > lastStagedParsedBytes)
            lastParsedBytes = try #require(pendingUsage.parsedBytes)
            lastStagedParsedBytes = lastParsedBytes
            let afterLedger = try PersistedCodexLedger.read(databaseURL: self.storeURL)
            Self.assertLedger(afterLedger, equals: self.committedLedger)
        }
    }

    private func prepareCleanScan(
        finalContents: String,
        environment: CostUsageTestEnvironment) throws
        -> (report: CostUsageDailyReport, usage: CostUsageFileUsage, ledger: PersistedCodexLedger)
    {
        _ = try environment.writeCodexSessionFile(
            day: self.day,
            filename: self.filename,
            contents: finalContents)
        _ = try environment.writeCodexSessionFile(
            day: self.day,
            filename: self.parentFilename,
            contents: self.parentContents)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: environment.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: environment.cacheRoot,
            maxCodexSessionFileBytes: 0,
            maxCodexScanBytesPerRefresh: 0)
        options.refreshMinIntervalSeconds = 0
        options.useCodexCatchUpWorkingSet = true
        let report = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: self.day,
            until: self.day,
            now: self.day,
            options: options)
        let usage = try #require(
            CostUsageStoreAccess.read(cacheRoot: environment.cacheRoot).files.values.first {
                $0.sessionId == self.childID
            })
        let storeURL = CostUsageStore(cacheRoot: environment.cacheRoot).databaseURL
        let ledger = try PersistedCodexLedger.read(databaseURL: storeURL)
        return (report, usage, ledger)
    }

    private func finish(
        clean: (report: CostUsageDailyReport, usage: CostUsageFileUsage, ledger: PersistedCodexLedger)) throws
    {
        self.options.maxCodexSessionFileBytes = 64 * 1024
        self.options.maxCodexScanBytesPerRefresh = 64 * 1024
        let finalReport = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: self.day,
            until: self.day,
            now: self.day.addingTimeInterval(10),
            options: self.options)
        #expect(finalReport.data == clean.report.data)
        #expect(finalReport.summary == clean.report.summary)
        let finalCache = CostUsageStoreAccess.read(cacheRoot: self.env.cacheRoot)
        let finalUsage = try #require(finalCache.files.values.first { $0.sessionId == self.childID })
        #expect(finalUsage.codexRows == clean.usage.codexRows)
        #expect(finalUsage.codexTokenSnapshots == clean.usage.codexTokenSnapshots)
        #expect(finalUsage.codexCostNanos == clean.usage.codexCostNanos)
        #expect(finalUsage.codexScanComplete == true)
        let finalLedger = try PersistedCodexLedger.read(databaseURL: self.storeURL)
        #expect(finalLedger.fileDayAggregates == clean.ledger.fileDayAggregates)
        #expect(finalLedger.dayAggregates == clean.ledger.dayAggregates)
        #expect(finalLedger.verifiedDayAggregates == clean.ledger.verifiedDayAggregates)

        let idempotentReport = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: self.day,
            until: self.day,
            now: self.day.addingTimeInterval(11),
            options: self.options)
        #expect(idempotentReport.data == finalReport.data)
        #expect(idempotentReport.summary == finalReport.summary)
        let idempotentCache = CostUsageStoreAccess.read(cacheRoot: self.env.cacheRoot)
        let idempotentUsage = try #require(idempotentCache.files.values.first { $0.sessionId == self.childID })
        #expect(idempotentUsage.codexRows == finalUsage.codexRows)
        #expect(idempotentUsage.codexTokenSnapshots == finalUsage.codexTokenSnapshots)
        #expect(idempotentUsage.codexCostNanos == finalUsage.codexCostNanos)
    }

    private static func assertLedger(_ actual: PersistedCodexLedger, equals expected: PersistedCodexLedger) {
        #expect(actual.usageRows == expected.usageRows)
        #expect(actual.tokenSnapshots == expected.tokenSnapshots)
        #expect(actual.fileDayAggregates == expected.fileDayAggregates)
        #expect(actual.dayAggregates == expected.dayAggregates)
        #expect(actual.verifiedDayAggregates == expected.verifiedDayAggregates)
    }

    private static func makeInitialContents(
        environment: CostUsageTestEnvironment,
        day: Date,
        timestamp: String,
        childID: String) throws -> String
    {
        try environment.jsonl([
            [
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": [
                    "id": childID,
                    "source": ["subagent": ["thread_spawn": [:]]],
                ],
            ],
            self.turnContext(timestamp: timestamp, model: "openai/gpt-5.3"),
            self.tokenCount(
                timestamp: environment.isoString(for: day.addingTimeInterval(1)),
                model: "openai/gpt-5.3",
                total: (input: 1000, cached: 900, output: 100)),
        ] + (0..<20).map { index in
            [
                "type": "response_item",
                "timestamp": timestamp,
                "payload": [
                    "sequence": index,
                    "text": String(repeating: "x", count: 128),
                ],
            ] as [String: Any]
        })
    }

    private static func makeParentContents(
        environment: CostUsageTestEnvironment,
        day: Date,
        timestamp: String,
        parentID: String) throws -> String
    {
        try environment.jsonl([
            [
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": ["id": parentID],
            ],
            self.turnContext(timestamp: timestamp, model: "openai/gpt-5.2"),
            self.tokenCount(
                timestamp: environment.isoString(for: day.addingTimeInterval(1)),
                model: "openai/gpt-5.2",
                total: (input: 1000, cached: 900, output: 100)),
        ])
    }

    private static func makeAppendChunks(
        environment: CostUsageTestEnvironment,
        day: Date,
        timestamp: String,
        childID: String,
        parentID: String) throws -> [String]
    {
        try (0..<3).map { pass in
            try environment.jsonl([
                pass == 0
                    ? [
                        "type": "session_meta",
                        "timestamp": timestamp,
                        "payload": ["id": childID, "forked_from_id": parentID],
                    ]
                    : [
                        "type": "response_item",
                        "timestamp": timestamp,
                        "payload": ["sequence": 100 + pass, "text": String(repeating: "y", count: 128)],
                    ],
                pass == 0
                    ? [
                        "type": "session_meta",
                        "timestamp": timestamp,
                        "payload": ["id": parentID],
                    ]
                    : [
                        "type": "response_item",
                        "timestamp": timestamp,
                        "payload": ["sequence": 150 + pass, "text": String(repeating: "p", count: 128)],
                    ],
                Self.turnContext(
                    timestamp: environment.isoString(for: day.addingTimeInterval(Double(2 + pass))),
                    model: "openai/gpt-5.4"),
                pass == 0
                    ? [
                        "type": "inter_agent_communication_metadata",
                        "timestamp": environment.isoString(for: day.addingTimeInterval(2)),
                        "payload": ["trigger_turn": true],
                    ]
                    : [
                        "type": "response_item",
                        "timestamp": timestamp,
                        "payload": ["sequence": 200 + pass, "text": String(repeating: "z", count: 128)],
                    ],
                pass == 0
                    ? Self.tokenCount(
                        timestamp: environment.isoString(for: day.addingTimeInterval(3)),
                        model: "openai/gpt-5.4",
                        total: (input: 1050, cached: 910, output: 105),
                        last: (input: 50, cached: 10, output: 5))
                    : Self.tokenCount(
                        timestamp: environment.isoString(for: day.addingTimeInterval(Double(3 + pass))),
                        model: "openai/gpt-5.4",
                        total: (input: 1050 + 50 * pass, cached: 910 + 10 * pass, output: 105 + 5 * pass),
                        last: (input: 50, cached: 10, output: 5)),
            ])
        }
    }

    private static func turnContext(timestamp: String, model: String) -> [String: Any] {
        [
            "type": "turn_context",
            "timestamp": timestamp,
            "payload": ["model": model],
        ]
    }

    private static func tokenCount(
        timestamp: String,
        model: String,
        total: Usage? = nil,
        last: Usage? = nil) -> [String: Any]
    {
        var info: [String: Any] = ["model": model]
        if let total {
            info["total_token_usage"] = [
                "input_tokens": total.input,
                "cached_input_tokens": total.cached,
                "output_tokens": total.output,
            ]
        }
        if let last {
            info["last_token_usage"] = [
                "input_tokens": last.input,
                "cached_input_tokens": last.cached,
                "output_tokens": last.output,
            ]
        }
        return [
            "type": "event_msg",
            "timestamp": timestamp,
            "payload": [
                "type": "token_count",
                "info": info,
            ],
        ]
    }
}

private struct PersistedCodexLedger: Equatable {
    let usageRows: [String]
    let tokenSnapshots: [String]
    let fileDayAggregates: [String]
    let dayAggregates: [String]
    let verifiedDayAggregates: [String]

    static func read(databaseURL: URL) throws -> Self {
        let connection = try SQLiteLedgerConnection(databaseURL: databaseURL)
        let usageRows = try connection.canonicalJSONRows(
            "SELECT file_id,row_index,hex(payload) FROM usage_rows ORDER BY file_id,row_index")
        let tokenSnapshots = try connection.rows(
            "SELECT file_id,event_index,timestamp,timestamp_ms,day,last_input,last_cached,last_output,last_reasoning," +
                "total_input,total_cached,total_output,total_reasoning,end_offset " +
                "FROM token_snapshots ORDER BY file_id,event_index")
        let fileDayAggregates = try connection.rows(
            "SELECT * FROM file_day_aggregates ORDER BY file_id,day,model")
        let dayAggregates = try connection.rows(
            "SELECT * FROM day_aggregates ORDER BY day,model")
        let verifiedDayAggregates = try connection.rows(
            "SELECT * FROM verified_day_aggregates ORDER BY day,model")
        return Self(
            usageRows: usageRows,
            tokenSnapshots: tokenSnapshots,
            fileDayAggregates: fileDayAggregates,
            dayAggregates: dayAggregates,
            verifiedDayAggregates: verifiedDayAggregates)
    }
}

private final class SQLiteLedgerConnection: @unchecked Sendable {
    private var database: OpaquePointer?

    init(databaseURL: URL) throws {
        let result = sqlite3_open_v2(databaseURL.path, &self.database, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK else {
            throw NSError(
                domain: "CodexSubagentAccountingIntegrationTests",
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: "Unable to open cost usage SQLite database"])
        }
    }

    deinit {
        if let database {
            sqlite3_close_v2(database)
        }
    }

    func rows(_ sql: String) throws -> [String] {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw NSError(
                domain: "CodexSubagentAccountingIntegrationTests",
                code: Int(prepareResult),
                userInfo: [NSLocalizedDescriptionKey: "Unable to prepare SQLite ledger query"])
        }
        defer { sqlite3_finalize(statement) }

        var result = [String]()
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE { break }
            guard stepResult == SQLITE_ROW else {
                throw NSError(
                    domain: "CodexSubagentAccountingIntegrationTests",
                    code: Int(stepResult),
                    userInfo: [NSLocalizedDescriptionKey: "Unable to read SQLite ledger query"])
            }

            var fields = [String]()
            for column in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_NULL:
                    fields.append("NULL")
                case SQLITE_INTEGER:
                    fields.append(String(sqlite3_column_int64(statement, column)))
                case SQLITE_FLOAT:
                    fields.append(String(sqlite3_column_double(statement, column)))
                case SQLITE_TEXT:
                    fields.append(sqlite3_column_text(statement, column).map(String.init(cString:)) ?? "")
                case SQLITE_BLOB:
                    let byteCount = Int(sqlite3_column_bytes(statement, column))
                    guard byteCount > 0, let bytes = sqlite3_column_blob(statement, column) else {
                        fields.append("")
                        continue
                    }
                    let data = Data(bytes: bytes, count: byteCount)
                    fields.append(data.map { String(format: "%02x", $0) }.joined())
                default:
                    fields.append("")
                }
            }
            result.append(fields.joined(separator: "|"))
        }
        return result
    }

    func canonicalJSONRows(_ sql: String) throws -> [String] {
        try self.rows(sql).map { row in
            let fields = row.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let payload = Self.data(fromHex: String(fields[2])),
                  let object = try? JSONSerialization.jsonObject(with: payload),
                  let canonical = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            else { return row }
            return "\(fields[0])|\(fields[1])|\(Self.hexString(canonical))"
        }
    }

    private static func data(fromHex value: String) -> Data? {
        let bytes = Array(value.utf8)
        guard bytes.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        data.reserveCapacity(bytes.count / 2)
        for index in stride(from: 0, to: bytes.count, by: 2) {
            guard let high = Self.hexValue(bytes[index]), let low = Self.hexValue(bytes[index + 1]) else {
                return nil
            }
            data.append(high << 4 | low)
        }
        return data
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
