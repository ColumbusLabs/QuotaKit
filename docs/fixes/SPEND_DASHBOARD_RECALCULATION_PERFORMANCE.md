# Spend Dashboard Recalculation Performance (#161)

## Scope

This change is limited to repeated spend-dashboard snapshot revision work and
derived-model construction. It preserves the #159 load/liveness contract and
the #160 Codex history-horizon and catch-up policy. Aggregate background-work
budgeting remains explicitly deferred.

## Original repeated-work paths

The shared dashboard observes settings and store state on the main actor.
Observation churn could reconstruct SpendDashboardSource.configuration(...).
Its sourceRevisions(...) helper then called snapshotRevision(snapshot) for
each non-Codex token snapshot. That encoder walked daily history, model
breakdowns, hourly rows, projects, project histories and breakdowns, sessions,
and scalar fields on every configuration capture, even when the immutable
publication had not changed.

The controller's rebuildModel() also called SpendDashboardModel.build(...)
synchronously from @MainActor. A later SpendDashboardPublication.model(...)
request could then build the same semantic model again for the menu consumer.

## Fingerprint ownership

TokenSnapshotPublication now stores an optional semantic fingerprint beside
its immutable snapshot. The fingerprint is computed once at the publication
boundary by UsageStore.spendDashboardSnapshotSemanticFingerprint(...):

- normal token publications compute it in publishTokenSnapshotState;
- provider-snapshot-derived token publications use the same publication path
  (and cached installations compute it when installed);
- independent spend-dashboard token publications compute it in
  publishSpendDashboardTokenSnapshotState;
- confirmed-empty publications remain revision-only and do not hash an absent
  snapshot.

Current-provider publication accessors carry the stored value to
SpendDashboardSource.sourceRevisions(...). The source revision therefore
combines the existing publication revision with the already-computed
fingerprint; configuration assembly no longer traverses a snapshot.
Publication lookup still validates provider configuration and ownership scope,
so account A cannot reuse account B's value and an old provider configuration
cannot reuse a fingerprint under a new scope. The value has publication
lifetime: replacing or clearing the publication drops it, and there is no
unbounded global cache.

The former SpendDashboardSnapshotRevisionEncoder remains, moved into
SpendDashboardModelDerivation.swift, because its field coverage is the
existing semantic invalidation contract. String fields remain deterministic
UTF-8 with length delimiters. Fixed-width integers, floating-point bit
patterns, and presence markers now feed stable stack bytes directly into
CryptoKit instead of allocating a transient Data value for each scalar.

## Model derivation boundary

SpendDashboardController.rebuildModel() captures a
SpendDashboardModelBuildRequest containing the immutable inputs, requested
days, loaded/reference date, calendar and time-zone semantics, preferred
currency, hidden source IDs, native-Codex/OpenCodex presentation flag, selected
day, and the semantic build key. Source/publication state is still published
immediately; it is not held behind model derivation.

The request is evaluated by a cache-owned
Task.detached(priority: .userInitiated). Only the completion callback hops
back to MainActor to validate and apply the result. The injected model-builder
test seam records Thread.isMainThread == false for the production controller
path.

The detached task is deliberately not wrapped in a separately cancellable
Task. Cancelling the old wrapper did not cancel synchronous SpendDashboardModel
work, so rapid changes could leave A, B, and C consuming CPU concurrently.
The cache now owns a single-flight scheduler: one active build, one latest
pending controller request, and at most one pending publication-only request.
Replacing pending B with C drops B and increments the coalesced counter. A is
allowed to finish, its stale result is discarded when appropriate, and C is
the only next controller build.

## Memoization key and lifetime

SpendDashboardModelBuildKey includes:

- source revisions, including publication fingerprints;
- source ownership fingerprints and provider/account identities;
- the controller's loaded-input revision;
- ordered input identity, provider, display name, model-provider name, source
  kind, and token-activity-cache presence;
- requested day range;
- effective current bucket day;
- calendar identifier, bucket time zone, first weekday, and minimum days in the
  first week;
- preferred currency;
- sorted hidden source IDs;
- native-Codex/OpenCodex filtering;
- normalized selected day.

The loaded-input revision covers same-configuration loader replacement where
the configuration's source revision is not itself changed. Input display
identity keeps Codex display-name changes visible without source I/O. The
effective day rather than an instant prevents same-day activation churn from
invalidating a model, while a bucket-day rollover or time-zone change creates
a new key.

Each controller owns one SpendDashboardModelCache with a bounded capacity of
four entries. The controller passes that same cache to its current
SpendDashboardPublication. The cache is controller/publication lifetime and
uses a small recency order; it is not a process-wide cache. Manually
constructed publications use their publication revision as their default
input identity unless a caller supplies a specific loaded-input revision.

The cache also owns the single-flight queues. Controller work has priority
over a pending publication-only scope, so a menu request cannot create a
second concurrent aggregation or cause rapid controller changes to fan out
into multiple detached jobs.

## Final pending-work arbitration correction

The first single-flight implementation had two controller-only supersession
gaps. A→B→A could attach a new completion to active A while leaving obsolete
pending B queued. Likewise, when the latest controller request was already in
the four-entry cache, the controller could apply cached A while leaving a
pending B queued behind a different active build. Both cases caused CPU work
that could never become the current model.

The cache now treats `pendingControllerJob` as only the latest controller
request that still needs computation. A controller request matching active A
merges completions into A and drops a different pending controller job. A
controller request satisfied from cache drops any pending controller job before
returning the cached model. A different uncached controller request replaces
the pending controller job. Pending publication work is never discarded by
these controller-only operations, and controller priority over publication
work remains unchanged.

Cache lookup and admission are now one lock-protected operation: the cache
entry is checked and its LRU position touched under the same lock used to
inspect active and pending jobs. No builder, counter callback, or completion
callback runs while that lock is held. This closes the window in which a build
could insert a key after an initial miss but before queue arbitration, causing
a second build for the same key.

The active build remains allowed to finish because the synchronous builder is
not cooperatively cancellable, but obsolete pending controller work never
starts. The maximum number of concurrent expensive model builds therefore
remains exactly one.

## Stale-build protection

Every scheduled model request advances a model-derivation generation separate
from the source-load generation. A completion is applied only when both its
generation and active semantic key still match the current request. Task
cancellation is not used as CPU-work cancellation or correctness protection.
An older active build may finish and populate the bounded cache, but its
controller completion is discarded when stale and increments the
stale-completion counter. Pending superseded requests never start.

## Publication model reuse

The production publication consumer is
StatusItemController.overviewSpendDashboardModel(...). Its exact
controller/publication request now uses the shared cache instead of executing
another full build. The controller publishes its current request key and
applied model key alongside source state. If the exact key is still pending,
SpendDashboardPublication.model(...) returns immediately without building or
waiting; the controller republishes after the cache completion makes the exact
model available. This fixes the publish-before-detached-completion race that
the previous publication-reuse test missed because it waited for the
controller build before asking the publication for its model.

The status-menu consumer supplies providerScope. When that scope, stale-source
filter, day window, currency, hidden-source set, selected day, and all other
key inputs are exactly equivalent to the controller request, it follows the
exact-key path. A genuinely different provider-scoped request is queued as a
publication-priority job on the same single-flight cache and returns a
non-blocking empty placeholder until completion; completion republishes the
current publication, after which the request is a bounded-cache hit. It never
performs an uncontrolled synchronous full build on the production UI path.

When a controller request itself hits the bounded cache, the controller applies
that model and republishes immediately as well, so the publication's exact-key
state cannot remain marked pending after a cache hit.

Standalone publications created without the controller-owned asynchronous
completion handler retain the existing synchronous fallback for compatibility;
the traced production path always uses the controller-owned cache and handler.

## Invalidation and observability

The focused matrix covers:

- 30 to 90 days;
- preferred-currency changes;
- hidden-source changes;
- selected-day changes;
- bucket time-zone and effective-day changes;
- loaded input/source revision changes;
- provider/account ownership changes;
- Codex display-name changes;
- menu-only ownership/display churn, which does not rebuild the model.

The key also includes native-Codex/OpenCodex filtering; its model behavior
continues to be covered by the existing SpendDashboardModelTests.

The lightweight counters are:

- the process-local, lock-protected fingerprint-computation counter exposed by
  SpendDashboardSnapshotRevisionEncoder;
- model build starts, executions, completions, cache hits, and stale
  completions discarded;
- pending builds coalesced, exact publication requests deferred, and maximum
  concurrent cache-owned builds.

They are lock-protected. Model counters are observation-ignored on the
controller, and the process-local fingerprint counter is not store state, so
counter updates cannot cause dashboard observation churn.

## Targeted verification

The SpendDashboardRecalculationPerformanceTests suite has 13 passing tests.
In addition to the accepted fingerprint and model-key coverage, it now proves
the immediate-publication race and single-flight replacement behavior:

- gated controller request K plus an immediate exact provider-scoped
  publication request records one builder invocation, no additional build
  execution, one deferred publication request, and maximum concurrency one;
- gated A followed by 90-day B, 365-day C, and selected-day churn records
  actual builder requests `[30, 365]`, two coalesced pending requests, one
  stale discard, and maximum concurrency one;
- gated A→B→A records exactly `[30]`: B is discarded before it executes, the
  original A completion is stale, and the newest A completion applies;
- after seeding cached 30 and making 7 current, gated 365 followed by pending
  90 and cached latest 30 executes only `[365]` for the churn; 90 never runs;
- the admission-boundary gate inserts a key while admission is paused and
  receives a cache hit with zero builder invocations;
- exact publication reuse after completion remains a cache hit; a distinct
  provider scope executes once asynchronously and then reuses its result;
- changed ownership cannot reuse the old cached model.

Additional focused results:

- swift test --filter 'returning to the active controller request drops obsolete pending work': 1/1;
- swift test --filter 'cached latest controller request drops obsolete pending work': 1/1;
- swift test --filter 'cache admission observes a concurrent cache insertion atomically': 1/1;
- swift test --filter SpendDashboardRecalculationPerformanceTests: 13/13;
- swift test --filter SpendDashboardPublicationTests: 19/19;
- swift test --filter SpendDashboardControllerTests: 24/24;
- swift test --filter StatusMenuOverviewSpendTests: 6/6;
- swift build: passed;
- swift test --filter SpendDashboardModelTests: 47/47;
- swift test --filter SpendDashboardDateTruthTests: 23/23;
- swift test --filter SpendDashboardLoadLivenessTests: 15/15;
- swift test --filter SpendDashboardCodexHistoryHorizonTests: 20/20.
- SwiftFormat on all five changed Swift files: 0/5 formatted;
- SwiftLint strict on all five changed Swift files: 0 violations.

Publication/controller tests use deterministic model-generation gates rather
than arbitrary sleeps for the new race checks. The liveness tests' behavioral
assertions remain the #159 contract. No full project suite or ./Scripts/test.sh
was run.

## Structural performance proof

Before this change, N repeated configuration captures performed N full
snapshot traversals, N identical derivation requests performed repeated full
model builds, and controller derivation ran on the main actor.

After this change, one immutable publication performs one fingerprint
calculation, one semantic model key performs one actual build with subsequent
cache hits, the controller's expensive builder runs outside the main actor,
and one active scheduler prevents duplicate CPU work during churn. The
immediate-publication test proves that publication-before-completion does not
add a build; the churn test proves A→B→C becomes A→C. A stale completion is
explicitly discarded rather than allowed to overwrite a newer model. The
fingerprint regression test observes one publication computation across
repeated configuration captures; the new-publication test observes exactly
one additional computation for the new publication.

No CPU percentage is claimed. Native Instruments profiling on a representative
large archive is deferred to the final integration/performance phase.

## Compatibility status

#159 load-liveness tests remain green. #160 history-horizon tests remain green,
including routine, visible expanded, and withdrawal behavior. No scanner
policy, dashboard UI, provider/account ownership rule, spend calculation, or
aggregate background-work budget was changed.
