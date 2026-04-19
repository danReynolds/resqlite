/// Profile-mode allocation counters.
///
/// All increments MUST be wrapped in `if (kProfileMode) { ... }` so
/// Dart's AOT compiler tree-shakes them out of release builds. The
/// counters themselves are plain `int` fields; they cost nothing when
/// never incremented.
///
/// **Purpose.** Support memory-axis experiments (exp 055 columnar typed
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
/// — the exp 055 metric) are NOT captured here yet. Adding them
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

  /// Take a named snapshot of all counter values.
  static Map<String, int> snapshot() => {
        'rows_decoded': rowsDecoded,
        'cells_decoded': cellsDecoded,
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
  }
}
