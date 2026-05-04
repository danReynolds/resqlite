/// Profile-mode allocation counters.
///
/// All increments MUST be wrapped in `if (kProfileMode) { ... }` so
/// Dart's AOT compiler tree-shakes them out of release builds. The
/// counters themselves are plain `int` fields; they cost nothing when
/// never incremented.
///
/// **Purpose.** Support memory-axis experiments
/// ([EXP-055](../../experiments/055-columnar-typed-arrays.md) columnar typed
/// arrays, FFI param allocation, blob path optimization, etc.) by
/// giving the profile-mode harness exact counts of what the decode
/// path produced. RSS delta from `ProcessInfo.currentRss` is a coarse
/// lower bound; `Database.diagnostics()` is SQLite-specific; these
/// counters fill the Dart-side gap.
///
/// **Isolate scope.** Dart isolates don't share top-level state. These
/// counters are currently populated from the main isolate — specifically
/// by the `benchmark/profile/profiled_database.dart` wrapper, which
/// sees every result after it crosses back from a worker. That lets
/// the harness snapshot aggregates around a workload without a custom
/// cross-isolate protocol.
///
/// **Counters that require worker-isolate visibility** (per-SQLite-type
/// breakdowns, e.g. "how many int cells got boxed into `List<Object?>`"
/// — the [EXP-055](../../experiments/055-columnar-typed-arrays.md) metric)
/// are NOT captured here yet. Adding them
/// requires a round-trip request to each worker to snapshot its local
/// state, which is a meaningful protocol addition — deferred to the
/// experiment that actually needs it.
///
/// **Adding new counters.**
///   1. Add a static `int` field here with a doc comment.
///   2. Add it to [snapshot] and [diff].
///   3. Increment it at the relevant hot path, gated by `kProfileMode`.
/// Keep additions minimal — prefer extending an existing counter's
/// semantics over introducing a parallel one.
library;

class ProfileCounters {
  ProfileCounters._();

  /// Rows materialized and returned to the caller's code. One per
  /// SQL row in every `select` result that passes back through the
  /// main isolate. Incremented from `ProfiledDatabase.select()` —
  /// includes reader-pool results (the dominant decode path) but not
  /// internal stream-engine re-queries unless they route through a
  /// harness-visible call site.
  static int rowsDecoded = 0;

  /// Cells materialized — sum of `rowCount × colCount` for every
  /// returned result. More precise than rows when a workload mixes
  /// queries with different column counts.
  static int cellsDecoded = 0;

  /// Cumulative wall-clock microseconds spent inside the synchronous
  /// body of `StreamEngine.onDependencyChanges` — `_tableIndex` lookup,
  /// per-entry column intersection checks, dirty/in-flight
  /// scheduling, and `_flushQueue` kickoff. Incremented per write when
  /// at least one stream is registered. Used by the A11c profile
  /// harness to isolate writer-side fanout cost from the reader-pool
  /// drain time captured in `yield_us`.
  static int invalidateUs = 0;
  static int invalidateCount = 0;

  /// Cumulative wall-clock microseconds spent specifically inside
  /// `StreamEngine.onDependencyChanges` column-set intersection probes.
  /// Sum across every concrete column-vs-column watcher visited per
  /// dependency change. Lets the harness compute average
  /// per-watcher intersection cost as `intersectionUs /
  /// intersectionEntries`.
  static int intersectionUs = 0;
  static int intersectionEntries = 0;

  /// Times a `ReaderPool._dispatch` caller parked because no worker was
  /// currently available for dispatch - for example, when every worker
  /// was busy or when workers were temporarily unavailable during
  /// respawn/sacrifice. One increment per dispatch wait.
  ///
  /// Added by [EXP-115](../../experiments/115-dispatcher-park-counters.md)
  /// to make the parked-dispatcher path that
  /// [exp 105](../../experiments/105-reader-pool-sizing.md) and
  /// [exp 114](../../experiments/114-fifo-waiter-queue.md) targeted directly
  /// observable, without needing a workload that surfaces the cost as
  /// wall time.
  static int dispatcherParkedTotal = 0;

  /// Times a parked dispatcher resumed from the await but found no
  /// available worker on the next scan and re-parked. Under the old
  /// shared-completer wakeup scheme this was the wake-amplification
  /// signal: every worker-free event woke every parked dispatcher,
  /// exactly one won the freed slot, and the rest re-parked. FIFO or
  /// slot-handoff dispatch should keep this counter near zero.
  ///
  /// `dispatcherWakeRetryTotal / dispatcherParkedTotal` is the average
  /// spurious-wake fraction per park event over a workload.
  static int dispatcherWakeRetryTotal = 0;

  /// Peak observed concurrency of parked dispatchers since the last
  /// [reset]. Computed monotonically: incremented before each park,
  /// compared against the high-water mark, and decremented immediately
  /// after the park wait resumes. A peak > pool size is the precondition
  /// for the wake-amplification cost; without sustained parking past the
  /// worker count, dispatch-internal optimizations are benchmark-invisible
  /// (see exp 114 future-notes).
  static int dispatcherMaxParkedConcurrent = 0;

  /// Internal — running count of currently parked dispatchers. Not
  /// exported in [snapshot]; only used to maintain
  /// [dispatcherMaxParkedConcurrent]. Mutated only on the main
  /// isolate (where `ReaderPool._dispatch` runs).
  static int dispatcherCurrentParked = 0;

  /// Cumulative wall-clock microseconds spent inside the writer
  /// isolate's `_handleExecute` and `_handleBatch` bodies — message
  /// receive through reply send. Includes Dart-side parameter
  /// encoding, the FFI write call itself, dirty-table extraction, and
  /// reply marshalling.
  ///
  /// Together with [writerNativeUs] this lets a profile-mode harness
  /// split per-write writer-isolate wall into "SQLite-side native
  /// work" and "everything else": the difference
  /// `writerHandlerUs - writerNativeUs` is the writer-isolate
  /// dispatch overhead on the write path. Added by
  /// [EXP-123](../../experiments/123-writer-dispatch-step-split.md).
  ///
  /// **Isolate scope.** Lives in the writer isolate only. Snapshot
  /// across the isolate boundary via
  /// `Database.writerProfileSnapshot()`; never appears in this
  /// class's main-isolate [snapshot] map. Combined Execute + Batch.
  static int writerHandlerUs = 0;

  /// Number of writer-isolate Execute + Batch handler invocations
  /// captured in [writerHandlerUs]. Lets the audit harness compute
  /// `writerHandlerUs / writerHandlerCount` for a per-write average.
  static int writerHandlerCount = 0;

  /// Cumulative wall-clock microseconds spent specifically inside the
  /// FFI write call (`resqliteExecute`, `resqliteRunBatch`, or
  /// `resqliteRunBatchNested`) — i.e. the SQLite-side prepare / bind /
  /// step / reset / commit work plus the FFI crossing itself.
  ///
  /// Wired through the optional `nativeStopwatch` parameter on
  /// [executeWrite], [executeBatchWrite], and [executeNestedBatchWrite]
  /// so the timed region is exactly the FFI call and nothing else.
  /// Writer-isolate scope (see [writerHandlerUs]).
  static int writerNativeUs = 0;

  /// Number of FFI write calls captured in [writerNativeUs]. Equal to
  /// [writerHandlerCount] in steady state — they diverge only if the
  /// handler exits early before issuing the FFI call (for example, a
  /// rejected request that throws before reaching `executeWrite`).
  static int writerNativeCount = 0;

  /// Take a named snapshot of all counter values.
  ///
  /// Only includes counters mutated on the calling isolate. The
  /// writer-isolate-local `writer*` counters never appear here unless
  /// [snapshot] is called from inside the writer isolate; main-isolate
  /// callers should use `Database.writerProfileSnapshot()` to read
  /// them across the isolate boundary.
  static Map<String, int> snapshot() => {
    'rows_decoded': rowsDecoded,
    'cells_decoded': cellsDecoded,
    'invalidate_us': invalidateUs,
    'invalidate_count': invalidateCount,
    'intersection_us': intersectionUs,
    'intersection_entries': intersectionEntries,
    'dispatcher_parked_total': dispatcherParkedTotal,
    'dispatcher_wake_retry_total': dispatcherWakeRetryTotal,
    'dispatcher_max_parked_concurrent': dispatcherMaxParkedConcurrent,
  };

  /// Compute `after - before` for every key present in both snapshots.
  static Map<String, int> diff(
    Map<String, int> before,
    Map<String, int> after,
  ) {
    final out = <String, int>{};
    for (final key in after.keys) {
      final a = before[key];
      final b = after[key];
      if (a != null && b != null) out[key] = b - a;
    }
    return out;
  }

  /// Reset all counters on the calling isolate to zero. This includes
  /// the writer-isolate-local `writer*` counters when called from
  /// inside the writer isolate, but main-isolate callers can only
  /// reset the writer-side counters via
  /// `Database.resetWriterProfileCounters()`.
  static void reset() {
    rowsDecoded = 0;
    cellsDecoded = 0;
    invalidateUs = 0;
    invalidateCount = 0;
    intersectionUs = 0;
    intersectionEntries = 0;
    dispatcherParkedTotal = 0;
    dispatcherWakeRetryTotal = 0;
    dispatcherMaxParkedConcurrent = 0;
    dispatcherCurrentParked = 0;
    writerHandlerUs = 0;
    writerHandlerCount = 0;
    writerNativeUs = 0;
    writerNativeCount = 0;
  }
}
