// EXP-256: when a write races a stream's initial query, should the stream emit
// the known-stale initial rows immediately and correct itself, or wait and emit
// only the corrected result?
//
// Lane B shipped, so this harness measures it directly. To reproduce lane A,
// replace the poisoned-baseline branch in `StreamEngine._createStream` with a
// plain `entry.emit(initialRows)` before the re-query enqueue.
//
// The decision metric is NOT time-to-first-emission — lane A wins that by
// construction, by emitting data it already knows is superseded. What matters
// is time-to-CORRECT-value (when the subscriber can trust what it sees) and
// how many stale frames a UI renders before then.
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _samples = 12;
const _writes = 8;

double _median(List<double> xs) {
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

double _p90(List<double> xs) {
  final s = [...xs]..sort();
  return s[(0.9 * (s.length - 1)).round()];
}

class _Obs {
  double? firstMs;
  double? correctMs;
  int emissions = 0;
  int staleEmissions = 0;
}

/// One observation: open a stream over [seedRows] rows, fire [_writes] inserts
/// without awaiting the first emission (so they race the initial query), and
/// record when the subscriber first sees anything and first sees the truth.
Future<_Obs> _observe(Database db, int seedRows, {required bool race}) async {
  final expected = seedRows + _writes;
  final obs = _Obs();
  final done = Completer<void>();
  final sw = Stopwatch()..start();

  final sub = db.stream('SELECT id, name FROM items').listen((rows) {
    final t = sw.elapsedMicroseconds / 1000.0;
    obs.emissions++;
    obs.firstMs ??= t;
    if (rows.length != expected) obs.staleEmissions++;
    if (rows.length == expected && obs.correctMs == null) {
      obs.correctMs = t;
      if (!done.isCompleted) done.complete();
    }
  });

  if (!race) {
    // Control: let the stream register and emit before writing at all.
    while (obs.emissions == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }
  await Future.wait([
    for (var i = 0; i < _writes; i++)
      db.execute('INSERT INTO items(name) VALUES (?)', ['w_$i']),
  ]);

  await done.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () => throw StateError('never reached the correct value'),
  );
  await sub.cancel();
  await db.execute('DELETE FROM items WHERE name LIKE ?', ['w_%']);
  return obs;
}

Future<void> main() async {
  const lane = 'B suppress-stale (shipped)';
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp256-');
  final db = await Database.open('${tmp.path}/s.db');
  await db.execute('CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT)');

  stdout.writeln(
    '| lane | shape | first emit ms | correct ms (p50/p90) | emissions | stale frames |',
  );
  stdout.writeln('|---|---|---:|---:|---:|---:|');

  for (final (label, seed, race) in [
    ('racing · 1k rows', 1000, true),
    ('racing · 20k rows', 20000, true),
    ('racing · 60k rows', 60000, true),
    ('no race · 20k rows (control)', 20000, false),
  ]) {
    await db.execute('DELETE FROM items');
    await db.executeBatch('INSERT INTO items(name) VALUES (?)', [
      for (var i = 0; i < seed; i++) ['seed_$i'],
    ]);

    // Warm the pool and statement caches.
    for (var w = 0; w < 3; w++) {
      await _observe(db, seed, race: race);
    }

    final firsts = <double>[], corrects = <double>[];
    var emissions = 0, stale = 0;
    for (var i = 0; i < _samples; i++) {
      final o = await _observe(db, seed, race: race);
      firsts.add(o.firstMs!);
      corrects.add(o.correctMs!);
      emissions += o.emissions;
      stale += o.staleEmissions;
    }
    stdout.writeln(
      '| $lane | $label | ${_median(firsts).toStringAsFixed(1)} '
      '| ${_median(corrects).toStringAsFixed(1)} / ${_p90(corrects).toStringAsFixed(1)} '
      '| ${(emissions / _samples).toStringAsFixed(2)} '
      '| ${(stale / _samples).toStringAsFixed(2)} |',
    );
  }

  await db.close();
  await tmp.delete(recursive: true);
}
