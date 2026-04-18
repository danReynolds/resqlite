/// Drift schema for the Column-Disjoint Streams benchmark.
///
/// Mirrors `benchmark/suites/disjoint_columns.dart`:
///   * `wide(id PK, a, b, c, ..., t)` — 21 columns (id + 20 TEXT)
///   * Seed: 5,000 rows, each column filled with `'v<i>'`
library;

import 'package:drift/drift.dart';

part 'disjoint_columns_db.g.dart';

/// Wide table with 20 TEXT columns (a..t). Explicitly enumerated — drift
/// has no "generate N columns" facility; matches the SQL DDL 1:1.
class Wide extends Table {
  IntColumn get id => integer()();
  TextColumn get a => text()();
  TextColumn get b => text()();
  TextColumn get c => text()();
  TextColumn get d => text()();
  TextColumn get e => text()();
  TextColumn get f => text()();
  TextColumn get g => text()();
  TextColumn get h => text()();
  TextColumn get i => text()();
  TextColumn get j => text()();
  TextColumn get k => text()();
  TextColumn get l => text()();
  TextColumn get m => text()();
  TextColumn get n => text()();
  TextColumn get o => text()();
  TextColumn get p => text()();
  TextColumn get q => text()();
  TextColumn get r => text()();
  TextColumn get s => text()();
  TextColumn get t => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Wide])
class DisjointColumnsDriftDb extends _$DisjointColumnsDriftDb {
  DisjointColumnsDriftDb(super.executor);

  @override
  int get schemaVersion => 1;
}
