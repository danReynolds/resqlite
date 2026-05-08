// ignore_for_file: avoid_print
//
// Writer-isolate wall vs SQLite step wall audit — exp 127.
//
// Exp 121 audited invalidation traversal as a fraction of A11c overlap
// wall and ruled it out as the active dispatch target. Its decision
// note (and the parallel `signals.json` `blockedOnMeasurement` entry on
// the `stream-rerun-dispatch` and `measurement-system` directions)
// pointed at two remaining missing measurements before any further
// dispatch implementation experiment is worth running:
//
//   1. completion-side microtask scheduling cost
//   2. *writer-isolate dispatch wall vs SQLite step wall split*
//
// This harness builds the second one. It pairs the existing
// `ProfileCounters` snapshot inside `audit_workloads.dart` with a new
// cross-isolate `WriterCountersSnapshotRequest` that returns the
// writer's per-isolate `handlerUs` (cumulative dispatch wall) and
// `sqliteUs` (cumulative wall inside the FFI write helpers), so the
// audit can answer:
//
//   What fraction of A11c overlap (and keyed-PK) wall time does the
//   writer isolate spend in *Dart-side* dispatch (request decode,
//   dirty-table read, response build, isolate reply) versus inside the
//   `executeWrite` / `executeBatchWrite` FFI helpers?
//
// If `writer_sqlite_us / writer_handler_us` is close to 1.0, future
// writer-side dispatch optimizations have no headroom — the writer
// already spends almost all of its busy time in SQLite proper. If it
// is materially lower, there is a Dart-side wall slice that further
// dispatch experiments can credibly target.
//
// Workload shapes mirror exp 119 / exp 121's `audit_workloads.dart`
// scenarios so the writer-side numbers stay directly comparable to the
// reader-pool and invalidation audits as a structural property.
//
// Wall convention is inherited from `audit_workloads.dart`: the
// stopwatch stops on the last write; emission drains run after the
// stopwatch so the wall denominator is not padded with idle waiting.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/writer_isolate_audit.dart --markdown

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
    handlerUs: r.counters['writer_handler_us']!,
    sqliteUs: r.counters['writer_sqlite_us']!,
    handlerCount: r.counters['writer_handler_count']!,
    parkedTotal: r.counters['dispatcher_parked_total']!,
    maxParked: r.counters['dispatcher_max_parked_concurrent']!,
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

  double get wallMs => wallUs / 1000.0;
  double get dartUs =>
      handlerUs >= sqliteUs ? (handlerUs - sqliteUs).toDouble() : 0.0;
  double get handlerFractionPct =>
      wallUs == 0 ? 0.0 : (handlerUs / wallUs) * 100.0;
  double get sqliteFractionPct =>
      wallUs == 0 ? 0.0 : (sqliteUs / wallUs) * 100.0;
  double get dartFractionPct => wallUs == 0 ? 0.0 : (dartUs / wallUs) * 100.0;
  double get sqliteOfHandlerPct =>
      handlerUs == 0 ? 0.0 : (sqliteUs / handlerUs) * 100.0;
  double get usPerHandler =>
      handlerCount == 0 ? 0.0 : handlerUs / handlerCount;
  double get usPerSqlite => handlerCount == 0 ? 0.0 : sqliteUs / handlerCount;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; writer counters will stay zero. '
      'Rerun with -DRESQLITE_PROFILE=true.',
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
      'benchmark/profile/results/exp-127-writer-isolate-wall-aggregate.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<List<AuditScenarioResult>> _runA11cAudit() async {
  final setup = await setupA11cDb(prefix: 'writer_isolate_audit_a11c_');
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
  buf.writeln('# Experiment 127 - Writer-Isolate Wall vs SQLite Step Wall');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/writer_isolate_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  buf.writeln();
  buf.writeln(
    'Wall-clock convention (inherited from `audit_workloads.dart`): '
    '`wall_us` is writer-side burst wall — the stopwatch stops on the '
    'last write. Emission drains run after the stopwatch so the wall '
    'denominator is not padded with idle waiting.',
  );
  buf.writeln();
  buf.writeln(
    '`writer_handler_us` is the cumulative wall the writer dispatch '
    'loop spent inside *every* non-snapshot `WriterRequest` '
    '(`ExecuteRequest`, `BatchRequest`, `BeginRequest`, `CommitRequest`, '
    '`RollbackRequest`, `QueryRequest`, `CloseRequest`), including each '
    'message\'s Dart-side prologue/epilogue (request decode, dirty-'
    'table read, response build, reply send). `writer_sqlite_us` is '
    'narrower — it is the wall spent inside the FFI *write* helpers '
    '(`executeWrite`, `executeBatchWrite`, `executeNestedBatchWrite`), '
    'so it is incremented from `_handleExecute` and `_handleBatch` '
    'only. On the audit workloads here the user only issues '
    '`db.execute`, so handler dispatch is dominated by `ExecuteRequest` '
    'and the difference `handler_us - sqlite_us` is the writer-side '
    'Dart wall on that request type.',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/writer_isolate_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | handler_us | sqlite_us | handler_count | '
    'parked_total | max_parked | emissions |',
  );
  buf.writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.handlerUs} | ${row.sqliteUs} | ${row.handlerCount} | '
      '${row.parkedTotal} | ${row.maxParked} | ${row.emissions} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived fractions');
  buf.writeln();
  buf.writeln(
    '| workload | handler_us / wall_us | sqlite_us / wall_us | '
    'dart_us / wall_us | sqlite_us / handler_us | us per handler call | '
    'us per sqlite call |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | '
      '${row.handlerFractionPct.toStringAsFixed(2)}% | '
      '${row.sqliteFractionPct.toStringAsFixed(2)}% | '
      '${row.dartFractionPct.toStringAsFixed(2)}% | '
      '${row.sqliteOfHandlerPct.toStringAsFixed(2)}% | '
      '${row.usPerHandler.toStringAsFixed(2)} | '
      '${row.usPerSqlite.toStringAsFixed(2)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `handler_us / wall_us` is the fraction of writer-side burst wall '
    'where the writer isolate was actually busy in its handler loop. The '
    'remainder is wall the writer was idle — waiting for the next '
    'request to arrive after the previous one returned to the main '
    'isolate.',
  );
  buf.writeln(
    '- `sqlite_us / wall_us` is the fraction of writer-side burst wall '
    'spent inside the FFI write helpers. This is the floor on what '
    'writer-side dispatch optimizations could possibly leave; if it is '
    'close to `handler_us / wall_us`, the writer is already spending '
    'almost all of its busy time in SQLite proper.',
  );
  buf.writeln(
    '- `dart_us / wall_us` is the writer-side Dart wall fraction — '
    'request decode, dirty-table read, response build, reply send. '
    'Future writer-side dispatch experiments are bounded by this '
    'fraction.',
  );
  buf.writeln(
    '- `sqlite_us / handler_us` is the same idea normalized to the '
    'writer-busy wall. It abstracts over how saturated the writer '
    'isolate is across the burst.',
  );
  buf.writeln(
    '- `parked_total` and `max_parked` should both stay at zero post-'
    'exp-120, reproducing exp 120\'s acceptance signal as a sanity '
    'check.',
  );
  buf.writeln();
  buf.writeln('## Interpretation');
  buf.writeln();
  buf.writeln(
    'See `experiments/127-writer-isolate-wall-split.md` for the decision '
    'and follow-up notes attached to these numbers.',
  );
  return buf.toString();
}
