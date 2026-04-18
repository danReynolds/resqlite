/// Drift schema: Text-heavy shape for the Schema Shapes microbenchmark.
/// See `schema_shapes.dart` for context.
library;

import 'package:drift/drift.dart';

part 'schema_shapes_text_db.g.dart';

class TextHeavyT extends Table {
  @override
  String? get tableName => 't';

  IntColumn get id => integer()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get summary => text()();
  TextColumn get notes => text()();
  RealColumn get score => real()();
  IntColumn get count => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [TextHeavyT])
class TextHeavyDriftDb extends _$TextHeavyDriftDb {
  TextHeavyDriftDb(super.executor);
  @override
  int get schemaVersion => 1;
}
