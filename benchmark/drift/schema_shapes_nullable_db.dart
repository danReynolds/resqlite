/// Drift schema: Nullable shape for the Schema Shapes microbenchmark.
/// See `schema_shapes.dart` for context.
library;

import 'package:drift/drift.dart';

part 'schema_shapes_nullable_db.g.dart';

class NullableT extends Table {
  @override
  String? get tableName => 't';

  IntColumn get id => integer()();
  TextColumn get name => text().nullable()();
  RealColumn get value => real().nullable()();
  TextColumn get tag => text().nullable()();
  IntColumn get count => integer().nullable()();
  TextColumn get note => text().nullable()();
  RealColumn get score => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [NullableT])
class NullableDriftDb extends _$NullableDriftDb {
  NullableDriftDb(super.executor);
  @override
  int get schemaVersion => 1;
}
