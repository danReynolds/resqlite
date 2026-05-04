// ignore_for_file: avoid_print
//
// Writer-side dispatch-vs-native wall split audit — exp 123.
//
// Exp 119/120/121/122 closed the ReaderPool and StreamEngine admission
// paths. Every measured stream workload now reports
// `dispatcherParkedTotal == 0` and `dispatcherWakeRetryTotal == 0`. The
// future notes from those experiments pointed the next dispatch
// question off the read side and onto the writer:
//
//   What fraction of writer-isolate per-write wall is the FFI write
//   call itself (`resqliteExecute` / `resqliteRunBatch` / nested), and
//   what fraction is the surrounding Dart-side dispatch overhead
//   (parameter encoding, dirty-table FFI, reply marshalling)?
//
// `signals.json` lists this measurement explicitly under both
// `stream-rerun-dispatch.blockedOnMeasurement` ("writer-isolate wall
// vs SQLite wall split for overlap workloads") and
// `parameter-encoding-and-binding.blockedOnMeasurement` ("writer-
// isolate profile separating bind work from dispatch and step time").
// Until that split exists, dispatch-area implementation experiments
// are gated.
//
// This harness adds it. For each scenario the timed write loop runs
// against the same workload shapes exp 119/121 use (so writer wall is
// directly comparable), with two extra snapshots taken either side of
// the stopwatch:
//
//   - main-isolate `ProfileCounters` (already exists),
//   - writer-isolate `ProfileCounters.writer*` via the new
//     `Database.writerProfileSnapshot()` round-trip.
//
// Wall convention matches `audit_workloads.dart`: stopwatch stops on
// the last write, drains run after — so `wall_us` is writer-side burst
// wall, not denominator-padded with idle wait. The two writer snapshot
// round-trips are taken outside the stopwatch (the snapshot's own
// round-trip wall would otherwise inflate the denominator).
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/writer_dispatch_split_audit.dart --markdown

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';

// ---------------------------------------------------------------------------
// Shared workload constants — mirror `audit_workloads.dart` so wall
// numbers stay directly comparable to exp 119 / exp 121.
// ---------------------------------------------------------------------------

const int _a11cRowCount = 5000;
const int _a11cStreamCount = 50;
const int _a11cWriteCount = 500;
const int _keyedPkRowCount = 10000;
const int _keyedPkStreamCount = 50;
const int _keyedPkWriteCount = 200;
const int _keyedPkPrngSeed = 0xBEEF;

// Wide-batch workload — one BatchRequest carrying 10,000 rows of 20
// mixed-type parameters each. Mirrors the release-suite `Wide Batch
// Insert` shape exp 116 promoted, which the parameter-encoding
// direction (exp 109/112/113) already considers the relevant
// parameter-width signal. Single batch request keeps the Dart-side
// dispatch overhead per row tiny — making the native fraction the
// upper bound on what dispatch optimization can ever recover here.
const int _wideBatchRowCount = 10000;
const int _wideBatchParamCount = 20;

// ---------------------------------------------------------------------------
// Audit data structures
// ---------------------------------------------------------------------------

final class _ScenarioResult {
  _ScenarioResult({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.invalidateUs,
    required this.parkedTotal,
    required this.maxParked,
    required this.writerHandlerUs,
    required this.writerHandlerCount,
    required this.writerNativeUs,
    required this.writerNativeCount,
    required this.emissions,
  });

  final String workload;
  final String shape;
  final int wallUs;
  final int invalidateUs;
  final int parkedTotal;
  final int maxParked;
  final int writerHandlerUs;
  final int writerHandlerCount;
  final int writerNativeUs;
  final int writerNativeCount;
  final int emissions;

  double get wallMs => wallUs / 1000.0;

  /// `writer_handler_us / wall_us`. Hard upper bound on what writer-
  /// isolate dispatch optimization can save: anything outside
  /// `writer_handler` is main-isolate scheduling, in-flight reader
  /// work, or invalidation traversal — different optimization
  /// directions.
  double get writerHandlerFractionPct =>
      wallUs == 0 ? 0.0 : (writerHandlerUs / wallUs) * 100.0;

  /// `writer_native_us / writer_handler_us`. The "how much of the
  /// writer's own time is SQLite vs Dart" headline number. A high
  /// fraction means dispatch optimization buys little here; a low
  /// fraction means the Dart-side wrapper dominates.
  double get nativeOfHandlerPct => writerHandlerUs == 0
      ? 0.0
      : (writerNativeUs / writerHandlerUs) * 100.0;

  /// Writer-isolate dispatch overhead as a fraction of total wall —
  /// the part of wall_us that smarter writer-side dispatch could in
  /// principle eliminate. Same as
  /// `writer_handler_us / wall_us - writer_native_us / wall_us`.
  double get dispatchOverheadFractionPct => wallUs == 0
      ? 0.0
      : ((writerHandlerUs - writerNativeUs) / wallUs) * 100.0;

  double get usPerWriteHandler =>
      writerHandlerCount == 0 ? 0.0 : writerHandlerUs / writerHandlerCount;
  double get usPerWriteNative =>
      writerNativeCount == 0 ? 0.0 : writerNativeUs / writerNativeCount;
  double get usPerWriteDispatch => writerHandlerCount == 0
      ? 0.0
      : (writerHandlerUs - writerNativeUs) / writerHandlerCount;
}

// ---------------------------------------------------------------------------
// Snapshot helpers
// ---------------------------------------------------------------------------

Future<WriterProfileSnapshot> _resetWriter(Database db) =>
    db.writerProfileSnapshot(reset: true);

Future<WriterProfileSnapshot> _snapshotWriter(Database db) =>
    db.writerProfileSnapshot();

// ---------------------------------------------------------------------------
// Scenario runners
// ---------------------------------------------------------------------------

Future<_ScenarioResult> _runA11cScenario({
  required String name,
  required int streamCount,
  required String updateSql,
  required String Function(int writeIndex) valueFor,
}) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'writer_split_audit_a11c_${name.replaceAll(' ', '_')}_',
  );
  final db = await Database.open('${tempDir.path}/test.db');
  try {
    final colNames = _a11cColumnNames();
    final createSql =
        'CREATE TABLE wide(id INTEGER PRIMARY KEY, ' +
        colNames.map((c) => '$c TEXT NOT NULL').join(', ') +
        ')';
    final insertSql =
        'INSERT INTO wide(id, ${colNames.join(', ')}) '
        'VALUES (?, ${List.filled(colNames.length, '?').join(', ')})';
    await db.execute(createSql);
    await db.executeBatch(insertSql, [
      for (var i = 0; i < _a11cRowCount; i++)
        [i, for (final _ in colNames) 'v$i'],
    ]);

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
      await _resetWriter(db);
      final sw = Stopwatch()..start();
      for (var w = 0; w < _a11cWriteCount; w++) {
        await db.execute(updateSql, [valueFor(w), w % _a11cRowCount]);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      }
      sw.stop();
      final writerSnap = await _snapshotWriter(db);
      final mainSnap = ProfileCounters.snapshot();

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final emissions = emitCounts.fold<int>(0, (a, b) => a + b);

      return _ScenarioResult(
        workload: name,
        shape: '$streamCount streams x $_a11cWriteCount writes',
        wallUs: sw.elapsedMicroseconds,
        invalidateUs: mainSnap['invalidate_us']!,
        parkedTotal: mainSnap['dispatcher_parked_total']!,
        maxParked: mainSnap['dispatcher_max_parked_concurrent']!,
        writerHandlerUs: writerSnap.handlerUs,
        writerHandlerCount: writerSnap.handlerCount,
        writerNativeUs: writerSnap.nativeUs,
        writerNativeCount: writerSnap.nativeCount,
        emissions: emissions,
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

Future<_ScenarioResult> _runKeyedPkScenario() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'writer_split_audit_pk_',
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
    await db.executeBatch(
      'INSERT INTO items(body, updated_at) VALUES (?, ?)',
      [for (var i = 1; i <= _keyedPkRowCount; i++) ['seed_body_$i', 0]],
    );

    final watchedIds = _pickKeyedPkWatchedIds();
    final initials = <Completer<void>>[];
    final subscriptions = <StreamSubscription<List<Map<String, Object?>>>>[];
    final emitCounts = List<int>.filled(_keyedPkStreamCount, 0);
    for (var i = 0; i < _keyedPkStreamCount; i++) {
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

      final prng = math.Random(_keyedPkPrngSeed);

      ProfileCounters.reset();
      await _resetWriter(db);
      final sw = Stopwatch()..start();
      for (var w = 0; w < _keyedPkWriteCount; w++) {
        final pk = prng.nextInt(_keyedPkRowCount) + 1;
        await db.execute(
          'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
          ['body_$w', w, pk],
        );
      }
      sw.stop();
      final writerSnap = await _snapshotWriter(db);
      final mainSnap = ProfileCounters.snapshot();

      // Quiet-window drain so trailing emissions are counted, AFTER the
      // stopwatch and snapshots so they don't pad the denominator.
      var lastEmissions = emitCounts.fold<int>(0, (a, b) => a + b);
      const quietWindow = Duration(milliseconds: 200);
      final quietDeadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(quietDeadline)) {
        await Future<void>.delayed(quietWindow);
        final nowEmissions = emitCounts.fold<int>(0, (a, b) => a + b);
        if (nowEmissions == lastEmissions) break;
        lastEmissions = nowEmissions;
      }

      return _ScenarioResult(
        workload: 'keyed PK subscriptions',
        shape: '$_keyedPkStreamCount streams x $_keyedPkWriteCount random writes',
        wallUs: sw.elapsedMicroseconds,
        invalidateUs: mainSnap['invalidate_us']!,
        parkedTotal: mainSnap['dispatcher_parked_total']!,
        maxParked: mainSnap['dispatcher_max_parked_concurrent']!,
        writerHandlerUs: writerSnap.handlerUs,
        writerHandlerCount: writerSnap.handlerCount,
        writerNativeUs: writerSnap.nativeUs,
        writerNativeCount: writerSnap.nativeCount,
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

Future<_ScenarioResult> _runWideBatchScenario() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'writer_split_audit_batch_',
  );
  final db = await Database.open('${tempDir.path}/test.db');
  try {
    final colDefs = <String>[];
    for (var i = 0; i < _wideBatchParamCount; i++) {
      // Mixed types — text, int, real — to mirror the release wide-batch
      // shape promoted in exp 116. The batch encoder takes a different
      // path per type, so a single-type batch would understate per-row
      // dispatch cost.
      final type = switch (i % 3) {
        0 => 'TEXT',
        1 => 'INTEGER',
        _ => 'REAL',
      };
      colDefs.add('c$i $type');
    }
    final insertCols = [for (var i = 0; i < _wideBatchParamCount; i++) 'c$i'];
    final placeholders = List.filled(_wideBatchParamCount, '?').join(', ');
    await db.execute(
      'CREATE TABLE wide_batch(id INTEGER PRIMARY KEY, ${colDefs.join(', ')})',
    );

    final paramSets = <List<Object?>>[
      for (var row = 0; row < _wideBatchRowCount; row++)
        [
          for (var i = 0; i < _wideBatchParamCount; i++)
            switch (i % 3) {
              0 => 'value_${row}_$i',
              1 => row * 31 + i,
              _ => (row + i) * 1.5,
            },
        ],
    ];

    ProfileCounters.reset();
    await _resetWriter(db);
    final sw = Stopwatch()..start();
    await db.executeBatch(
      'INSERT INTO wide_batch(${insertCols.join(', ')}) VALUES ($placeholders)',
      paramSets,
    );
    sw.stop();
    final writerSnap = await _snapshotWriter(db);
    final mainSnap = ProfileCounters.snapshot();

    return _ScenarioResult(
      workload: 'wide batch insert',
      shape:
          '1 batch x $_wideBatchRowCount rows x $_wideBatchParamCount params',
      wallUs: sw.elapsedMicroseconds,
      invalidateUs: mainSnap['invalidate_us']!,
      parkedTotal: mainSnap['dispatcher_parked_total']!,
      maxParked: mainSnap['dispatcher_max_parked_concurrent']!,
      writerHandlerUs: writerSnap.handlerUs,
      writerHandlerCount: writerSnap.handlerCount,
      writerNativeUs: writerSnap.nativeUs,
      writerNativeCount: writerSnap.nativeCount,
      emissions: 0,
    );
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<String> _a11cColumnNames() => [
  for (var i = 0; i < 20; i++) String.fromCharCode('a'.codeUnitAt(0) + i),
];

List<int> _pickKeyedPkWatchedIds() {
  final step = _keyedPkRowCount ~/ _keyedPkStreamCount;
  return [for (var i = 0; i < _keyedPkStreamCount; i++) (i * step) + 1];
}

int _readerPoolSize() => (Platform.numberOfProcessors - 1).clamp(2, 4);

// ---------------------------------------------------------------------------
// Entry point + reporting
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; writer-side counters will stay zero. '
      'Rerun with -DRESQLITE_PROFILE=true.',
    );
  }

  final writeMarkdown = args.contains('--markdown');

  final rows = <_ScenarioResult>[];
  rows.add(
    await _runA11cScenario(
      name: 'A11c baseline',
      streamCount: 0,
      updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
      valueFor: (writeIndex) => 'b$writeIndex',
    ),
  );
  rows.add(
    await _runA11cScenario(
      name: 'A11c disjoint',
      streamCount: _a11cStreamCount,
      updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
      valueFor: (writeIndex) => 'd$writeIndex',
    ),
  );
  rows.add(
    await _runA11cScenario(
      name: 'A11c overlap',
      streamCount: _a11cStreamCount,
      updateSql: 'UPDATE wide SET a = ? WHERE id = ?',
      valueFor: (writeIndex) => 'o$writeIndex',
    ),
  );
  rows.add(await _runKeyedPkScenario());
  rows.add(await _runWideBatchScenario());

  final markdown = _renderMarkdown(rows);
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-123-writer-dispatch-split-aggregate.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

String _renderMarkdown(List<_ScenarioResult> rows) {
  final readerCount = _readerPoolSize();
  final buf = StringBuffer();
  buf.writeln('# Experiment 123 - Writer Dispatch / Native Wall Split');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/writer_dispatch_split_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  buf.writeln();
  buf.writeln(
    'Wall-clock convention: `wall_us` is writer-side burst wall — the '
    'stopwatch stops on the last write. The `writerProfileSnapshot()` '
    'round-trip and emission drains run after the stopwatch so the '
    'denominator is not padded with idle waiting.',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/writer_dispatch_split_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | writer_handler_us | writer_handler_count | '
    'writer_native_us | writer_native_count | invalidate_us | parked_total | '
    'max_parked | emissions |',
  );
  buf.writeln(
    '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.writerHandlerUs} | ${row.writerHandlerCount} | '
      '${row.writerNativeUs} | ${row.writerNativeCount} | '
      '${row.invalidateUs} | ${row.parkedTotal} | ${row.maxParked} | '
      '${row.emissions} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived fractions');
  buf.writeln();
  buf.writeln(
    '| workload | writer_handler / wall | native / handler | '
    'dispatch overhead / wall | us per write (handler) | '
    'us per write (native) | us per write (dispatch) |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | '
      '${row.writerHandlerFractionPct.toStringAsFixed(2)}% | '
      '${row.nativeOfHandlerPct.toStringAsFixed(2)}% | '
      '${row.dispatchOverheadFractionPct.toStringAsFixed(2)}% | '
      '${row.usPerWriteHandler.toStringAsFixed(2)} | '
      '${row.usPerWriteNative.toStringAsFixed(2)} | '
      '${row.usPerWriteDispatch.toStringAsFixed(2)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `wall_us` is writer-side burst wall (main isolate stopwatch, '
    'stops on the last write).',
  );
  buf.writeln(
    '- `writer_handler_us` is the cumulative writer-isolate wall spent '
    'inside `_handleExecute` + `_handleBatch` bodies — message receive '
    'through reply send, including parameter encoding, the FFI write '
    'call, dirty-table extraction, and reply marshalling.',
  );
  buf.writeln(
    '- `writer_native_us` is the subset spent specifically inside the '
    'FFI write call (`resqliteExecute` / `resqliteRunBatch` / '
    '`resqliteRunBatchNested`) — i.e. SQLite-side prepare/bind/step/'
    'reset/commit work plus the FFI crossing itself.',
  );
  buf.writeln(
    '- `native / handler` is the headline split: how much of the '
    'writer\'s own time is SQLite. A value near 100% means writer-side '
    'dispatch optimization can buy little (the FFI call dominates); a '
    'value well below 100% means the Dart-side wrapper is a target.',
  );
  buf.writeln(
    '- `writer_handler / wall` is the structural ceiling on how much '
    'main-isolate wall the writer can ever explain. The remainder '
    '(`1 - handler/wall`) is main-isolate scheduling, in-flight reader '
    'fan-out, invalidation traversal, and the round-trip the request/'
    'reply messages take through Dart\'s isolate ports.',
  );
  buf.writeln(
    '- `parked_total` and `max_parked` should both stay at zero post-'
    'exp-120/122. Reproducing that is a sanity check that the workload '
    'is hitting the shapes exp 119 / exp 121 measured.',
  );
  buf.writeln();
  buf.writeln('## Interpretation');
  buf.writeln();
  buf.writeln(
    'See `experiments/123-writer-dispatch-step-split.md` for the decision '
    'and follow-up notes attached to these numbers.',
  );
  return buf.toString();
}
