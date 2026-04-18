/// Drift schema: Narrow shape (`t(id, value INTEGER)`) for the
/// Schema Shapes microbenchmark. See `schema_shapes.dart` for context.
library;

import 'package:drift/drift.dart';

part 'schema_shapes_narrow_db.g.dart';

class NarrowT extends Table {
  @override
  String? get tableName => 't';

  IntColumn get id => integer()();
  IntColumn get value => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [NarrowT])
class NarrowDriftDb extends _$NarrowDriftDb {
  NarrowDriftDb(super.executor);
  @override
  int get schemaVersion => 1;
}
