/// Dependency value types shared by the native bindings, writer, reader, and
/// stream engine.
///
/// Tables are the correctness layer: when table tracking is unknown, every
/// stream must re-query. Columns are an optimization layer scoped to a known
/// table: when column tracking is unavailable for that table, streams already
/// watching the table re-query.

/// Tracked table set for one query or write cycle.
sealed class TableDependencies {
  const TableDependencies._();

  /// Known empty table set.
  static const none = FixedTableDependencies([]);

  /// Unknown table set. Consumers must re-query every stream.
  static const unknown = UnknownTableDependencies._();

  /// Known table set.
  const factory TableDependencies.fixed(List<TableDependency> tables) =
      FixedTableDependencies;
}

/// Known, bounded table dependency list.
final class FixedTableDependencies extends TableDependencies {
  const FixedTableDependencies(this.tables) : super._();

  final List<TableDependency> tables;

  bool get isEmpty => tables.isEmpty;
}

/// Sentinel for unreliable native table tracking.
final class UnknownTableDependencies extends TableDependencies {
  const UnknownTableDependencies._() : super._();
}

/// Table-level dependency.
///
/// A plain [TableDependency] means column precision is unavailable or
/// inapplicable. [TableColumnDependency] is the precise optimization case:
/// only writes intersecting [columns] need re-query.
base class TableDependency {
  const TableDependency(this.table);

  final String table;
}

/// Dependency on a fixed set of columns in [table].
final class TableColumnDependency extends TableDependency {
  const TableColumnDependency(super.table, this.columns);

  final Set<String> columns;
}

/// Dependency on a fixed set of rowids in [table].
///
/// [columns] is optional. When present, both rowid and column precision can
/// elide a re-query. When absent, rowid precision is the only optimization and
/// column changes fall back to table-level behavior for matching rowids.
final class TableRowDependency extends TableDependency {
  const TableRowDependency(super.table, {required this.rowIds, this.columns});

  final Set<int> rowIds;
  final Set<String>? columns;
}
