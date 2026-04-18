/// Drift schema for the Sync Burst (A7) benchmark.
///
/// Mirrors `benchmark/suites/sync_burst.dart`:
///   * `items(id PK, external_id UNIQUE, payload TEXT)`
///   * The UNIQUE constraint on `external_id` is critical — the merge
///     phase uses `INSERT OR REPLACE` which resolves against it.
library;

import 'package:drift/drift.dart';

part 'sync_burst_db.g.dart';

class Items extends Table {
  IntColumn get id => integer()();
  IntColumn get externalId => integer().named('external_id').unique()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Items])
class SyncBurstDriftDb extends _$SyncBurstDriftDb {
  SyncBurstDriftDb(super.executor);

  @override
  int get schemaVersion => 1;
}
