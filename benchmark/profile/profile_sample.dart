/// Timing + meta for a single instrumented Database call.
///
/// Used by the Phase 1 "dispatch budget" research pass — measures
/// where each millisecond goes on workloads where resqlite currently
/// trails sqlite3 (small inserts, point queries, merge rounds).
///
/// Stays entirely in `benchmark/profile/` so production code is not
/// touched. See experiments/080-dispatch-budget.md for the analysis
/// this data feeds.
class ProfileSample {
  const ProfileSample({
    required this.op,
    required this.sql,
    required this.totalMicros,
    this.paramCount = 0,
    this.rowsReturned,
    this.tag,
  });

  /// Which public API was called — `execute`, `executeBatch`, `select`, `stream-initial`.
  final String op;

  /// SQL text (truncated to 80 chars for compactness in output).
  final String sql;

  /// Total wall time from the caller's perspective, await-to-return.
  final int totalMicros;

  /// Parameter count, for correlating perf with bind work.
  final int paramCount;

  /// Rows in the response (null for writes).
  final int? rowsReturned;

  /// Optional tag for grouping samples in the report (e.g. "hot loop iteration N").
  final String? tag;

  Map<String, Object?> toJson() => {
        'op': op,
        'sql': sql.length > 80 ? '${sql.substring(0, 77)}...' : sql,
        'total_us': totalMicros,
        'params': paramCount,
        if (rowsReturned != null) 'rows': rowsReturned,
        if (tag != null) 'tag': tag,
      };
}
