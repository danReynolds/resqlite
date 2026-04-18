/// Drift schema for the Large Working Set (A9) benchmark.
///
/// Mirrors `benchmark/suites/large_working_set.dart`:
///   * `items(id PK, payload TEXT)` — minimal schema, 5M seeded rows,
///     each with a ~200-char payload (~1 GB total).
///
/// Read-only benchmark; drift doesn't re-seed, it opens against the
/// cached seed file created by the resqlite peer. The drift `@DriftDatabase`
/// schemaVersion must match what's on disk (or drift's migration logic
/// kicks in and adds overhead). Version 1 matches the plain table we seed.
library;

import 'package:drift/drift.dart';

part 'large_working_set_db.g.dart';

class Items extends Table {
  IntColumn get id => integer()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Items])
class LargeWorkingSetDriftDb extends _$LargeWorkingSetDriftDb {
  LargeWorkingSetDriftDb(super.executor);

  @override
  int get schemaVersion => 1;
}
