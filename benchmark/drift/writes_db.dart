/// Drift schema for the Write Performance microbenchmarks.
///
/// Covers the `t(id, name, value)` table used by the Single Inserts
/// and Batch Insert subsections of `benchmark/suites/writes.dart`.
///
/// The Interactive Transaction + Batched Write Inside Transaction +
/// Transaction Read subsections are NOT migrated to drift in this
/// round. They specifically exercise resqlite's interactive txn fast
/// paths (`tx.executeBatch` nested write, `resqlite_run_batch_nested`
/// C entry point) that don't have a generic peer equivalent. Adding
/// a `peer.transaction()` primitive to [BenchmarkPeer] is possible
/// but out of scope here.
library;

import 'package:drift/drift.dart';

part 'writes_db.g.dart';

class T extends Table {
  @override
  String? get tableName => 't';

  IntColumn get id => integer()();
  TextColumn get name => text()();
  RealColumn get value => real()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [T])
class WritesDriftDb extends _$WritesDriftDb {
  WritesDriftDb(super.executor);

  @override
  int get schemaVersion => 1;
}
