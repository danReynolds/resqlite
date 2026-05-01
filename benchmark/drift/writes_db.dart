/// Drift schema for the Write Performance microbenchmarks.
///
/// Covers the `t(id, name, value)` table used by the Single Inserts
/// and narrow Batch Insert subsections of `benchmark/suites/writes.dart`,
/// plus `wide_batch` for the 20-parameter batch shape added after
/// exp 113 showed row width is a first-class write-path dimension.
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

class WideBatch extends Table {
  @override
  String? get tableName => 'wide_batch';

  IntColumn get id => integer()();
  TextColumn get c0 => text()();
  IntColumn get c1 => integer()();
  RealColumn get c2 => real()();
  BlobColumn get c3 => blob()();
  TextColumn get c4 => text()();
  IntColumn get c5 => integer()();
  RealColumn get c6 => real()();
  BlobColumn get c7 => blob()();
  TextColumn get c8 => text()();
  IntColumn get c9 => integer()();
  RealColumn get c10 => real()();
  BlobColumn get c11 => blob()();
  TextColumn get c12 => text()();
  IntColumn get c13 => integer()();
  RealColumn get c14 => real()();
  BlobColumn get c15 => blob()();
  TextColumn get c16 => text()();
  IntColumn get c17 => integer()();
  RealColumn get c18 => real()();
  BlobColumn get c19 => blob()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [T, WideBatch])
class WritesDriftDb extends _$WritesDriftDb {
  WritesDriftDb(super.executor);

  @override
  int get schemaVersion => 1;
}
