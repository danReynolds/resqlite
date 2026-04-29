/// Dependency and invalidation value types shared by the native bindings,
/// writer, and stream engine.
///
/// Tables are the correctness layer: when table tracking is unknown, every
/// stream must be invalidated. Columns are an optimization layer scoped to a
/// known table: when column tracking is unknown for that table, streams already
/// watching the table re-query.

/// The per-table read-column dependency map used by stream entries.
typedef ColumnDependencyMap = Map<String, ColumnDependencies>;

/// Table dependency set.
sealed class TableDependencies {
  const TableDependencies._();

  /// Concrete list of tables.
  const factory TableDependencies.fixed(List<String> tables) =
      FixedTableDependencies;

  /// Unknown dependency set. Consumers must take the all-tables fallback.
  static const all = AllTableDependencies._();
}

/// Known, bounded table dependency list.
final class FixedTableDependencies extends TableDependencies {
  const FixedTableDependencies(this.tables) : super._();

  final List<String> tables;

  bool get isEmpty => tables.isEmpty;
}

/// Sentinel for unreliable native table dependency tracking.
final class AllTableDependencies extends TableDependencies {
  const AllTableDependencies._() : super._();
}

/// Column dependency set for one known table.
sealed class ColumnDependencies {
  const ColumnDependencies._();

  /// Concrete set of columns. Column elision can apply by intersection.
  const factory ColumnDependencies.fixed(Set<String> columns) =
      FixedColumnDependencies;

  /// Unknown / all columns for the table.
  static const all = AllColumnDependencies._();
}

/// Known, bounded column dependency set for one table.
final class FixedColumnDependencies extends ColumnDependencies {
  const FixedColumnDependencies(this.columns) : super._();

  final Set<String> columns;
}

/// Sentinel for "any column may matter" within a known table.
final class AllColumnDependencies extends ColumnDependencies {
  const AllColumnDependencies._() : super._();
}

/// Write-side column invalidation for one dirty table.
final class TableInvalidation {
  const TableInvalidation(this.table, this.columns);

  final String table;
  final ColumnDependencies columns;
}

/// Invalidation publication produced by writer activity and consumed by the
/// stream engine.
sealed class StreamInvalidation {
  const StreamInvalidation._();

  /// No invalidation should be published for this writer response.
  static const none = NoStreamInvalidation._();

  /// Publish dirty table metadata, optionally with per-table column detail.
  const factory StreamInvalidation.dirty(
    TableDependencies tables, {
    List<TableInvalidation> columnInvalidations,
  }) = DirtyStreamInvalidation;
}

/// No-op invalidation publication.
final class NoStreamInvalidation extends StreamInvalidation {
  const NoStreamInvalidation._() : super._();
}

/// Concrete invalidation publication for a completed write cycle.
final class DirtyStreamInvalidation extends StreamInvalidation {
  const DirtyStreamInvalidation(
    this.tables, {
    this.columnInvalidations = const <TableInvalidation>[],
  }) : super._();

  final TableDependencies tables;
  final List<TableInvalidation> columnInvalidations;
}
