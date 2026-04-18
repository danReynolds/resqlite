/// Drift schema for the Feed Paging (A6) benchmark.
///
/// Mirrors `benchmark/suites/feed_paging.dart`:
///   * `posts(id PK, author_id, created_at, body, like_count)`
///   * Compound index `posts_created_at_id(created_at DESC, id)` for keyset
///     pagination. Drift models this as a plain `@TableIndex` — the DESC
///     directive is embedded at query time in the keyset walk.
///
/// Seed: 100,000 rows.
library;

import 'package:drift/drift.dart';

part 'feed_paging_db.g.dart';

@TableIndex(name: 'posts_created_at_id', columns: {#createdAt, #id})
class Posts extends Table {
  IntColumn get id => integer()();
  IntColumn get authorId => integer().named('author_id')();
  IntColumn get createdAt => integer().named('created_at')();
  TextColumn get body => text()();
  IntColumn get likeCount => integer().named('like_count').withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Posts])
class FeedPagingDriftDb extends _$FeedPagingDriftDb {
  FeedPagingDriftDb(super.executor);

  @override
  int get schemaVersion => 1;
}
