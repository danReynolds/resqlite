/// Drift schema: Wide shape (20-col `t`) for the Schema Shapes
/// microbenchmark. See `schema_shapes.dart` for context.
library;

import 'package:drift/drift.dart';

part 'schema_shapes_wide_db.g.dart';

class WideT extends Table {
  @override
  String? get tableName => 't';

  IntColumn get id => integer()();
  IntColumn get c1 => integer().nullable()();
  IntColumn get c2 => integer().nullable()();
  IntColumn get c3 => integer().nullable()();
  IntColumn get c4 => integer().nullable()();
  RealColumn get c5 => real().nullable()();
  RealColumn get c6 => real().nullable()();
  RealColumn get c7 => real().nullable()();
  RealColumn get c8 => real().nullable()();
  TextColumn get c9 => text().nullable()();
  TextColumn get c10 => text().nullable()();
  TextColumn get c11 => text().nullable()();
  TextColumn get c12 => text().nullable()();
  IntColumn get c13 => integer().nullable()();
  RealColumn get c14 => real().nullable()();
  TextColumn get c15 => text().nullable()();
  IntColumn get c16 => integer().nullable()();
  TextColumn get c17 => text().nullable()();
  RealColumn get c18 => real().nullable()();
  IntColumn get c19 => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [WideT])
class WideDriftDb extends _$WideDriftDb {
  WideDriftDb(super.executor);
  @override
  int get schemaVersion => 1;
}
