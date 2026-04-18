/// Drift schema for the Keyed PK Subscriptions (A11) benchmark.
///
/// Generated code lives in `keyed_pk_db.g.dart` (gitignored). Regenerate via:
///
///     dart run build_runner build --delete-conflicting-outputs
///
/// The schema intentionally mirrors the manual DDL in `benchmark/suites/
/// keyed_pk_subscriptions.dart`: `items(id PK, body TEXT NOT NULL,
/// updated_at INTEGER NOT NULL)`. Drift generates the table descriptors
/// that its `StreamQueryStore` needs for invalidation; the actual queries
/// in the benchmark go through `customSelect` / `customStatement` so every
/// peer sees the same raw SQL (see peer.dart for the fairness argument).
library;

import 'package:drift/drift.dart';

part 'keyed_pk_db.g.dart';

class Items extends Table {
  IntColumn get id => integer()();
  TextColumn get body => text()();
  IntColumn get updatedAt => integer().named('updated_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Items])
class KeyedPkDriftDb extends _$KeyedPkDriftDb {
  KeyedPkDriftDb(super.executor);

  @override
  int get schemaVersion => 1;
}
