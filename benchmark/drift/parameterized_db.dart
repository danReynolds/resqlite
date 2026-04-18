/// Drift schema for the Parameterized Queries microbenchmark.
///
/// Separate from `micro_items_db.dart` because this scenario uses a
/// different items shape (4 columns, no description/created_at) and
/// adds an index on `category` — parameterized filters by category in
/// the hot loop. The index is critical to the narrative (statement
/// cache benefit on a parameterized + indexed query).
library;

import 'package:drift/drift.dart';

part 'parameterized_db.g.dart';

@TableIndex(name: 'idx_category', columns: {#category})
class Items extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  RealColumn get value => real()();
  TextColumn get category => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Items])
class ParameterizedDriftDb extends _$ParameterizedDriftDb {
  ParameterizedDriftDb(super.executor);

  @override
  int get schemaVersion => 1;
}
