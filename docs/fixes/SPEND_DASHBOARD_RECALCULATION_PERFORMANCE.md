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

The request is evaluated by Task.detached(priority: .userInitiated). An
explicit main-actor wrapper only applies the completed model. The injected
model-builder test seam records Thread.isMainThread == false for the
production controller path.

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
SpendDashboardPublication, so an exact publication model request reuses the
controller result. The cache is controller/publication lifetime and uses a
small recency order; it is not a process-wide cache. Manually constructed
publications use their publication revision as their default input identity
unless a caller supplies a specific loaded-input revision.

## Stale-build protection

Every scheduled model request advances a model-derivation generation separate
from the source-load generation. A completion is applied only when both its
generation and active semantic key still match the current request. Task
cancellation is only an optimization; it is not correctness protection.
Older detached work may finish and populate the bounded cache, but it is
discarded for presentation and increments the stale-completion counter.

## Publication model reuse

The production publication consumer is
StatusItemController.overviewSpendDashboardModel(...). Its exact
controller/publication request now hits the shared cache instead of executing
another full build. A provider scope, stale-source filter, day window,
currency, hidden-source set, selected day, or other semantic difference
produces a different key and remains independent and correct. A genuinely
different request may still use the synchronous publication API for its first
result; it is not confused with the controller's exact model.

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
- native-Codex/OpenCodex filtering;
- menu-only ownership/display churn, which does not rebuild the model.

The lightweight counters are:

- the process-local, lock-protected fingerprint-computation counter exposed by
  SpendDashboardSnapshotRevisionEncoder;
- model build starts, executions, completions, cache hits, and stale
  completions discarded.

They are lock-protected. Model counters are observation-ignored on the
controller, and the process-local fingerprint counter is not store state, so
counter updates cannot cause dashboard observation churn.

## Targeted verification

The new SpendDashboardRecalculationPerformanceTests suite has 9 passing
tests covering one fingerprint per publication, new-publication invalidation and
scope isolation, deterministic fingerprints, cache reuse, non-main execution,
stale completion discard, the invalidation matrix, publication reuse, and
ownership isolation.

Additional focused results:

- swift test --filter SpendDashboardRecalculationPerformanceTests: 9/9;
- swift test --filter SpendDashboardPublicationTests: 19/19;
- swift test --filter SpendDashboardControllerTests: 24/24;
- swift test --filter SpendDashboardModelTests: 47/47;
- swift test --filter SpendDashboardDateTruthTests: 23/23;
- swift test --filter SpendDashboardLoadLivenessTests: 15/15;
- swift test --filter SpendDashboardCodexHistoryHorizonTests: 20/20.

The liveness tests were updated only to await deterministic model-derivation
completion after source-load completion; their behavioral assertions remain
the #159 contract. No full project suite or ./Scripts/test.sh was run.

## Structural performance proof

Before this change, N repeated configuration captures performed N full
snapshot traversals, N identical derivation requests performed repeated full
model builds, and controller derivation ran on the main actor.

After this change, one immutable publication performs one fingerprint
calculation, one semantic model key performs one actual build with subsequent
cache hits, and the controller's expensive builder runs outside the main
actor. A stale completion is explicitly discarded rather than allowed to
overwrite a newer model. The fingerprint regression test observes one
publication computation across repeated configuration captures; the
new-publication test observes exactly one additional computation for the new
publication.

No CPU percentage is claimed. Native Instruments profiling on a representative
large archive is deferred to the final integration/performance phase.

## Compatibility status

#159 load-liveness tests remain green. #160 history-horizon tests remain green,
including routine, visible expanded, and withdrawal behavior. No scanner
policy, dashboard UI, provider/account ownership rule, spend calculation, or
aggregate background-work budget was changed.
