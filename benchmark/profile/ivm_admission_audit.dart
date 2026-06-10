// Profile-mode audit: how much of an app-shaped reactive query mix does
// the exp 160 tier-1 classifier admit, and what do its streams do during
// a realistic write burst?
//
// The tracelite app-shaped scenarios (chat-sim, feed-paging) exercise
// select(), not stream(), so no existing workload answers the question
// "what fraction of real reactive UI queries benefit from incremental
// maintenance?". This harness builds the missing workload: chat + feed
// schemas mirroring the tracelite scenarios, a stream mix drawn from the
// screens a real app would keep live, and a chat-shaped write burst.
//
// Run:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/ivm_admission_audit.dart
//
// Reports per-query admission verdicts (via the classifier directly, so
// rejection reasons can be annotated) plus the engine's profile counters
// across the burst: admitted/rejected, skipped/applied/bailed, and the
// re-query traffic that remains.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/stream_ivm.dart';

const _userCount = 200;
const _conversationCount = 50;
const _seedMessages = 2000;
const _feedItems = 1000;
const _writeCount = 300;

final class _StreamSpec {
  const _StreamSpec(this.label, this.table, this.sql, this.paramsFor);

  final String label;
  final String table;
  final String sql;
  final List<Object?> Function(int instance) paramsFor;
}

/// The reactive screens a chat + feed app keeps live, 10 instances each
/// (different conversations / users / authors).
const int _instancesPerSpec = 10;

final _specs = <_StreamSpec>[
  _StreamSpec(
    'message pane (JOIN + DESC + LIMIT)',
    'messages',
    'SELECT m.id, m.body, m.sent_at, u.name, u.avatar_url '
        'FROM messages m JOIN users u ON u.id = m.sender_id '
        'WHERE m.conv_id = ? ORDER BY m.sent_at DESC LIMIT 20',
    _convParam,
  ),
  _StreamSpec(
    'message pane, denormalized (DESC + LIMIT)',
    'messages',
    'SELECT id, sender_id, body, sent_at FROM messages '
        'WHERE conv_id = ? ORDER BY sent_at DESC LIMIT 20',
    _convParam,
  ),
  _StreamSpec(
    'conversation list (DESC + LIMIT, no tiebreak)',
    'conversations',
    'SELECT id, last_msg_at FROM conversations '
        'ORDER BY last_msg_at DESC LIMIT 30',
    _noParams,
  ),
  _StreamSpec(
    'conversation list (DESC + LIMIT, pk tiebreak)',
    'conversations',
    'SELECT id, last_msg_at FROM conversations '
        'ORDER BY last_msg_at DESC, id DESC LIMIT 30',
    _noParams,
  ),
  _StreamSpec(
    'unread badge (aggregate)',
    'messages',
    'SELECT COUNT(*) AS unread FROM messages WHERE conv_id = ? AND id > ?',
    (i) => [_convParam(i).first, 0],
  ),
  _StreamSpec(
    'user card (pk equality)',
    'users',
    'SELECT id, name, avatar_url FROM users WHERE id = ?',
    (i) => [i + 1],
  ),
  _StreamSpec(
    'full conversation transcript (int equality + ORDER BY pk)',
    'messages',
    'SELECT id, sender_id, body, sent_at FROM messages '
        'WHERE conv_id = ? ORDER BY id',
    _convParam,
  ),
  _StreamSpec(
    'feed page (DESC + LIMIT)',
    'feed_items',
    'SELECT id, author_id, created_at, body, like_count FROM feed_items '
        'ORDER BY created_at DESC, id DESC LIMIT 50',
    _noParams,
  ),
  _StreamSpec(
    'author drafts (int equality + ORDER BY pk)',
    'feed_items',
    'SELECT id, body, like_count FROM feed_items '
        'WHERE author_id = ? ORDER BY id',
    (i) => [i + 1],
  ),
];

List<Object?> _convParam(int instance) => [instance + 1];
List<Object?> _noParams(int instance) => const [];

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_ivm_audit_');
  final db = await Database.open('${dir.path}/app.db');

  await _setupSchema(db);

  // Direct classifier verdict per spec, against the real table metadata.
  final verdicts = <String, String>{};
  for (final spec in _specs) {
    final info = await db.select('PRAGMA table_info("${spec.table}")');
    final master = await db.select(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      [spec.table],
    );
    final shape = classifyIvmQuery(
      spec.sql,
      spec.paramsFor(0),
      spec.table,
      info,
      createSql: master.isEmpty ? null : master.first['sql'] as String?,
    );
    verdicts[spec.label] = switch (shape) {
      null => 'no',
      IvmFullShape(limit: final l) => l == null ? 'full' : 'windowed',
      IvmSkipShape() => 'skip-only',
      IvmAggregateShape() => 'aggregate',
    };
  }

  // Install the stream mix and wait for initial emissions.
  final emissions = <String, int>{for (final s in _specs) s.label: 0};
  final subs = <StreamSubscription<Object?>>[];
  final initial = <Future<void>>[];
  for (final spec in _specs) {
    for (var i = 0; i < _instancesPerSpec; i++) {
      final first = Completer<void>();
      initial.add(first.future);
      subs.add(
        db.stream(spec.sql, spec.paramsFor(i)).listen((_) {
          if (!first.isCompleted) {
            first.complete();
          } else {
            emissions[spec.label] = emissions[spec.label]! + 1;
          }
        }),
      );
    }
  }
  await Future.wait(initial).timeout(const Duration(seconds: 30));
  // Let async admission (PRAGMA round trips) settle before counting.
  await Future<void>.delayed(const Duration(milliseconds: 200));

  // Admission happens at registration — snapshot before resetting for
  // the burst counters.
  final admissionSnap = ProfileCounters.snapshot();

  // Chat-shaped write burst: 70% new message + conversation bump,
  // 15% feed like, 10% profile edit, 5% message edit. New messages get
  // sent_at above every seed row so DESC panes see them enter their
  // windows, as they would in a real app.
  final prng = math.Random(160);
  ProfileCounters.reset();
  final sw = Stopwatch()..start();
  var nextMessageId = _seedMessages + 1;
  for (var w = 0; w < _writeCount; w++) {
    final roll = prng.nextInt(100);
    if (roll < 70) {
      final conv = prng.nextInt(_conversationCount) + 1;
      await db.execute(
        'INSERT INTO messages(id, conv_id, sender_id, body, sent_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          nextMessageId,
          conv,
          prng.nextInt(_userCount) + 1,
          'msg',
          _seedMessages + w + 1,
        ],
      );
      nextMessageId++;
      await db.execute(
        'UPDATE conversations SET last_msg_at = ? WHERE id = ?',
        [_seedMessages + w + 1, conv],
      );
    } else if (roll < 85) {
      await db.execute(
        'UPDATE feed_items SET like_count = like_count + 1 WHERE id = ?',
        [prng.nextInt(_feedItems) + 1],
      );
    } else if (roll < 95) {
      await db.execute('UPDATE users SET name = ? WHERE id = ?', [
        'renamed_$w',
        prng.nextInt(_userCount) + 1,
      ]);
    } else {
      await db.execute('UPDATE messages SET body = ? WHERE id = ?', [
        'edited_$w',
        prng.nextInt(_seedMessages) + 1,
      ]);
    }
    await Future<void>.delayed(Duration.zero);
  }
  sw.stop();

  // Quiet-window drain so trailing re-queries land before the snapshot.
  var last = emissions.values.fold<int>(0, (a, b) => a + b);
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final now = emissions.values.fold<int>(0, (a, b) => a + b);
    if (now == last) break;
    last = now;
  }
  final snap = ProfileCounters.snapshot();

  print('# IVM admission audit (app-shaped stream mix)\n');
  print(
    '| stream | instances | tier-1 admitted | burst emissions |',
  );
  print('|---|---:|---|---:|');
  for (final spec in _specs) {
    print(
      '| ${spec.label} | $_instancesPerSpec '
      '| ${verdicts[spec.label]} '
      '| ${emissions[spec.label]} |',
    );
  }
  final admittedSpecs = verdicts.values.where((v) => v != 'no').length;
  print('\nSpecs admitted: $admittedSpecs/${_specs.length} '
      '(${admittedSpecs * _instancesPerSpec}/${_specs.length * _instancesPerSpec} stream instances)');
  print('Burst wall: ${(sw.elapsedMicroseconds / 1000).toStringAsFixed(2)} ms '
      'for $_writeCount write ops (writes issue 1-2 statements each)');
  print('\nEngine admission counters (at registration):\n');
  for (final key in [
    'ivm_admitted_total',
    'ivm_admitted_skip_total',
    'ivm_admitted_agg_total',
    'ivm_rejected_total',
  ]) {
    print('- `$key`: ${admissionSnap[key]}');
  }
  print('\nEngine counters across the burst:\n');
  for (final key in [
    'ivm_skipped_total',
    'ivm_applied_total',
    'ivm_bail_total',
    'ivm_hit_fallback_total',
    'invalidate_count',
    'completion_handler_count',
  ]) {
    print('- `$key`: ${snap[key]}');
  }
  final decisions =
      (snap['ivm_skipped_total'] ?? 0) + (snap['ivm_applied_total'] ?? 0);
  print(
    '\nPer-stream invalidation decisions resolved without a reader '
    're-query: $decisions',
  );

  for (final sub in subs) {
    await sub.cancel();
  }
  await db.close();
  await dir.delete(recursive: true);
  exit(0);
}

Future<void> _setupSchema(Database db) async {
  await db.execute(
    'CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT NOT NULL, '
    'avatar_url TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE conversations(id INTEGER PRIMARY KEY, '
    'last_msg_at INTEGER NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE messages(id INTEGER PRIMARY KEY, conv_id INTEGER NOT NULL, '
    'sender_id INTEGER NOT NULL, body TEXT NOT NULL, sent_at INTEGER NOT NULL)',
  );
  await db.execute(
    'CREATE INDEX messages_conv_sent ON messages(conv_id, sent_at DESC)',
  );
  await db.execute(
    'CREATE TABLE feed_items(id INTEGER PRIMARY KEY, '
    'author_id INTEGER NOT NULL, created_at INTEGER NOT NULL, '
    'body TEXT NOT NULL, like_count INTEGER NOT NULL)',
  );
  await db.executeBatch(
    'INSERT INTO users(id, name, avatar_url) VALUES (?, ?, ?)',
    [
      for (var i = 1; i <= _userCount; i++)
        [i, 'user_$i', 'https://example.com/a/$i.png'],
    ],
  );
  await db.executeBatch(
    'INSERT INTO conversations(id, last_msg_at) VALUES (?, ?)',
    [
      for (var i = 1; i <= _conversationCount; i++) [i, 0],
    ],
  );
  await db.executeBatch(
    'INSERT INTO messages(id, conv_id, sender_id, body, sent_at) '
    'VALUES (?, ?, ?, ?, ?)',
    [
      for (var i = 1; i <= _seedMessages; i++)
        [
          i,
          (i % _conversationCount) + 1,
          (i % _userCount) + 1,
          'seed message $i',
          i,
        ],
    ],
  );
  await db.executeBatch(
    'INSERT INTO feed_items(id, author_id, created_at, body, like_count) '
    'VALUES (?, ?, ?, ?, ?)',
    [
      for (var i = 1; i <= _feedItems; i++)
        [i, (i % _userCount) + 1, i, 'post $i', 0],
    ],
  );
}
