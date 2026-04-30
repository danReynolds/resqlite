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
/// inapplicable. [TableColumDependency] is the precise optimization case:
/// only writes intersecting [columns] need re-query.
base class TableDependency {
  const TableDependency(this.table);

  final String table;
}

/// Dependency on a fixed set of columns in [table].
final class TableColumDependency extends TableDependency {
  const TableColumDependency(super.table, this.columns);

  final Set<String> columns;
}
