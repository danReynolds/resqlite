/// Drift schema for the Chat Sim (A5) benchmark.
///
/// Mirrors the SQL schema in `benchmark/suites/chat_sim.dart`:
///   * `users(id PK, name, avatar_url)` — 500 seeded rows
///   * `conversations(id PK, last_msg_at)` — 100 seeded rows
///   * `messages(id PK, conv_id, sender_id, body, sent_at)` with
///     `messages_conv_sent(conv_id, sent_at)` compound index
///
/// When this file changes, regenerate with:
///     dart run build_runner build --delete-conflicting-outputs
library;

import 'package:drift/drift.dart';

part 'chat_sim_db.g.dart';

class Users extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get avatarUrl => text().named('avatar_url').nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Conversations extends Table {
  IntColumn get id => integer()();
  IntColumn get lastMsgAt => integer().named('last_msg_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'messages_conv_sent', columns: {#convId, #sentAt})
class Messages extends Table {
  IntColumn get id => integer()();
  IntColumn get convId => integer().named('conv_id')();
  IntColumn get senderId => integer().named('sender_id')();
  TextColumn get body => text()();
  IntColumn get sentAt => integer().named('sent_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Users, Conversations, Messages])
class ChatSimDriftDb extends _$ChatSimDriftDb {
  ChatSimDriftDb(super.executor);

  @override
  int get schemaVersion => 1;
}
