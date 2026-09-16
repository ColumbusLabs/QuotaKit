import CodexBarCore
import CryptoKit
import Foundation

struct SpendDashboardSnapshotRevisionEncoder {
    private static let fingerprintCounter = SpendDashboardSnapshotFingerprintCounter()

    static var fingerprintComputationCount: Int {
        self.fingerprintCounter.count
    }

    static func recordFingerprintComputation() {
        self.fingerprintCounter.record()
    }

    static func fingerprint(_ snapshot: CostUsageTokenSnapshot) -> String {
        var encoder = Self()
        encoder.append(snapshot.currencyCode)
        encoder.append(snapshot.historyDays)
        encoder.append(snapshot.historyCoverageIsEstablished)
        encoder.append(snapshot.updatedAt.timeIntervalSinceReferenceDate)
        encoder.append(snapshot.last30DaysTokens)
        encoder.append(snapshot.last30DaysCostUSD)
        encoder.append(snapshot.daily.count)
        for entry in snapshot.daily {
            encoder.append(entry.date)
            encoder.append(entry.inputTokens)
            encoder.append(entry.cacheReadTokens)
            encoder.append(entry.cacheCreationTokens)
            encoder.append(entry.outputTokens)
            encoder.append(entry.totalTokens)
            encoder.append(entry.requestCount)
            encoder.append(entry.costUSD)
            encoder.append(entry.modelBreakdowns?.count)
            for breakdown in entry.modelBreakdowns ?? [] {
                encoder.append(breakdown.modelName)
                encoder.append(breakdown.totalTokens)
                encoder.append(breakdown.requestCount)
                encoder.append(breakdown.costUSD)
                encoder.append(breakdown.standardCostUSD)
                encoder.append(breakdown.priorityCostUSD)
                encoder.append(breakdown.standardTokens)
                encoder.append(breakdown.priorityTokens)
            }
        }
        encoder.append(snapshot.hourly.count)
        for entry in snapshot.hourly {
            encoder.append(entry.hour.timeIntervalSinceReferenceDate)
            encoder.append(entry.totalTokens)
            encoder.append(entry.costUSD)
        }
        encoder.append(snapshot.projects.count)
        encoder.append(snapshot.sessions.count)
        for project in snapshot.projects {
            encoder.append(project.name)
            encoder.append(project.path ?? "")
            encoder.append(project.totalTokens)
            encoder.append(project.totalCostUSD)
            encoder.append(project.daily.count)
            for entry in project.daily {
                encoder.append(entry.date)
                encoder.append(entry.costUSD)
                encoder.append(entry.totalTokens)
                encoder.append(entry.inputTokens)
                encoder.append(entry.outputTokens)
            }
            if let breakdowns = project.modelBreakdowns {
                encoder.append(breakdowns.count)
                for breakdown in breakdowns {
                    encoder.append(breakdown.modelName)
                    encoder.append(breakdown.costUSD)
                    encoder.append(breakdown.totalTokens)
                }
            } else {
                encoder.append(0)
            }
        }
        for session in snapshot.sessions {
            encoder.append(session.sessionID)
            encoder.append(session.lastActivity.timeIntervalSinceReferenceDate)
            encoder.append(session.totalTokens)
            encoder.append(session.costUSD)
            encoder.append(session.requestCount)
            encoder.append(session.modelBreakdowns.count)
            for breakdown in session.modelBreakdowns {
                encoder.append(breakdown.modelName)
                encoder.append(breakdown.costUSD)
                encoder.append(breakdown.totalTokens)
            }
        }
        return encoder.finalize()
    }

    private var hasher = SHA256()

    private mutating func append(_ value: String) {
        let data = Data(value.utf8)
        self.append(UInt64(data.count))
        data.withUnsafeBytes { bytes in
            self.hasher.update(bufferPointer: bytes)
        }
    }

    private mutating func append(_ value: Int) {
        self.append(UInt64(bitPattern: Int64(value)))
    }

    private mutating func append(_ value: Int?) {
        guard let value else {
            self.appendPresence(false)
            return
        }
        self.appendPresence(true)
        self.append(value)
    }

    private mutating func append(_ value: Bool) {
        self.appendPresence(value)
    }

    private mutating func append(_ value: Double) {
        self.append(value.bitPattern)
    }

    private mutating func append(_ value: Double?) {
        guard let value else {
            self.appendPresence(false)
            return
        }
        self.appendPresence(true)
        self.append(value)
    }

    private mutating func appendPresence(_ isPresent: Bool) {
        var byte = isPresent ? UInt8(1) : UInt8(0)
        withUnsafeBytes(of: &byte) { bytes in
            self.hasher.update(bufferPointer: bytes)
        }
    }

    private mutating func append(_ value: UInt64) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { bytes in
            self.hasher.update(bufferPointer: bytes)
        }
    }

    private mutating func finalize() -> String {
        self.hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class SpendDashboardSnapshotFingerprintCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.value
    }

    func record() {
        self.lock.lock()
        self.value += 1
        self.lock.unlock()
    }
}

struct SpendDashboardModelBuildKey: Hashable, Sendable {
    struct InputIdentity: Hashable, Sendable {
        let id: String
        let provider: UsageProvider
        let displayName: String
        let modelProviderName: String
        let sourceKind: SpendDashboardModel.SourceKind
        let hasTokenActivityCache: Bool
    }

    let sourceRevisions: [String]
    let sourceOwnershipFingerprints: [String]
    /// Monotonic identity for the controller's currently loaded input set.
    /// This covers loader replacements whose configuration revision is not
    /// available (for example, a same-configuration refresh).
    let inputRevision: UInt64
    let providerIDs: [String]
    let codexAccountIdentities: [String]
    let costUsageEnabled: Bool
    let openCodexUsageLogsEnabled: Bool
    let codexHistoryDays: Int
    let inputIdentities: [InputIdentity]
    let requestedDays: Int
    let effectiveNowDay: Date
    let calendarIdentifier: String
    let bucketTimeZoneIdentifier: String
    let firstWeekday: Int
    let minimumDaysInFirstWeek: Int
    let preferredCurrencyCode: String
    let hiddenSourceIDs: [String]
    let hideNativeCodexWhenOpenCodexPresent: Bool
    let selectedDay: Date?

    init(
        configuration: SpendDashboardConfiguration?,
        inputs: [SpendDashboardModel.ProviderInput],
        inputRevision: UInt64 = 0,
        requestedDays: Int,
        now: Date,
        calendar: Calendar,
        preferredCurrencyCode: String,
        hiddenSourceIDs: Set<String>,
        hideNativeCodexWhenOpenCodexPresent: Bool,
        selectedDay: Date?)
    {
        self.sourceRevisions = configuration?.sourceRevisions ?? []
        self.sourceOwnershipFingerprints = configuration?.sourceOwnershipFingerprints ?? []
        self.inputRevision = inputRevision
        self.providerIDs = configuration?.providerIDs ?? []
        self.codexAccountIdentities = configuration?.codexAccountIdentities ?? []
        self.costUsageEnabled = configuration?.costUsageEnabled ?? false
        self.openCodexUsageLogsEnabled = configuration?.openCodexUsageLogsEnabled ?? false
        self.codexHistoryDays = configuration?.codexHistoryDays ?? SpendDashboardSource.scanDays
        self.inputIdentities = inputs.map { input in
            InputIdentity(
                id: input.id,
                provider: input.provider,
                displayName: input.displayName,
                modelProviderName: input.modelProviderName,
                sourceKind: input.sourceKind,
                hasTokenActivityCache: input.tokenActivityCache != nil)
        }
        self.requestedDays = requestedDays
        self.effectiveNowDay = calendar.startOfDay(for: now)
        self.calendarIdentifier = String(describing: calendar.identifier)
        self.bucketTimeZoneIdentifier = calendar.timeZone.identifier
        self.firstWeekday = calendar.firstWeekday
        self.minimumDaysInFirstWeek = calendar.minimumDaysInFirstWeek
        self.preferredCurrencyCode = preferredCurrencyCode
        self.hiddenSourceIDs = hiddenSourceIDs.sorted()
        self.hideNativeCodexWhenOpenCodexPresent = hideNativeCodexWhenOpenCodexPresent
        self.selectedDay = selectedDay.map { calendar.startOfDay(for: $0) }
    }
}

struct SpendDashboardModelBuildRequest: Sendable {
    let inputs: [SpendDashboardModel.ProviderInput]
    let requestedDays: Int
    let now: Date
    let calendar: Calendar
    let preferredCurrencyCode: String
    let hiddenSourceIDs: Set<String>
    let hideNativeCodexWhenOpenCodexPresent: Bool
    let selectedDay: Date?
    let inputRevision: UInt64
    let key: SpendDashboardModelBuildKey

    init(
        configuration: SpendDashboardConfiguration?,
        inputs: [SpendDashboardModel.ProviderInput],
        inputRevision: UInt64 = 0,
        requestedDays: Int,
        now: Date,
        calendar: Calendar,
        preferredCurrencyCode: String,
        hiddenSourceIDs: Set<String>,
        hideNativeCodexWhenOpenCodexPresent: Bool,
        selectedDay: Date?)
    {
        self.inputs = inputs
        self.inputRevision = inputRevision
        self.requestedDays = requestedDays
        self.now = now
        self.calendar = calendar
        self.preferredCurrencyCode = preferredCurrencyCode
        self.hiddenSourceIDs = hiddenSourceIDs
        self.hideNativeCodexWhenOpenCodexPresent = hideNativeCodexWhenOpenCodexPresent
        self.selectedDay = selectedDay
        self.key = SpendDashboardModelBuildKey(
            configuration: configuration,
            inputs: inputs,
            inputRevision: inputRevision,
            requestedDays: requestedDays,
            now: now,
            calendar: calendar,
            preferredCurrencyCode: preferredCurrencyCode,
            hiddenSourceIDs: hiddenSourceIDs,
            hideNativeCodexWhenOpenCodexPresent: hideNativeCodexWhenOpenCodexPresent,
            selectedDay: selectedDay)
    }

    func build() -> SpendDashboardModel {
        SpendDashboardModel.build(
            inputs: self.inputs,
            requestedDays: self.requestedDays,
            now: self.now,
            calendar: self.calendar,
            preferredCurrencyCode: self.preferredCurrencyCode,
            hiddenSourceIDs: self.hiddenSourceIDs,
            hideNativeCodexWhenOpenCodexPresent: self.hideNativeCodexWhenOpenCodexPresent,
            selectedDay: self.selectedDay)
    }
}

struct SpendDashboardModelDerivationCounterSnapshot: Sendable, Equatable {
    let buildStarts: Int
    let buildsExecuted: Int
    let buildCompletions: Int
    let cacheHits: Int
    let staleCompletionsDiscarded: Int
    let buildsCoalesced: Int
    let publicationRequestsDeferred: Int
    let maxConcurrentBuilds: Int
}

final class SpendDashboardModelDerivationCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var buildStarts = 0
    private var buildsExecuted = 0
    private var buildCompletions = 0
    private var cacheHits = 0
    private var staleCompletionsDiscarded = 0
    private var buildsCoalesced = 0
    private var publicationRequestsDeferred = 0
    private var activeBuilds = 0
    private var maxConcurrentBuilds = 0

    var snapshot: SpendDashboardModelDerivationCounterSnapshot {
        self.lock.lock()
        defer { self.lock.unlock() }
        return SpendDashboardModelDerivationCounterSnapshot(
            buildStarts: self.buildStarts,
            buildsExecuted: self.buildsExecuted,
            buildCompletions: self.buildCompletions,
            cacheHits: self.cacheHits,
            staleCompletionsDiscarded: self.staleCompletionsDiscarded,
            buildsCoalesced: self.buildsCoalesced,
            publicationRequestsDeferred: self.publicationRequestsDeferred,
            maxConcurrentBuilds: self.maxConcurrentBuilds)
    }

    func recordBuildStart() {
        self.lock.lock()
        self.buildStarts += 1
        self.activeBuilds += 1
        self.maxConcurrentBuilds = max(self.maxConcurrentBuilds, self.activeBuilds)
        self.lock.unlock()
    }

    func recordBuildExecuted() {
        self.lock.lock()
        self.buildsExecuted += 1
        self.lock.unlock()
    }

    func recordBuildCompletion() {
        self.lock.lock()
        self.buildCompletions += 1
        self.activeBuilds = max(0, self.activeBuilds - 1)
        self.lock.unlock()
    }

    func recordCacheHit() {
        self.lock.lock()
        self.cacheHits += 1
        self.lock.unlock()
    }

    func recordStaleCompletionDiscarded() {
        self.lock.lock()
        self.staleCompletionsDiscarded += 1
        self.lock.unlock()
    }

    func recordBuildCoalesced() {
        self.lock.lock()
        self.buildsCoalesced += 1
        self.lock.unlock()
    }

    func recordPublicationRequestDeferred() {
        self.lock.lock()
        self.publicationRequestsDeferred += 1
        self.lock.unlock()
    }
}

enum SpendDashboardModelBuildPriority: Sendable {
    case controller
    case publication
}

enum SpendDashboardModelBuildEnqueueResult {
    case cached(SpendDashboardModel)
    case scheduled
    case alreadyScheduled
}

private final class SpendDashboardModelBuildJob: @unchecked Sendable {
    let request: SpendDashboardModelBuildRequest
    let builder: @Sendable (SpendDashboardModelBuildRequest) -> SpendDashboardModel
    var completions: [@Sendable (SpendDashboardModel) -> Void]

    init(
        request: SpendDashboardModelBuildRequest,
        builder: @escaping @Sendable (SpendDashboardModelBuildRequest) -> SpendDashboardModel,
        completion: @escaping @Sendable (SpendDashboardModel) -> Void)
    {
        self.request = request
        self.builder = builder
        self.completions = [completion]
    }
}

final class SpendDashboardModelCache: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    let supportsAsynchronousBuilds: Bool
    let counters: SpendDashboardModelDerivationCounters
    private var models: [SpendDashboardModelBuildKey: SpendDashboardModel] = [:]
    private var order: [SpendDashboardModelBuildKey] = []
    private var activeJob: SpendDashboardModelBuildJob?
    private var pendingControllerJob: SpendDashboardModelBuildJob?
    private var pendingPublicationJob: SpendDashboardModelBuildJob?

    init(
        capacity: Int = 4,
        counters: SpendDashboardModelDerivationCounters = SpendDashboardModelDerivationCounters(),
        supportsAsynchronousBuilds: Bool = false)
    {
        self.capacity = max(1, capacity)
        self.supportsAsynchronousBuilds = supportsAsynchronousBuilds
        self.counters = counters
    }

    func model(for key: SpendDashboardModelBuildKey) -> SpendDashboardModel? {
        self.lock.lock()
        guard let model = self.models[key] else {
            self.lock.unlock()
            return nil
        }
        self.order.removeAll { $0 == key }
        self.order.append(key)
        self.lock.unlock()
        self.counters.recordCacheHit()
        return model
    }

    func insert(_ model: SpendDashboardModel, for key: SpendDashboardModelBuildKey) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.models[key] = model
        self.order.removeAll { $0 == key }
        self.order.append(key)
        while self.order.count > self.capacity {
            let evicted = self.order.removeFirst()
            self.models.removeValue(forKey: evicted)
        }
    }

    @discardableResult
    func enqueue(
        request: SpendDashboardModelBuildRequest,
        priority: SpendDashboardModelBuildPriority,
        builder: @escaping @Sendable (SpendDashboardModelBuildRequest) -> SpendDashboardModel,
        completion: @escaping @Sendable (SpendDashboardModel) -> Void) -> SpendDashboardModelBuildEnqueueResult
    {
        if let cached = self.model(for: request.key) {
            return .cached(cached)
        }

        let newJob = SpendDashboardModelBuildJob(
            request: request,
            builder: builder,
            completion: completion)
        var result: SpendDashboardModelBuildEnqueueResult = .scheduled
        var jobToStart: SpendDashboardModelBuildJob?
        var didCoalesce = false

        self.lock.lock()
        if let activeJob = self.activeJob, activeJob.request.key == request.key {
            activeJob.completions.append(completion)
            self.lock.unlock()
            return .alreadyScheduled
        }

        switch priority {
        case .controller:
            if let pendingPublicationJob = self.pendingPublicationJob,
               pendingPublicationJob.request.key == request.key
            {
                newJob.completions.append(contentsOf: pendingPublicationJob.completions)
                self.pendingPublicationJob = nil
            }
            if let pendingControllerJob = self.pendingControllerJob {
                if pendingControllerJob.request.key == request.key {
                    pendingControllerJob.completions.append(contentsOf: newJob.completions)
                    result = .alreadyScheduled
                } else {
                    self.pendingControllerJob = newJob
                    didCoalesce = true
                }
            } else {
                self.pendingControllerJob = newJob
            }
        case .publication:
            if let pendingControllerJob = self.pendingControllerJob,
               pendingControllerJob.request.key == request.key
            {
                pendingControllerJob.completions.append(completion)
                result = .alreadyScheduled
            } else if let pendingPublicationJob = self.pendingPublicationJob {
                if pendingPublicationJob.request.key == request.key {
                    pendingPublicationJob.completions.append(completion)
                    result = .alreadyScheduled
                } else {
                    self.pendingPublicationJob = newJob
                    didCoalesce = true
                }
            } else {
                self.pendingPublicationJob = newJob
            }
        }

        if self.activeJob == nil {
            jobToStart = self.promoteNextJobLocked()
        }
        self.lock.unlock()

        if didCoalesce {
            self.counters.recordBuildCoalesced()
        }
        if let jobToStart {
            self.start(jobToStart)
        }
        return result
    }

    /// Drops a controller request that has become unnecessary because its key is
    /// already applied or the controller has stopped. An active build is left
    /// alone; its completion is still serialized before any later job starts.
    func discardPendingControllerBuild() {
        self.lock.lock()
        self.pendingControllerJob = nil
        self.lock.unlock()
    }

    private func promoteNextJobLocked() -> SpendDashboardModelBuildJob? {
        guard self.activeJob == nil else { return nil }
        let next: SpendDashboardModelBuildJob?
        if let controllerJob = self.pendingControllerJob {
            self.pendingControllerJob = nil
            next = controllerJob
        } else if let publicationJob = self.pendingPublicationJob {
            self.pendingPublicationJob = nil
            next = publicationJob
        } else {
            next = nil
        }
        self.activeJob = next
        return next
    }

    private func start(_ job: SpendDashboardModelBuildJob) {
        self.counters.recordBuildStart()
        Task.detached(priority: .userInitiated) { [cache = self] in
            cache.counters.recordBuildExecuted()
            let model = job.builder(job.request)
            cache.complete(job, model: model)
        }
    }

    private func complete(_ job: SpendDashboardModelBuildJob, model: SpendDashboardModel) {
        self.counters.recordBuildCompletion()
        self.insert(model, for: job.request.key)

        self.lock.lock()
        guard self.activeJob === job else {
            self.lock.unlock()
            return
        }
        self.activeJob = nil
        let completions = job.completions
        let next = self.promoteNextJobLocked()
        self.lock.unlock()

        if let next {
            self.start(next)
        }
        for completion in completions {
            completion(model)
        }
    }
}
