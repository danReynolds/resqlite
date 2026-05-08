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
/// **Isolate scope.** Dart isolates don't share top-level state. Most
/// counters are populated from the main isolate. Writer-isolate timings
/// are copied back on internal writer responses and accumulated here by
/// the main-isolate writer client, so profile harnesses can still
/// snapshot one counter map.
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

  /// Main-isolate wall time spent awaiting writer operations. This
  /// includes isolate message delivery/copy, writer scheduling, native
  /// write work, dirty-dependency fetch, and the response hop back to
  /// the caller, but excludes `StreamEngine.onDependencyChanges` because
  /// that is already reported by [invalidateUs].
  static int writerRoundtripUs = 0;

  /// Worker-isolate wall time spent inside the write helper call:
  /// Dart parameter packing, FFI entry/exit, native bind/step/reset, and
  /// result unmarshalling for `execute`.
  static int writerWriteCallUs = 0;

  /// Profile-only split of [writerWriteCallUs] for `executeBatch`: time spent
  /// flattening Dart parameter rows into the native batch matrix buffer.
  ///
  /// This is zero for `execute` and transaction `commit` requests.
  static int writerBatchParamPackUs = 0;

  /// Profile-only split of [writerWriteCallUs] for `executeBatch`: time spent
  /// inside `resqlite_run_batch*` after the parameter matrix has been packed.
  ///
  /// This includes native bind / step / reset / transaction-control work and
  /// excludes Dart-side parameter packing.
  static int writerBatchNativeWriteUs = 0;

  /// Worker-isolate wall time spent fetching and materializing dirty
  /// table/column dependencies after a profiled write call.
  static int writerDirtyFetchUs = 0;

  /// Number of profiled writer execute, batch, and commit requests.
  static int writerRequestCount = 0;

  /// Cumulative wall-clock microseconds spent by stream re-query tasks
  /// awaiting `ReaderPool.selectIfChanged`. This includes dispatch wait,
  /// worker execution, reply delivery, and scheduling delay observed by the
  /// main-isolate continuation. Because stream re-queries overlap, this is
  /// per-request accumulated time rather than workload wall time.
  static int streamRequeryAwaitUs = 0;
  static int streamRequeryCount = 0;

  /// Number of stream re-queries whose worker-side hash comparison returned
  /// changed or unchanged results.
  static int streamRequeryChangedCount = 0;
  static int streamRequeryUnchangedCount = 0;
  static int streamRequeryDiscardedCount = 0;

  /// Synchronous wall-clock microseconds spent delivering changed stream rows
  /// to subscriber controllers. Listener callbacks run later; this only covers
  /// the `StreamController.add` fan-out loop.
  static int streamEmitUs = 0;
  static int streamEmitCount = 0;

  /// Cumulative wall-clock microseconds spent parked in `ReaderPool._dispatch`
  /// after all reader workers were busy.
  static int readerDispatchWaitUs = 0;

  /// Synchronous wall-clock microseconds spent in the main-isolate reader reply
  /// handler before the pending read future is completed.
  static int readerReplyDeliveryUs = 0;
  static int readerReplyDeliveryCount = 0;

  /// Take a named snapshot of all counter values.
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
    'writer_roundtrip_us': writerRoundtripUs,
    'writer_write_call_us': writerWriteCallUs,
    'writer_batch_param_pack_us': writerBatchParamPackUs,
    'writer_batch_native_write_us': writerBatchNativeWriteUs,
    'writer_dirty_fetch_us': writerDirtyFetchUs,
    'writer_request_count': writerRequestCount,
    'stream_requery_await_us': streamRequeryAwaitUs,
    'stream_requery_count': streamRequeryCount,
    'stream_requery_changed_count': streamRequeryChangedCount,
    'stream_requery_unchanged_count': streamRequeryUnchangedCount,
    'stream_requery_discarded_count': streamRequeryDiscardedCount,
    'stream_emit_us': streamEmitUs,
    'stream_emit_count': streamEmitCount,
    'reader_dispatch_wait_us': readerDispatchWaitUs,
    'reader_reply_delivery_us': readerReplyDeliveryUs,
    'reader_reply_delivery_count': readerReplyDeliveryCount,
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
    invalidateUs = 0;
    invalidateCount = 0;
    intersectionUs = 0;
    intersectionEntries = 0;
    dispatcherParkedTotal = 0;
    dispatcherWakeRetryTotal = 0;
    dispatcherMaxParkedConcurrent = 0;
    dispatcherCurrentParked = 0;
    writerRoundtripUs = 0;
    writerWriteCallUs = 0;
    writerBatchParamPackUs = 0;
    writerBatchNativeWriteUs = 0;
    writerDirtyFetchUs = 0;
    writerRequestCount = 0;
    streamRequeryAwaitUs = 0;
    streamRequeryCount = 0;
    streamRequeryChangedCount = 0;
    streamRequeryUnchangedCount = 0;
    streamRequeryDiscardedCount = 0;
    streamEmitUs = 0;
    streamEmitCount = 0;
    readerDispatchWaitUs = 0;
    readerReplyDeliveryUs = 0;
    readerReplyDeliveryCount = 0;
  }
}
