/// Profile-mode diagnostic counters.
///
/// All increments MUST be wrapped in `if (kProfileMode) { ... }` so
/// Dart's AOT compiler tree-shakes them out of release builds. The
/// counters themselves are plain `int` fields; they cost nothing when
/// never incremented.
///
/// **Purpose.** Support experiment-mode investigations that need more
/// than wall time:
///
/// - memory-axis work (exp 055 columnar typed arrays, blob-path churn,
///   param-marshalling allocation)
/// - reactive-path work (exp 052 column-level dependency tracking,
///   disjoint writes vs overlapping writes, rerun suppression)
///
/// RSS delta from `ProcessInfo.currentRss` is a coarse lower bound;
/// `Database.diagnostics()` is SQLite-specific; these counters fill the
/// Dart-side / stream-engine gap.
///
/// **Isolate scope.** Dart isolates don't share top-level state. These
/// counters are currently populated from the main isolate — specifically
/// by the `benchmark/profile/profiled_database.dart` wrapper, which
/// sees every result after it crosses back from a worker. That lets
/// the harness snapshot aggregates around a workload without a custom
/// cross-isolate protocol.
///
/// **Counters that require worker-isolate visibility** (per-SQLite-type
/// breakdowns, e.g. "how many int cells got boxed into `List<Object?>`")
/// are NOT captured here yet. Adding them requires a round-trip request
/// to each worker to snapshot its local state, which is a meaningful
/// protocol addition — deferred until an experiment needs it.
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

  /// Number of non-empty dirty-table invalidation payloads delivered to
  /// the stream engine.
  static int streamInvalidationsReceived = 0;

  /// Total stream-entry fan-out selected by the inverted index across
  /// invalidation flushes. Lets exp 052 compare "same writes, fewer
  /// affected streams" once writer-side precision exists.
  static int streamAffectedEntries = 0;

  /// Number of times `_scheduleReQuery` was asked to mark a stream
  /// entry dirty.
  static int streamRerunsRequested = 0;

  /// Number of rerun requests absorbed into an already in-flight rerun or an
  /// already-queued next-turn follow-up rerun.
  static int streamRerunsDeferredInflight = 0;

  /// Number of actual reruns started.
  static int streamRerunsStarted = 0;

  /// Number of reruns abandoned before they ever acquired a reader worker
  /// because a newer invalidation had already made them obsolete.
  static int streamRerunsSkippedBeforeDispatch = 0;

  /// Cumulative microseconds reruns spent waiting for an available reader
  /// worker before dispatch.
  static int streamRerunPoolWaitUs = 0;

  /// Cumulative microseconds from dispatch to response receipt for reruns
  /// once a reader worker had been acquired.
  static int streamRerunRoundTripUs = 0;

  /// Cumulative microseconds spent inside the worker executing
  /// `selectIfChanged` for reruns.
  static int streamRerunWorkerExecUs = 0;

  /// Cumulative microseconds spent on the main isolate after a rerun
  /// response arrives, covering stale/unchanged checks, cache update,
  /// and subscriber delivery.
  static int streamRerunCompletionUs = 0;

  /// Number of reruns that returned "unchanged" from the worker-side
  /// `selectIfChanged` fast path.
  static int streamResultsUnchanged = 0;

  /// Number of reruns discarded because a newer invalidation landed
  /// while the query was still in flight.
  static int streamResultsStale = 0;

  /// Number of rerun emissions delivered to subscribers. Initial stream
  /// emissions are intentionally excluded so disjoint/overlap workloads
  /// can compare write-driven reactivity without setup noise.
  static int streamEmitsDelivered = 0;

  /// Take a named snapshot of all counter values.
  static Map<String, int> snapshot() => {
        'rows_decoded': rowsDecoded,
        'cells_decoded': cellsDecoded,
        'stream_invalidations_received': streamInvalidationsReceived,
        'stream_affected_entries': streamAffectedEntries,
        'stream_reruns_requested': streamRerunsRequested,
        'stream_reruns_deferred_inflight': streamRerunsDeferredInflight,
        'stream_reruns_started': streamRerunsStarted,
        'stream_reruns_skipped_before_dispatch':
            streamRerunsSkippedBeforeDispatch,
        'stream_rerun_pool_wait_us': streamRerunPoolWaitUs,
        'stream_rerun_round_trip_us': streamRerunRoundTripUs,
        'stream_rerun_worker_exec_us': streamRerunWorkerExecUs,
        'stream_rerun_completion_us': streamRerunCompletionUs,
        'stream_results_unchanged': streamResultsUnchanged,
        'stream_results_stale': streamResultsStale,
        'stream_emits_delivered': streamEmitsDelivered,
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

  /// Reset all counters to zero.
  static void reset() {
    rowsDecoded = 0;
    cellsDecoded = 0;
    streamInvalidationsReceived = 0;
    streamAffectedEntries = 0;
    streamRerunsRequested = 0;
    streamRerunsDeferredInflight = 0;
    streamRerunsStarted = 0;
    streamRerunsSkippedBeforeDispatch = 0;
    streamRerunPoolWaitUs = 0;
    streamRerunRoundTripUs = 0;
    streamRerunWorkerExecUs = 0;
    streamRerunCompletionUs = 0;
    streamResultsUnchanged = 0;
    streamResultsStale = 0;
    streamEmitsDelivered = 0;
  }
}
