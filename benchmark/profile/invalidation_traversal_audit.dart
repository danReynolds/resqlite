// ignore_for_file: avoid_print
//
// Invalidation-traversal cost audit — exp 121.
//
// Exp 120 closed the over-dispatch path inside `StreamEngine._flushQueue`
// and dropped `dispatcherParkedTotal` / `dispatcherMaxParkedConcurrent`
// to zero on every measured stream workload. That moved the next
// dispatch-area question off ReaderPool admission and onto the
// remaining wall-time sources called out in exp 120's future notes:
// completion-side churn, write-side dispatch, and *invalidation
// traversal* — the last of which already has counters
// (`ProfileCounters.invalidateUs` / `intersectionUs`) but had not been
// audited as a fraction of overlap wall.
//
// This harness asks one question:
//
//   What fraction of A11c overlap (and keyed-PK) wall time is the
//   synchronous body of `StreamEngine.onDependencyChanges`?
//
// If the fraction is small, future dispatch work should branch toward
// completion-side churn or writer-side dispatch instead of column-set
// intersection or `_tableIndex` lookup. If it is large, the cost is
// where signals.json hinted.
//
// Workload shapes mirror exp 119's `dispatch_pressure_audit.dart` so
// the two reports are directly comparable.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/invalidation_traversal_audit.dart --markdown

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';

const int _a11cRowCount = 5000;
const int _a11cStreamCount = 50;
const int _a11cWriteCount = 500;

const int _keyedRowCount = 10000;
const int _keyedStreamCount = 50;
const int _keyedWriteCount = 200;
const int _keyedPrngSeed = 0xBEEF;

final class _AuditRow {
  _AuditRow({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.invalidateUs,
    required this.invalidateCount,
    required this.intersectionUs,
    required this.intersectionEntries,
    required this.parkedTotal,
    required this.maxParked,
    required this.emissions,
  });

  final String workload;
  final String shape;
  final int wallUs;
  final int invalidateUs;
  final int invalidateCount;
  final int intersectionUs;
  final int intersectionEntries;
  final int parkedTotal;
  final int maxParked;
  final int emissions;

  double get wallMs => wallUs / 1000.0;
  double get invalidateFractionPct =>
      wallUs == 0 ? 0.0 : (invalidateUs / wallUs) * 100.0;
  double get intersectionFractionPct =>
      wallUs == 0 ? 0.0 : (intersectionUs / wallUs) * 100.0;
  double get usPerWrite =>
      invalidateCount == 0 ? 0.0 : invalidateUs / invalidateCount;
  double get nsPerEntry => intersectionEntries == 0
      ? 0.0
      : (intersectionUs * 1000.0) / intersectionEntries;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; invalidation counters will stay zero. '
      'Rerun with -DRESQLITE_PROFILE=true.',
    );
  }

  final writeMarkdown = args.contains('--markdown');

  final rows = <_AuditRow>[];
  rows.addAll(await _runA11cAudit());
  rows.add(await _runKeyedPkAudit());

  final markdown = _renderMarkdown(rows);
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-121-invalidation-traversal-aggregate.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<List<_AuditRow>> _runA11cAudit() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'invalidation_audit_a11c_',
  );
  final db = await Database.open('${tempDir.path}/test.db');
  final colNames = [
    for (var i = 0; i < 20; i++) String.fromCharCode('a'.codeUnitAt(0) + i),
  ];
  final createSql =
      'CREATE TABLE wide(id INTEGER PRIMARY KEY, ' +
      colNames.map((c) => '$c TEXT NOT NULL').join(', ') +
      ')';
  final insertSql =
      'INSERT INTO wide(id, ${colNames.join(', ')}) '
      'VALUES (?, ${List.filled(colNames.length, '?').join(', ')})';

  try {
    await db.execute(createSql);
    await db.executeBatch(insertSql, [
      for (var i = 0; i < _a11cRowCount; i++)
        [i, for (final _ in colNames) 'v$i'],
    ]);

    return [
      await _runA11cScenario(
        db,
        name: 'A11c baseline',
        streamCount: 0,
        updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
        valueFor: (writeIndex) => 'b$writeIndex',
      ),
      await _runA11cScenario(
        db,
        name: 'A11c disjoint',
        streamCount: _a11cStreamCount,
        updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
        valueFor: (writeIndex) => 'd$writeIndex',
      ),
      await _runA11cScenario(
        db,
        name: 'A11c overlap',
        streamCount: _a11cStreamCount,
        updateSql: 'UPDATE wide SET a = ? WHERE id = ?',
        valueFor: (writeIndex) => 'o$writeIndex',
      ),
    ];
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<_AuditRow> _runA11cScenario(
  Database db, {
  required String name,
  required int streamCount,
  required String updateSql,
  required String Function(int writeIndex) valueFor,
}) async {
  final initials = <Completer<void>>[];
  final subscriptions = <StreamSubscription<List<Map<String, Object?>>>>[];
  final emitCounts = List<int>.filled(streamCount, 0);

  for (var i = 0; i < streamCount; i++) {
    final idx = i;
    final initial = Completer<void>();
    initials.add(initial);
    final partWidth = _a11cRowCount ~/ streamCount;
    final partStart = idx * partWidth;
    final partEnd = partStart + partWidth;
    subscriptions.add(
      db
          .stream(
            'SELECT id, a, b FROM wide WHERE id >= ? AND id < ? ORDER BY id',
            [partStart, partEnd],
          )
          .listen((_) {
            if (!initial.isCompleted) {
              initial.complete();
            } else {
              emitCounts[idx]++;
            }
          }),
    );
  }

  try {
    if (streamCount > 0) {
      await Future.wait(
        initials.map((c) => c.future),
      ).timeout(const Duration(seconds: 60));
    }

    ProfileCounters.reset();
    final sw = Stopwatch()..start();
    for (var w = 0; w < _a11cWriteCount; w++) {
      await db.execute(updateSql, [valueFor(w), w % _a11cRowCount]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    sw.stop();

    final emissions = emitCounts.fold<int>(0, (a, b) => a + b);
    return _rowFromCounters(
      workload: name,
      shape: '$streamCount streams x $_a11cWriteCount writes',
      wallUs: sw.elapsedMicroseconds,
      emissions: emissions,
    );
  } finally {
    for (final sub in subscriptions) {
      await sub.cancel();
    }
  }
}

Future<_AuditRow> _runKeyedPkAudit() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'invalidation_audit_pk_',
  );
  final db = await Database.open('${tempDir.path}/test.db');
  try {
    await db.execute(
      'CREATE TABLE items('
      'id INTEGER PRIMARY KEY, '
      'body TEXT NOT NULL, '
      'updated_at INTEGER NOT NULL'
      ')',
    );
    await db.executeBatch('INSERT INTO items(body, updated_at) VALUES (?, ?)', [
      for (var i = 1; i <= _keyedRowCount; i++) ['seed_body_$i', 0],
    ]);

    final watchedIds = _pickWatchedIds();
    final initials = <Completer<void>>[];
    final subscriptions = <StreamSubscription<List<Map<String, Object?>>>>[];
    final emitCounts = List<int>.filled(_keyedStreamCount, 0);
    for (var i = 0; i < _keyedStreamCount; i++) {
      final idx = i;
      final initial = Completer<void>();
      initials.add(initial);
      subscriptions.add(
        db
            .stream('SELECT id, body, updated_at FROM items WHERE id = ?', [
              watchedIds[i],
            ])
            .listen((_) {
              if (!initial.isCompleted) {
                initial.complete();
              } else {
                emitCounts[idx]++;
              }
            }),
      );
    }

    try {
      await Future.wait(
        initials.map((c) => c.future),
      ).timeout(const Duration(seconds: 60));

      final prng = math.Random(_keyedPrngSeed);

      ProfileCounters.reset();
      final sw = Stopwatch()..start();
      for (var w = 0; w < _keyedWriteCount; w++) {
        final pk = prng.nextInt(_keyedRowCount) + 1;
        await db.execute(
          'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
          ['body_$w', w, pk],
        );
      }

      var lastEmissions = emitCounts.fold<int>(0, (a, b) => a + b);
      const quietWindow = Duration(milliseconds: 200);
      final quietDeadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(quietDeadline)) {
        await Future<void>.delayed(quietWindow);
        final nowEmissions = emitCounts.fold<int>(0, (a, b) => a + b);
        if (nowEmissions == lastEmissions) break;
        lastEmissions = nowEmissions;
      }
      sw.stop();

      return _rowFromCounters(
        workload: 'keyed PK subscriptions',
        shape:
            '$_keyedStreamCount streams x $_keyedWriteCount random writes',
        wallUs: sw.elapsedMicroseconds,
        emissions: lastEmissions,
      );
    } finally {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    }
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

List<int> _pickWatchedIds() {
  final step = _keyedRowCount ~/ _keyedStreamCount;
  return [for (var i = 0; i < _keyedStreamCount; i++) (i * step) + 1];
}

_AuditRow _rowFromCounters({
  required String workload,
  required String shape,
  required int wallUs,
  int emissions = 0,
}) {
  final counters = ProfileCounters.snapshot();
  return _AuditRow(
    workload: workload,
    shape: shape,
    wallUs: wallUs,
    invalidateUs: counters['invalidate_us']!,
    invalidateCount: counters['invalidate_count']!,
    intersectionUs: counters['intersection_us']!,
    intersectionEntries: counters['intersection_entries']!,
    parkedTotal: counters['dispatcher_parked_total']!,
    maxParked: counters['dispatcher_max_parked_concurrent']!,
    emissions: emissions,
  );
}

String _renderMarkdown(List<_AuditRow> rows) {
  final readerCount = _readerPoolSize();
  final buf = StringBuffer();
  buf.writeln('# Experiment 121 - Invalidation Traversal Audit');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/invalidation_traversal_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/invalidation_traversal_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | invalidate_us | invalidate_count | '
    'intersection_us | intersection_entries | parked_total | max_parked | emissions |',
  );
  buf.writeln(
    '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.invalidateUs} | ${row.invalidateCount} | '
      '${row.intersectionUs} | ${row.intersectionEntries} | '
      '${row.parkedTotal} | ${row.maxParked} | ${row.emissions} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived fractions');
  buf.writeln();
  buf.writeln(
    '| workload | invalidate_us / wall_ms | intersection_us / wall_ms | '
    'us per write | ns per intersection entry |',
  );
  buf.writeln('|---|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | '
      '${row.invalidateFractionPct.toStringAsFixed(2)}% | '
      '${row.intersectionFractionPct.toStringAsFixed(2)}% | '
      '${row.usPerWrite.toStringAsFixed(2)} | '
      '${row.nsPerEntry.toStringAsFixed(0)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `invalidate_us` is the cumulative wall-clock microseconds spent in '
    'the synchronous body of `StreamEngine.onDependencyChanges` — '
    '`_tableIndex` lookup, per-entry column intersection probes, dirty/'
    'in-flight scheduling, and the synchronous portion of '
    '`_flushQueue` that admits stream re-queries before any await hop.',
  );
  buf.writeln(
    '- `intersection_us` is the subset spent specifically inside '
    '`entryCols.intersects(changedCols)` calls. Their ratio (intersection_us / '
    'invalidate_us) shows how much of invalidation cost is column-set '
    'intersection versus the rest of the traversal (lookup, scheduling, '
    'flush bookkeeping).',
  );
  buf.writeln(
    '- `invalidate_us / wall_ms` is the fraction of total workload wall '
    'attributable to writer-side invalidation traversal. A11c overlap is '
    'the workload exp 119/120 flagged as the next signal source; if that '
    'fraction is small, future dispatch work should branch off invalidation '
    'and toward completion-side or writer-side wall.',
  );
  buf.writeln(
    '- `parked_total` and `max_parked` should both stay at zero post-exp-120, '
    'reproducing exp 120\'s acceptance signal as a sanity check.',
  );
  buf.writeln();
  buf.writeln('## Interpretation');
  buf.writeln();
  buf.writeln(
    'See `experiments/121-invalidation-traversal-audit.md` for the decision '
    'and follow-up notes attached to these numbers.',
  );
  return buf.toString();
}

int _readerPoolSize() => (Platform.numberOfProcessors - 1).clamp(2, 4);
