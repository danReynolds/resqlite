/// Drift schema for the High-Cardinality Stream Fan-out (A11b) benchmark.
///
/// Mirrors `benchmark/suites/high_cardinality_fanout.dart`:
///   * `items(id PK, owner_id, value)`
///   * Index `items_owner(owner_id)` — 100 streams each filter by owner_id
///   * Seed: 10,000 items across 100 owners (100 per owner)
library;

import 'package:drift/drift.dart';

part 'high_card_fanout_db.g.dart';

@TableIndex(name: 'items_owner', columns: {#ownerId})
class Items extends Table {
  IntColumn get id => integer()();
  IntColumn get ownerId => integer().named('owner_id')();
  IntColumn get value => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Items])
class HighCardFanoutDriftDb extends _$HighCardFanoutDriftDb {
  HighCardFanoutDriftDb(super.executor);

  @override
  int get schemaVersion => 1;
}
