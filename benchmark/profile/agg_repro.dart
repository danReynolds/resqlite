// Replicates the equivalence harness write generator exactly (seed-driven)
// with a configurable subset of its streams, to isolate which stream
// interaction lets the global COUNT(*) drift.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:resqlite/resqlite.dart';

Future<void> main(List<String> args) async {
  final seed = int.parse(args[0]);
  final streamSet = args[1]; // 'count' | 'aggpair' | 'all'
  final dir = await Directory.systemTemp.createTemp('agg_repro_');
  final db = await Database.open('${dir.path}/t.db');
  await db.execute(
      'CREATE TABLE msgs(id INTEGER PRIMARY KEY, conv INTEGER NOT NULL, '
      'score INTEGER, body TEXT NOT NULL, kind TEXT NOT NULL)');
  final prng = math.Random(seed);
  var nextId = 1;
  await db.executeBatch(
      'INSERT INTO msgs(id, conv, score, body, kind) VALUES (?, ?, ?, ?, ?)',
      [
        for (; nextId <= 60; nextId++)
          [nextId, nextId % 6, prng.nextBool() ? null : prng.nextInt(1000),
           'b$nextId', nextId % 3 == 0 ? 'pin' : 'note']
      ]);

  final sqls = <(String, String, List<Object?>)>[
    ('global count', 'SELECT COUNT(*) AS n FROM msgs', const []),
    if (streamSet != 'count')
      ('aggregates',
       'SELECT COUNT(*) AS n, SUM(score) AS total, MIN(score) AS lo, '
       'MAX(score) AS hi, AVG(score) AS mean FROM msgs WHERE conv = ?', [2]),
    if (streamSet == 'all') ...[
      ('full range',
       'SELECT id, conv, score FROM msgs WHERE id >= ? AND id < ? ORDER BY id',
       [10, 40]),
      ('windowed feed',
       'SELECT id, score FROM msgs WHERE conv = ? ORDER BY score DESC, id DESC LIMIT 5',
       [2]),
      ('windowed asc', 'SELECT id, conv FROM msgs ORDER BY conv, id LIMIT 7',
       const []),
      ('skip pane',
       'SELECT id, body FROM msgs WHERE conv = ? ORDER BY score DESC LIMIT 4',
       [3]),
      ('text eq', "SELECT id, kind FROM msgs WHERE kind = 'pin' ORDER BY id",
       const []),
      ('control',
       'SELECT conv, COUNT(*) AS n FROM msgs WHERE id > 0 GROUP BY conv ORDER BY conv',
       const []),
    ],
  ];
  final emissions = {for (final s in sqls) s.$1: <List<Map<String, Object?>>>[]};
  final subs = [
    for (final s in sqls)
      db.stream(s.$2, s.$3).listen((r) => emissions[s.$1]!.add(r)),
  ];
  await Future<void>.delayed(const Duration(milliseconds: 200));

  final liveIds = List<int>.generate(60, (i) => i + 1);
  Future<void> oneWrite() async {
    final roll = prng.nextInt(100);
    if (roll < 35 || liveIds.isEmpty) {
      final id = nextId++;
      liveIds.add(id);
      await db.execute(
          'INSERT INTO msgs(id, conv, score, body, kind) VALUES (?, ?, ?, ?, ?)',
          [id, prng.nextInt(6), prng.nextBool() ? null : prng.nextInt(1000),
           'b$id', prng.nextBool() ? 'pin' : 'note']);
    } else if (roll < 65) {
      final id = liveIds[prng.nextInt(liveIds.length)];
      await db.execute(
          'UPDATE msgs SET conv = ?, score = ?, kind = ? WHERE id = ?',
          [prng.nextInt(6), prng.nextBool() ? null : prng.nextInt(1000),
           prng.nextBool() ? 'pin' : 'note', id]);
    } else if (roll < 80) {
      final id = liveIds.removeAt(prng.nextInt(liveIds.length));
      await db.execute('DELETE FROM msgs WHERE id = ?', [id]);
    } else if (roll < 90) {
      final idx = prng.nextInt(liveIds.length);
      final oldId = liveIds[idx];
      final newId = nextId++;
      liveIds[idx] = newId;
      await db.execute('UPDATE msgs SET id = ? WHERE id = ?', [newId, oldId]);
    } else if (roll < 96) {
      await db.transaction((tx) async {
        final id = nextId++;
        liveIds.add(id);
        await tx.execute(
            "INSERT INTO msgs(id, conv, score, body, kind) VALUES (?, ?, ?, ?, 'note')",
            [id, prng.nextInt(6), prng.nextInt(1000), 'tx$id']);
        if (prng.nextBool()) {
          try {
            await tx.transaction((tx2) async {
              await tx2.execute('UPDATE msgs SET score = 777777 WHERE id = ?',
                  [liveIds[prng.nextInt(liveIds.length)]]);
              throw StateError('undo');
            });
          } on StateError {/**/}
        }
      });
    } else {
      final base = nextId;
      nextId += 300;
      liveIds.addAll([for (var i = base; i < base + 300; i++) i]);
      await db.executeBatch(
          "INSERT INTO msgs(id, conv, score, body, kind) VALUES (?, ?, ?, ?, 'note')",
          [for (var i = base; i < base + 300; i++) [i, i % 6, i % 7 == 0 ? null : i, 'bulk$i']]);
    }
  }

  Future<void> settle() async {
    int total() => emissions.values.fold(0, (a, l) => a + l.length);
    var last = total(); var quiet = 0;
    while (quiet < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final now = total();
      if (now == last) { quiet++; } else { quiet = 0; last = now; }
    }
  }

  for (var round = 0; round < 12; round++) {
    for (var w = 0; w < 18; w++) { await oneWrite(); }
    await settle();
    final truth = (await db.select('SELECT COUNT(*) AS n FROM msgs'))[0]['n'];
    final got = emissions['global count']!.last[0]['n'];
    if (got != truth) {
      print('seed $seed [$streamSet] DIVERGED round $round: got=$got truth=$truth');
      exit(1);
    }
  }
  print('seed $seed [$streamSet] OK');
  for (final s in subs) { await s.cancel(); }
  await db.close();
  await dir.delete(recursive: true);
  exit(0);
}
