/// Drift schema: Numeric-heavy shape for the Schema Shapes microbenchmark.
/// See `schema_shapes.dart` for context.
library;

import 'package:drift/drift.dart';

part 'schema_shapes_numeric_db.g.dart';

class NumericHeavyT extends Table {
  @override
  String? get tableName => 't';

  IntColumn get id => integer()();
  IntColumn get a => integer()();
  IntColumn get b => integer()();
  RealColumn get c => real()();
  RealColumn get d => real()();
  IntColumn get e => integer()();
  TextColumn get label => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [NumericHeavyT])
class NumericHeavyDriftDb extends _$NumericHeavyDriftDb {
  NumericHeavyDriftDb(super.executor);
  @override
  int get schemaVersion => 1;
}
