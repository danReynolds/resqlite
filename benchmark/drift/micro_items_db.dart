/// Drift schema for the standard "items" microbenchmarks.
///
/// Shared by select_maps, select_bytes, scaling, concurrent_reads,
/// point_query, and memory. Schema mirrors
/// `standardCreateSql` in `benchmark/shared/seeder.dart` 1:1:
///   items(id PK, name, description, value REAL, category, created_at)
///
/// A couple of the microbenchmarks filter on `category` — drift
/// doesn't need an explicit index for those because sqlite's query
/// planner will still scan the table; the seed size is small. If we
/// ever seed >100K rows here, add `@TableIndex(name: 'items_category',
/// columns: {#category})`.
///
/// When this file or its shape changes, regenerate with:
///     dart run build_runner build --delete-conflicting-outputs
library;

import 'package:drift/drift.dart';

part 'micro_items_db.g.dart';

class Items extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  RealColumn get value => real()();
  TextColumn get category => text()();
  TextColumn get createdAt => text().named('created_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Items])
class MicroItemsDriftDb extends _$MicroItemsDriftDb {
  MicroItemsDriftDb(super.executor);

  @override
  int get schemaVersion => 1;
}
