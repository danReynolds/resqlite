// ignore_for_file: avoid_print
//
// Writer-isolate dispatch wall audit — exp 127.
//
// Exp 121 closed the invalidation-traversal question: ~10–15% of A11c
// overlap wall is the synchronous body of `StreamEngine.onDependencyChanges`,
// not large enough on its own to re-open dispatch implementation work.
// That left two named blocking measurements in the
// `stream-rerun-dispatch` direction:
//
//   - completion-side microtask scheduling cost
//   - **writer-isolate wall vs SQLite step wall split**
//
// This harness ships the second one. It uses the new
// `WriterProfileCounters.writerHandleUs` (cumulative writer-isolate
// `_handle*` body wall for `Execute` + `Batch`) and `writerStepUs`
// (cumulative wall inside the `resqlite_execute` / `resqlite_run_batch`
// FFI call) — both gated on `kProfileMode` so release builds stay
// zero-cost.
//
// The audit asks one question:
//
//   What fraction of writer-side burst wall is Dart-side dispatch
//   overhead (param encoding, FFI marshaling, dirty-tables gather,
//   IPC framing) vs SQLite step itself?
//
// If the Dart-side share is small, future dispatch-area work should
// branch off the writer isolate and toward completion-side scheduling
// (the other open candidate). If it is large, writer-side dispatch is
// itself a viable optimization target — and the audit names which
// workload makes it visible.
//
// Workload runners come from `audit_workloads.dart` so this harness
// stays directly comparable to exp 119 (dispatch parking) and exp 121
// (invalidation traversal). Both runners stop the stopwatch on the
// last write and snapshot writer counters via
// `Database.writerProfileCounters()` immediately around the burst.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/writer_dispatch_audit.dart --markdown

import 'dart:io';

import 'package:resqlite/src/profile_mode.dart';

import 'audit_workloads.dart';

final class _AuditRow {
  _AuditRow({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.writerHandleUs,
    required this.writerStepUs,
    required this.writerHandleCount,
    required this.invalidateCount,
    required this.parkedTotal,
  });

  factory _AuditRow.fromScenario(AuditScenarioResult r) => _AuditRow(
    workload: r.workload,
    shape: r.shape,
    wallUs: r.wallUs,
    writerHandleUs: r.writerCounters['writer_handle_us'] ?? 0,
    writerStepUs: r.writerCounters['writer_step_us'] ?? 0,
    writerHandleCount: r.writerCounters['writer_handle_count'] ?? 0,
    invalidateCount: r.counters['invalidate_count'] ?? 0,
    parkedTotal: r.counters['dispatcher_parked_total'] ?? 0,
  );

  final String workload;
  final String shape;
  final int wallUs;
  final int writerHandleUs;
  final int writerStepUs;
  final int writerHandleCount;
  final int invalidateCount;
  final int parkedTotal;

  double get wallMs => wallUs / 1000.0;

  /// Dart-side dispatch portion = writer-isolate handler wall minus the
  /// SQLite step wall reported by the FFI-call counter. Sub-zero values
  /// would indicate clock drift between the two stopwatches; treat them
  /// as zero in the report rather than printing noise.
  int get writerDispatchUs {
    final v = writerHandleUs - writerStepUs;
    return v < 0 ? 0 : v;
  }

  double get handleFractionPct =>
      wallUs == 0 ? 0.0 : (writerHandleUs / wallUs) * 100.0;
  double get stepFractionPct =>
      wallUs == 0 ? 0.0 : (writerStepUs / wallUs) * 100.0;
  double get dispatchFractionPct =>
      wallUs == 0 ? 0.0 : (writerDispatchUs / wallUs) * 100.0;

  double get usPerWriteHandle =>
      writerHandleCount == 0 ? 0.0 : writerHandleUs / writerHandleCount;
  double get usPerWriteStep =>
      writerHandleCount == 0 ? 0.0 : writerStepUs / writerHandleCount;
  double get usPerWriteDispatch =>
      writerHandleCount == 0 ? 0.0 : writerDispatchUs / writerHandleCount;
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
      'benchmark/profile/results/exp-127-writer-dispatch-aggregate.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<List<AuditScenarioResult>> _runA11cAudit() async {
  final setup = await setupA11cDb(prefix: 'writer_dispatch_audit_a11c_');
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
  buf.writeln('# Experiment 127 - Writer Dispatch Wall Audit');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/writer_dispatch_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  buf.writeln();
  buf.writeln(
    'Wall-clock convention: `wall_us` is writer-side burst wall — the '
    'stopwatch stops on the last write. Writer counters are snapshotted '
    'via `Database.writerProfileCounters()` immediately around the burst, '
    'so `writer_handle_us` and `writer_step_us` cover the same window as '
    '`wall_us`.',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/writer_dispatch_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | writer_handle_us | writer_step_us | '
    'writer_handle_count | invalidate_count | parked_total |',
  );
  buf.writeln('|---|---|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.writerHandleUs} | ${row.writerStepUs} | '
      '${row.writerHandleCount} | ${row.invalidateCount} | '
      '${row.parkedTotal} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived fractions');
  buf.writeln();
  buf.writeln(
    '| workload | handle / wall | step / wall | dispatch / wall | '
    'us per write (handle) | us per write (step) | us per write (dispatch) |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | '
      '${row.handleFractionPct.toStringAsFixed(2)}% | '
      '${row.stepFractionPct.toStringAsFixed(2)}% | '
      '${row.dispatchFractionPct.toStringAsFixed(2)}% | '
      '${row.usPerWriteHandle.toStringAsFixed(2)} | '
      '${row.usPerWriteStep.toStringAsFixed(2)} | '
      '${row.usPerWriteDispatch.toStringAsFixed(2)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `writer_handle_us` is cumulative wall in the writer isolate\'s '
    '`_handleExecute` / `_handleBatch` body. It includes param encoding, '
    'the SQLite step itself, dirty-tables gather, and response build.',
  );
  buf.writeln(
    '- `writer_step_us` is the subset spent inside the FFI call '
    '(`resqlite_execute` / `resqlite_run_batch`). The C side is not '
    'instrumented; treat this as the closest available approximation '
    'to "real SQLite work" without modifying the C amalgamation.',
  );
  buf.writeln(
    '- `dispatch / wall` = `(writer_handle_us - writer_step_us) / wall_us`. '
    'It is the fraction of writer-side burst wall attributable to '
    'Dart-side dispatch overhead — param encoding, dirty-tables gather, '
    'isolate IPC framing, response construction. A small share argues '
    'that the next dispatch experiment should branch onto completion-side '
    'scheduling instead.',
  );
  buf.writeln(
    '- `parked_total` should stay at zero post-exp-120/122. If it ticks '
    'above zero, treat the run as a regression of the dispatch-admission '
    'invariant before reading the writer fractions.',
  );
  buf.writeln();
  buf.writeln('## Interpretation');
  buf.writeln();
  buf.writeln(
    'See `experiments/127-writer-dispatch-wall-audit.md` for the decision '
    'and follow-up notes attached to these numbers.',
  );
  return buf.toString();
}
