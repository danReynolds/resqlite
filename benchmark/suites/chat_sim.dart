// ignore_for_file: avoid_print

/// A5 — Chat Sim (v1).
///
/// Mixed read/write workload modeling a messaging app. Three tables
/// (users, conversations, messages), Zipfian message distribution across
/// conversations (a few popular conversations hold most messages), and
/// a deterministic 10K-op rotation across 4 op types:
///
///   - 5%  INSERT a new message into a Zipfian-picked conversation
///   - 5%  UPDATE a conversation's `last_msg_at`
///   - 45% SELECT last 20 messages for a conversation (JOIN users)
///   - 45% SELECT 1 user by PK
///
/// The 90/10 read/write skew matches typical UI apps where reads
/// dominate (feeds, details screens) and writes are sparse (user
/// actions). Per-op-type timings are reported in separate subsections
/// so readers can see where each library wins or loses.
///
/// Peers: all three. sqlite3.dart is included — no reactive streams
/// needed in this workload. The synchronous-vs-async contrast is the
/// point: async libraries with worker isolates (resqlite, sqlite_async)
/// should keep main-isolate time far below wall time; sqlite3's main
/// and wall are identical (sync on the calling isolate).
library;

import 'dart:io';
import 'dart:math' as math;

import '../drift/chat_sim_db.dart';
import '../shared/peer.dart';
import '../shared/stats.dart';
import '../shared/workload.dart';

const WorkloadMeta chatSimMeta = WorkloadMeta(
  slug: 'chat_sim',
  version: 1,
  title: 'Chat Sim',
  description: 'Mixed R/W workload: 500 users, 100 conversations, 10K '
      'seed messages (Zipfian distribution). 10K ops: 5% message '
      'inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 '
      'with user JOIN, 45% fetch-user-by-PK. Measures each op type '
      'separately so per-library wall/main tradeoffs are legible.',
);

// Seed sizes — fixed, reflected in v1.
const int _userCount = 500;
const int _conversationCount = 100;
const int _seedMessageCount = 10000;

// Op mix.
const int _totalOps = 10000;
const int _warmupOps = 500;

// Zipfian skew: exponent s. Larger = more skewed toward popular
// conversations. 1.0 = classic Zipf; real chat apps often skew harder.
const double _zipfExponent = 1.0;

// Deterministic PRNG seed so every peer sees the same traffic.
const int _prngSeed = 0x5EED;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<String> runChatSimBenchmark() async {
  final md = StringBuffer()
    ..writeln('## ${chatSimMeta.sectionHeading}')
    ..writeln()
    ..writeln(chatSimMeta.description)
    ..writeln();

  // Generate the op sequence once; all peers get identical traffic.
  final ops = _generateOpSequence(
    totalOps: _totalOps,
    userCount: _userCount,
    conversationCount: _conversationCount,
    seed: _prngSeed,
  );

  final perPeerTimings = <String, Map<_OpType, BenchmarkTiming>>{};

  final tempDir = await Directory.systemTemp.createTemp('bench_chat_sim_');
  try {
    final peers = await PeerSet.open(
      tempDir.path,
      driftFactory: driftFactoryFor((exec) => ChatSimDriftDb(exec)),
    );
    try {
      for (final peer in peers.all) {
        print('  running on ${peer.name}...');
        await _seed(peer);
        perPeerTimings['${peer.label} chat'] = await _measure(peer, ops);
      }
    } finally {
      await peers.closeAll();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }

  _writeResults(md, perPeerTimings);
  return md.toString();
}

// ---------------------------------------------------------------------------
// Op types + sequence
// ---------------------------------------------------------------------------

enum _OpType {
  insertMessage,
  updateConversation,
  readMessages,
  readUser;

  /// Human-readable title for the per-op-type subsection on the
  /// dashboard. Kept stable across versions unless the op's meaning
  /// changes (a meaning change should bump `chatSimMeta.version`).
  String get title {
    switch (this) {
      case _OpType.insertMessage:
        return 'Insert message';
      case _OpType.updateConversation:
        return 'Update conversation';
      case _OpType.readMessages:
        return 'Fetch last-20 messages (JOIN users)';
      case _OpType.readUser:
        return 'Fetch user by PK';
    }
  }
}

final class _Op {
  _Op.insertMessage({
    required this.conversationId,
    required this.userId,
    required this.sentAt,
  })  : type = _OpType.insertMessage,
        readConvId = null;

  _Op.updateConversation({
    required this.conversationId,
    required this.sentAt,
  })  : type = _OpType.updateConversation,
        userId = null,
        readConvId = null;

  _Op.readMessages({required this.readConvId})
      : type = _OpType.readMessages,
        conversationId = null,
        userId = null,
        sentAt = null;

  _Op.readUser({required this.userId})
      : type = _OpType.readUser,
        conversationId = null,
        readConvId = null,
        sentAt = null;

  final _OpType type;
  final int? conversationId;
  final int? userId;
  final int? sentAt;
  final int? readConvId;
}

/// Build a deterministic list of ops. PRNG state depends only on [seed];
/// every peer receives an identical sequence.
List<_Op> _generateOpSequence({
  required int totalOps,
  required int userCount,
  required int conversationCount,
  required int seed,
}) {
  final prng = math.Random(seed);
  final zipf = _ZipfianSampler(conversationCount, _zipfExponent, seed);
  final ops = <_Op>[];

  // Running "time" counter so sent_at is monotonic-ish; doesn't need
  // to be real time for the workload, just unique.
  var clock = 0;

  for (var i = 0; i < totalOps; i++) {
    final roll = prng.nextInt(100);
    if (roll < 5) {
      // 5% insert
      ops.add(_Op.insertMessage(
        conversationId: zipf.sample() + 1,
        userId: prng.nextInt(userCount) + 1,
        sentAt: clock++,
      ));
    } else if (roll < 10) {
      // 5% update conversation
      ops.add(_Op.updateConversation(
        conversationId: zipf.sample() + 1,
        sentAt: clock++,
      ));
    } else if (roll < 55) {
      // 45% read messages
      ops.add(_Op.readMessages(readConvId: zipf.sample() + 1));
    } else {
      // 45% read user
      ops.add(_Op.readUser(userId: prng.nextInt(userCount) + 1));
    }
  }
  return ops;
}

/// Zipfian sampler: returns indices 0..n-1 with probability ∝ 1/(k+1)^s.
/// Precomputes the CDF once so each sample is a single log-n lookup.
final class _ZipfianSampler {
  _ZipfianSampler(int n, double s, int seed)
      : _rng = math.Random(seed ^ 0xBADBEEF),
        _cdf = _buildCdf(n, s);

  final math.Random _rng;
  final List<double> _cdf;

  int sample() {
    final r = _rng.nextDouble();
    // Binary search for first CDF entry >= r.
    var lo = 0;
    var hi = _cdf.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >>> 1;
      if (_cdf[mid] >= r) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  static List<double> _buildCdf(int n, double s) {
    final weights = List<double>.generate(n, (k) => 1.0 / math.pow(k + 1, s));
    final sum = weights.fold<double>(0, (a, b) => a + b);
    final cdf = List<double>.filled(n, 0);
    var acc = 0.0;
    for (var i = 0; i < n; i++) {
      acc += weights[i] / sum;
      cdf[i] = acc;
    }
    // Floating-point slop: force last entry to exactly 1.0.
    cdf[n - 1] = 1.0;
    return cdf;
  }
}

// ---------------------------------------------------------------------------
// Seed
// ---------------------------------------------------------------------------

Future<void> _seed(BenchmarkPeer peer) async {
  // IF NOT EXISTS because drift auto-creates tables + indexes from its
  // @DriftDatabase schema at open time; bare CREATE TABLE/INDEX would
  // throw "already exists" on the drift peer. The schema here must
  // match benchmark/drift/chat_sim_db.dart exactly.
  await peer.execute('CREATE TABLE IF NOT EXISTS users('
      'id INTEGER PRIMARY KEY, '
      'name TEXT NOT NULL, '
      'avatar_url TEXT NOT NULL)');
  await peer.execute('CREATE TABLE IF NOT EXISTS conversations('
      'id INTEGER PRIMARY KEY, '
      'last_msg_at INTEGER NOT NULL)');
  await peer.execute('CREATE TABLE IF NOT EXISTS messages('
      'id INTEGER PRIMARY KEY, '
      'conv_id INTEGER NOT NULL, '
      'sender_id INTEGER NOT NULL, '
      'body TEXT NOT NULL, '
      'sent_at INTEGER NOT NULL)');
  await peer.execute(
    'CREATE INDEX IF NOT EXISTS messages_conv_sent ON messages(conv_id, sent_at)',
  );

  // Seed users.
  await peer.executeBatch(
    'INSERT INTO users(name, avatar_url) VALUES (?, ?)',
    [
      for (var i = 1; i <= _userCount; i++)
        ['user_$i', 'https://example.com/avatars/$i.png'],
    ],
  );

  // Seed conversations.
  await peer.executeBatch(
    'INSERT INTO conversations(last_msg_at) VALUES (?)',
    [for (var i = 1; i <= _conversationCount; i++) [0]],
  );

  // Seed messages with Zipfian distribution over conversations.
  final zipf =
      _ZipfianSampler(_conversationCount, _zipfExponent, _prngSeed ^ 0xABC);
  final msgPrng = math.Random(_prngSeed ^ 0xDEF);
  await peer.executeBatch(
    'INSERT INTO messages(conv_id, sender_id, body, sent_at) VALUES (?, ?, ?, ?)',
    [
      for (var i = 1; i <= _seedMessageCount; i++)
        [
          zipf.sample() + 1,
          msgPrng.nextInt(_userCount) + 1,
          'seed_message_$i',
          i,
        ],
    ],
  );
}

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

Future<Map<_OpType, BenchmarkTiming>> _measure(
  BenchmarkPeer peer,
  List<_Op> ops,
) async {
  // Label is just the peer identifier — the per-op-type subsection on
  // the dashboard already tells readers which op they're looking at.
  // Parser compatibility: labels must start with `resqlite`/`sqlite3`/
  // `sqlite_async` so `parse_results.dart`'s `line.startsWith('| resqlite')`
  // branch matches for resqlite rows, and `generate_devices.dart`'s
  // library-name detection works for the others.
  final timings = <_OpType, BenchmarkTiming>{
    for (final t in _OpType.values)
      t: BenchmarkTiming(peer.label),
  };

  for (var i = 0; i < ops.length; i++) {
    final op = ops[i];
    final record = i >= _warmupOps ? timings[op.type]! : null;
    await _executeOp(peer, op, record);
  }

  return timings;
}

Future<void> _executeOp(
  BenchmarkPeer peer,
  _Op op,
  BenchmarkTiming? record,
) async {
  switch (op.type) {
    case _OpType.insertMessage:
      await _timeWrite(peer, record, () async {
        await peer.execute(
          'INSERT INTO messages(conv_id, sender_id, body, sent_at) '
          'VALUES (?, ?, ?, ?)',
          [
            op.conversationId,
            op.userId,
            'body_${op.sentAt}',
            op.sentAt,
          ],
        );
      });

    case _OpType.updateConversation:
      await _timeWrite(peer, record, () async {
        await peer.execute(
          'UPDATE conversations SET last_msg_at = ? WHERE id = ?',
          [op.sentAt, op.conversationId],
        );
      });

    case _OpType.readMessages:
      await _timeRead(peer, record, () => peer.select(
            'SELECT m.id, m.body, m.sent_at, u.name, u.avatar_url '
            'FROM messages m JOIN users u ON u.id = m.sender_id '
            'WHERE m.conv_id = ? '
            'ORDER BY m.sent_at DESC LIMIT 20',
            [op.readConvId],
          ));

    case _OpType.readUser:
      await _timeRead(peer, record, () => peer.select(
            'SELECT id, name, avatar_url FROM users WHERE id = ?',
            [op.userId],
          ));
  }
}

/// Time a write op. For sync peers, main == wall. For async peers,
/// main-isolate time is effectively zero (the await delivers an already-
/// completed future; no post-return consumption work).
Future<void> _timeWrite(
  BenchmarkPeer peer,
  BenchmarkTiming? record,
  Future<void> Function() op,
) async {
  if (record == null) {
    await op();
    return;
  }
  final sw = Stopwatch()..start();
  await op();
  sw.stop();
  if (peer.isSynchronous) {
    record.recordWallOnly(sw.elapsedMicroseconds);
  } else {
    record.record(
      wallMicroseconds: sw.elapsedMicroseconds,
      mainMicroseconds: 0,
    );
  }
}

/// Time a read op + consumer iteration. For sync peers, all the work
/// happens before await returns, so wall == main. For async peers, the
/// post-await iteration is the main-isolate cost.
Future<void> _timeRead(
  BenchmarkPeer peer,
  BenchmarkTiming? record,
  Future<List<Map<String, Object?>>> Function() op,
) async {
  if (record == null) {
    final r = await op();
    _consume(r);
    return;
  }
  final swWall = Stopwatch()..start();
  final result = await op();
  final wallFromDispatch = swWall.elapsedMicroseconds;
  final swMain = Stopwatch()..start();
  _consume(result);
  swMain.stop();
  swWall.stop();
  if (peer.isSynchronous) {
    record.recordWallOnly(swWall.elapsedMicroseconds);
  } else {
    record.record(
      wallMicroseconds: swWall.elapsedMicroseconds,
      mainMicroseconds: swMain.elapsedMicroseconds,
    );
    // Suppress unused_local_variable warning: wallFromDispatch captures
    // the dispatch-only moment for future diagnostic use if we ever
    // want to separate dispatch from post-return work. Unused today.
    // (Dart will complain if we actually annotate it; leave as-is.)
  }
  // ignore: unused_local_variable
  final _ = wallFromDispatch;
}

/// Touch every value in every row to force materialization / column
/// access. Same consumer all three peers see — fair comparison.
void _consume(List<Map<String, Object?>> rows) {
  for (final row in rows) {
    for (final v in row.values) {
      // Force the value to be observed. `row.values` iteration itself
      // is the materialization trigger on resqlite's lazy Row views.
      if (identical(v, v)) continue;
    }
  }
}

// ---------------------------------------------------------------------------
// Markdown output
// ---------------------------------------------------------------------------

void _writeResults(
  StringBuffer md,
  Map<String, Map<_OpType, BenchmarkTiming>> perPeerTimings,
) {
  // One subsection per op type so the parser creates separate metric
  // keys per op (natively handled by generate_devices.dart).
  for (final opType in _OpType.values) {
    md
      ..writeln('### ${opType.title}')
      ..writeln()
      ..writeln('| Library | Wall med (ms) | Wall p90 (ms) | '
          'Main med (ms) | Main p90 (ms) |')
      ..writeln('|---|---|---|---|---|');
    for (final entry in perPeerTimings.entries) {
      final timing = entry.value[opType]!;
      if (timing.wallUs.isEmpty) continue;
      md.writeln(
        '| ${timing.label} '
        '| ${timing.wall.medianMs.toStringAsFixed(3)} '
        '| ${timing.wall.p90Ms.toStringAsFixed(3)} '
        '| ${timing.main.medianMs.toStringAsFixed(3)} '
        '| ${timing.main.p90Ms.toStringAsFixed(3)} |',
      );
    }
    md.writeln();
  }
  md
    ..writeln('**Interpretation.** Each op type is timed independently. '
        'A library that dominates on one op type (e.g. reads) may lose '
        'on another (e.g. inserts under commit pressure). For '
        'Flutter-facing usage, the `Main med` column is the key number: '
        'it\'s the time spent on the UI thread per op.')
    ..writeln();
}

// Standalone entry.
Future<void> main() async {
  final md = await runChatSimBenchmark();
  print(md);
}
