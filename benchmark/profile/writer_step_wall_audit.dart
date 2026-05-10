// ignore_for_file: avoid_print
//
// Writer-isolate dispatch wall vs SQLite step wall audit — exp 135.
//
// Exp 120 closed the over-dispatch path inside `StreamEngine._flushQueue`
// and dropped reader-pool dispatcher counters to zero on every measured
// stream workload. Exp 121 then read the existing invalidation counters
// against the corrected wall convention and ruled invalidation
// traversal off the candidate list as a wall-time target.
//
// Both follow-up dispatch ideas in exp 120's future-notes are blocked
// on writer-isolate measurement infrastructure that exp 121 explicitly
// flagged in `signals.json`:
//
//   - completion-side microtask scheduling cost counter
//   - writer dispatch wall counter (dart wall - SQLite step wall)
//
// This experiment ships the second one: profile-mode counters inside
// the writer isolate that record per-handler wall time and the wall
// time spent inside the FFI calls that drive SQLite (`resqliteExecute`,
// `resqliteRunBatch`, `resqliteRunBatchNested`, the transaction-control
// stmts, and the step+decode part of `_handleTxQuery`). The harness
// reads them through `Database.snapshotWriterProfileCounters()`.
//
// One question:
//
//   What fraction of the writer-isolate handler wall is SQLite step
//   work versus Dart-side dispatch on A11c overlap and keyed-PK
//   subscriptions?
//
// If the SQLite-step share is high (≥ ~70%), writer-side dispatch is
// not the next dispatch experiment target on the currently-measured
// workloads. If it is low (≤ ~50%), there is real Dart-dispatch
// headroom and the next dispatch experiment in `stream-rerun-dispatch`
// can target it directly.
//
// Workload shapes mirror exp 119/121 via `audit_workloads.dart` so
// fractions reported here line up structurally with the prior audits.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/writer_step_wall_audit.dart --markdown

import 'dart:io';

import 'package:resqlite/src/profile_mode.dart';

import 'audit_workloads.dart';

final class _AuditRow {
  _AuditRow({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.handlerUs,
    required this.sqliteUs,
    required this.handlerCount,
    required this.parkedTotal,
    required this.maxParked,
    required this.emissions,
  });

  factory _AuditRow.fromScenario(AuditScenarioResult r) => _AuditRow(
    workload: r.workload,
    shape: r.shape,
    wallUs: r.wallUs,
    handlerUs: r.counters['writer_handler_us'] ?? 0,
    sqliteUs: r.counters['writer_sqlite_us'] ?? 0,
    handlerCount: r.counters['writer_handler_count'] ?? 0,
    parkedTotal: r.counters['dispatcher_parked_total'] ?? 0,
    maxParked: r.counters['dispatcher_max_parked_concurrent'] ?? 0,
    emissions: r.emissions,
  );

  final String workload;
  final String shape;
  final int wallUs;
  final int handlerUs;
  final int sqliteUs;
  final int handlerCount;
  final int parkedTotal;
  final int maxParked;
  final int emissions;

  // `handlerUs` and `sqliteUs` come from independently-running
  // stopwatches inside the writer isolate, so a marginal handler that
  // happens to nest entirely inside its `_measureSqlite` call could
  // briefly produce `sqliteUs > handlerUs` from clock-resolution
  // rounding. Clamp at zero so the derived fractions and the rendered
  // markdown never report a negative dispatch share — a value < 0 would
  // be a measurement artifact rather than a real signal.
  int get dispatchUs => handlerUs > sqliteUs ? handlerUs - sqliteUs : 0;
  double get wallMs => wallUs / 1000.0;
  double get handlerFractionPct =>
      wallUs == 0 ? 0.0 : (handlerUs / wallUs) * 100.0;
  double get sqliteFractionPct =>
      wallUs == 0 ? 0.0 : (sqliteUs / wallUs) * 100.0;
  double get dispatchFractionPct =>
      wallUs == 0 ? 0.0 : (dispatchUs / wallUs) * 100.0;
  double get sqliteFractionOfHandlerPct =>
      handlerUs == 0 ? 0.0 : (sqliteUs / handlerUs) * 100.0;
  double get usPerHandler =>
      handlerCount == 0 ? 0.0 : handlerUs / handlerCount;
  double get sqliteUsPerHandler =>
      handlerCount == 0 ? 0.0 : sqliteUs / handlerCount;
  double get dispatchUsPerHandler =>
      handlerCount == 0 ? 0.0 : dispatchUs / handlerCount;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; writer-isolate dispatch counters '
      'will stay zero. Rerun with -DRESQLITE_PROFILE=true.',
    );
  }

  final writeMarkdown = args.contains('--markdown');

  final rows = <_AuditRow>[];
  rows.addAll((await _runA11cAudit()).map(_AuditRow.fromScenario));
  rows.add(_AuditRow.fromScenario(await runKeyedPkScenario()));

  final markdown = _renderMarkdown(rows);
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-135-writer-step-wall-aggregate.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<List<AuditScenarioResult>> _runA11cAudit() async {
  final setup = await setupA11cDb(prefix: 'writer_step_audit_a11c_');
  try {
    return [
      await runA11cScenario(
        setup.db,
        name: 'A11c baseline',
        streamCount: 0,
        updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
        valueFor: (writeIndex) => 'b$writeIndex',
      ),
      await runA11cScenario(
        setup.db,
        name: 'A11c disjoint',
        streamCount: a11cStreamCount,
        updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
        valueFor: (writeIndex) => 'd$writeIndex',
      ),
      await runA11cScenario(
        setup.db,
        name: 'A11c overlap',
        streamCount: a11cStreamCount,
        updateSql: 'UPDATE wide SET a = ? WHERE id = ?',
        valueFor: (writeIndex) => 'o$writeIndex',
      ),
    ];
  } finally {
    await setup.db.close();
    await setup.tempDir.delete(recursive: true);
  }
}

String _renderMarkdown(List<_AuditRow> rows) {
  final readerCount = readerPoolSize();
  final buf = StringBuffer();
  buf.writeln('# Experiment 135 - Writer Step Wall vs Dispatch Wall Audit');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/writer_step_wall_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  buf.writeln();
  buf.writeln(
    'Wall-clock convention: `wall_us` is writer-side burst wall — the '
    'stopwatch stops on the last write (matches exp 119 / exp 121). '
    'Writer counters are snapshotted from the writer isolate via '
    '`Database.snapshotWriterProfileCounters()`.',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/writer_step_wall_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | handler_us | sqlite_us | dispatch_us | '
    'handler_count | parked_total | max_parked | emissions |',
  );
  buf.writeln(
    '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.handlerUs} | ${row.sqliteUs} | ${row.dispatchUs} | '
      '${row.handlerCount} | ${row.parkedTotal} | ${row.maxParked} | '
      '${row.emissions} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived fractions');
  buf.writeln();
  buf.writeln(
    '| workload | handler_us / wall_us | sqlite_us / wall_us | '
    'dispatch_us / wall_us | sqlite_us / handler_us | us per handler | '
    'sqlite_us per handler | dispatch_us per handler |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | '
      '${row.handlerFractionPct.toStringAsFixed(2)}% | '
      '${row.sqliteFractionPct.toStringAsFixed(2)}% | '
      '${row.dispatchFractionPct.toStringAsFixed(2)}% | '
      '${row.sqliteFractionOfHandlerPct.toStringAsFixed(2)}% | '
      '${row.usPerHandler.toStringAsFixed(2)} | '
      '${row.sqliteUsPerHandler.toStringAsFixed(2)} | '
      '${row.dispatchUsPerHandler.toStringAsFixed(2)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `handler_us` is the cumulative wall the writer isolate spent '
    'between request receipt and `replyPort.send`, summed over every '
    'handled message during the workload. It includes Dart-side '
    'dispatch (param allocation, dirty-table marshalling) and the FFI '
    'calls themselves.',
  );
  buf.writeln(
    '- `sqlite_us` is the cumulative wall spent specifically inside '
    'the FFI calls that drive SQLite — `resqliteExecute`, '
    '`resqliteRunBatch`, `resqliteRunBatchNested`, the transaction-control '
    'stmts, and the prepare+step portion of transaction reads.',
  );
  buf.writeln(
    '- `dispatch_us = handler_us - sqlite_us` is the writer-side Dart '
    'dispatch wall: param packing, `getDirtyTableDependencies`, message '
    'send, and any Dart-only bookkeeping inside the handler.',
  );
  buf.writeln(
    '- `sqlite_us / handler_us` is the share of writer-isolate handler '
    'wall actually spent in SQLite. A high share means writer-side '
    'dispatch optimization has little room; a low share means the '
    'inverse.',
  );
  buf.writeln(
    '- `parked_total` and `max_parked` should both stay at zero post-'
    'exp-120, reproducing exp 120\'s acceptance signal as a sanity '
    'check on top of the new counters.',
  );
  buf.writeln();
  buf.writeln('## Interpretation');
  buf.writeln();
  buf.writeln(
    'See `experiments/135-writer-step-wall-audit.md` for the decision '
    'and follow-up notes attached to these numbers.',
  );
  return buf.toString();
}
