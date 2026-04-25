/// Drift schema for the Many-Streams Writer Throughput (A11c) benchmark.
///
/// Mirrors `benchmark/suites/many_streams_writer_throughput.dart`:
///   * `wide(id PK, a, b, c, ..., t)` — 21 columns (id + 20 TEXT)
///   * `partition` is a derived `id % N` filter the streams use to fan
///     out across the row space; no separate column / index needed since
///     range filters on `id` (the PK) hit the implicit rowid index.
///
/// Generated code lives in `many_streams_writer_db.g.dart` (gitignored).
/// Regenerate via:
///
///     dart run build_runner build --delete-conflicting-outputs
library;

import 'package:drift/drift.dart';

part 'many_streams_writer_db.g.dart';

/// Wide table with 20 TEXT columns (a..t). Schema matches the
/// disjoint_columns benchmark intentionally — A11c is the writer-throughput
/// counterpart of that suite's stream-side ratio metric.
class Wide extends Table {
  IntColumn get id => integer()();
  TextColumn get a => text()();
  TextColumn get b => text()();
  TextColumn get c => text()();
  TextColumn get d => text()();
  TextColumn get e => text()();
  TextColumn get f => text()();
  TextColumn get g => text()();
  TextColumn get h => text()();
  TextColumn get i => text()();
  TextColumn get j => text()();
  TextColumn get k => text()();
  TextColumn get l => text()();
  TextColumn get m => text()();
  TextColumn get n => text()();
  TextColumn get o => text()();
  TextColumn get p => text()();
  TextColumn get q => text()();
  TextColumn get r => text()();
  TextColumn get s => text()();
  TextColumn get t => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Wide])
class ManyStreamsWriterDriftDb extends _$ManyStreamsWriterDriftDb {
  ManyStreamsWriterDriftDb(super.executor);

  @override
  int get schemaVersion => 1;
}
