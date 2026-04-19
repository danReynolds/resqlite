/// Timing + meta for a single instrumented Database call.
///
/// Produced by `ProfiledDatabase` and consumed by the profile-mode
/// harnesses (`run_profile.dart`, `dispatch_budget.dart`). See
/// `benchmark/EXPERIMENTS.md` for the full workflow.
///
/// Stays entirely in `benchmark/profile/` so production code is not
/// touched.
class ProfileSample {
  const ProfileSample({
    required this.op,
    required this.sql,
    required this.totalMicros,
    this.paramCount = 0,
    this.rowsReturned,
    this.batchSize,
    this.tag,
  });

  /// Which `ProfiledDatabase` method was called: `execute`,
  /// `executeBatch`, or `select`.
  final String op;

  /// SQL text (truncated to 80 chars in [toJson] for compactness).
  final String sql;

  /// Total wall time from the caller's perspective, await-to-return.
  final int totalMicros;

  /// Parameter count — bind arity for `execute`/`select`, or the
  /// per-row parameter count for `executeBatch` (all rows share a
  /// single SQL statement + bind arity).
  final int paramCount;

  /// Number of rows returned to the caller. Populated for `select`;
  /// null for writes.
  final int? rowsReturned;

  /// Number of parameter-row tuples in an `executeBatch` call.
  /// Populated for `executeBatch`; null for other ops.
  final int? batchSize;

  /// Optional tag for grouping samples in the report (e.g. "hot loop
  /// iteration N").
  final String? tag;

  Map<String, Object?> toJson() => {
        'op': op,
        'sql': sql.length > 80 ? '${sql.substring(0, 77)}...' : sql,
        'total_us': totalMicros,
        'params': paramCount,
        if (rowsReturned != null) 'rows': rowsReturned,
        if (batchSize != null) 'batch_size': batchSize,
        if (tag != null) 'tag': tag,
      };
}
