// ignore_for_file: avoid_print
//
// Main-isolate stream completion wall audit - exp 136.
//
// Exp 135 split the writer-isolate handler wall into Dart dispatch
// and SQLite step time and concluded that the writer is only ~22-25%
// of A11c overlap burst wall - the remaining ~75% lives on the main
// isolate. The `completion-side microtask scheduling cost counter`
// entry in `signals.json#stream-rerun-dispatch.blockedOnMeasurement`
// covers the next step: measure how much of that main-isolate share
// is the synchronous post-`await` body of `StreamEngine._requery`
// (the per-re-query completion path) plus `StreamEntry.emit` (the
// per-subscriber fan-out), versus framework / microtask overhead the
// counters cannot reach.
//
// Counters:
//
//   * `stream_complete_us` - cumulative wall inside the post-await
//     body of `_requery`, including the `finally` `_flushQueue`
//     re-entry. Profile-mode-gated, increments on the main isolate.
//   * `stream_complete_count` - one increment per resolved re-query.
//   * `stream_emit_us` / `stream_emit_count` - the `StreamEntry.emit`
//     for-loop sum and call count; `stream_emit_us` is a subset of
//     `stream_complete_us` since every emit during fanout runs inside
//     the completion wall.
//
// The audit reports both raw counters and derived fractions against
// the existing exp 121/135 wall convention (`wall_us` is writer-side
// burst wall; emissions drain runs after the stopwatch stops). The
// "accounted for" column sums `invalidate_us + stream_complete_us`
// (main-isolate synchronous stream wall) and divides by wall.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/stream_completion_audit.dart --markdown

import 'dart:io';

import 'package:resqlite/src/profile_mode.dart';

import 'audit_workloads.dart';

final class _AuditRow {
  _AuditRow({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.invalidateUs,
    required this.invalidateCount,
    required this.streamCompleteUs,
    required this.streamCompleteCount,
    required this.streamEmitUs,
    required this.streamEmitCount,
    required this.parkedTotal,
    required this.maxParked,
    required this.emissions,
  });

  factory _AuditRow.fromScenario(AuditScenarioResult r) => _AuditRow(
    workload: r.workload,
    shape: r.shape,
    wallUs: r.wallUs,
    invalidateUs: r.counters['invalidate_us'] ?? 0,
    invalidateCount: r.counters['invalidate_count'] ?? 0,
    streamCompleteUs: r.counters['stream_complete_us'] ?? 0,
    streamCompleteCount: r.counters['stream_complete_count'] ?? 0,
    streamEmitUs: r.counters['stream_emit_us'] ?? 0,
    streamEmitCount: r.counters['stream_emit_count'] ?? 0,
    parkedTotal: r.counters['dispatcher_parked_total'] ?? 0,
    maxParked: r.counters['dispatcher_max_parked_concurrent'] ?? 0,
    emissions: r.emissions,
  );

  final String workload;
  final String shape;
  final int wallUs;
  final int invalidateUs;
  final int invalidateCount;
  final int streamCompleteUs;
  final int streamCompleteCount;
  final int streamEmitUs;
  final int streamEmitCount;
  final int parkedTotal;
  final int maxParked;
  final int emissions;

  double get wallMs => wallUs / 1000.0;

  int get accountedUs => invalidateUs + streamCompleteUs;

  double _pct(int numerator) =>
      wallUs == 0 ? 0.0 : (numerator / wallUs) * 100.0;
  double get invalidateFractionPct => _pct(invalidateUs);
  double get streamCompleteFractionPct => _pct(streamCompleteUs);
  double get streamEmitFractionPct => _pct(streamEmitUs);
  double get accountedFractionPct => _pct(accountedUs);

  double get emitFractionOfCompletePct => streamCompleteUs == 0
      ? 0.0
      : (streamEmitUs / streamCompleteUs) * 100.0;

  double get usPerComplete => streamCompleteCount == 0
      ? 0.0
      : streamCompleteUs / streamCompleteCount;
  double get usPerEmit =>
      streamEmitCount == 0 ? 0.0 : streamEmitUs / streamEmitCount;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; stream completion counters '
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
      'benchmark/profile/results/exp-136-stream-completion-aggregate.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<List<AuditScenarioResult>> _runA11cAudit() async {
  final setup = await setupA11cDb(prefix: 'stream_completion_audit_a11c_');
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
  buf.writeln('# Experiment 136 - Stream Completion Wall Audit');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/stream_completion_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  buf.writeln();
  buf.writeln(
    'Wall-clock convention: `wall_us` is writer-side burst wall - the '
    'stopwatch stops on the last write (matches exp 119 / 121 / 135). '
    'Main-isolate stream counters are picked up from `ProfileCounters` '
    'directly; writer counters from `Database.snapshotWriterProfileCounters`.',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/stream_completion_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | invalidate_us | complete_us | '
    'complete_count | emit_us | emit_count | parked_total | max_parked | '
    'emissions |',
  );
  buf.writeln(
    '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.invalidateUs} | ${row.streamCompleteUs} | '
      '${row.streamCompleteCount} | ${row.streamEmitUs} | '
      '${row.streamEmitCount} | ${row.parkedTotal} | ${row.maxParked} | '
      '${row.emissions} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived fractions');
  buf.writeln();
  buf.writeln(
    '| workload | invalidate / wall | complete / wall | emit / wall | '
    'accounted / wall | emit / complete | us per complete | us per emit |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | '
      '${row.invalidateFractionPct.toStringAsFixed(2)}% | '
      '${row.streamCompleteFractionPct.toStringAsFixed(2)}% | '
      '${row.streamEmitFractionPct.toStringAsFixed(2)}% | '
      '${row.accountedFractionPct.toStringAsFixed(2)}% | '
      '${row.emitFractionOfCompletePct.toStringAsFixed(2)}% | '
      '${row.usPerComplete.toStringAsFixed(2)} | '
      '${row.usPerEmit.toStringAsFixed(2)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `invalidate_us` is exp 121\'s existing counter: cumulative wall '
    'inside the synchronous body of `StreamEngine.onDependencyChanges` '
    '(table index lookup, column intersection probes, dirty/in-flight '
    'scheduling, and the `_flushQueue` kickoff).',
  );
  buf.writeln(
    '- `complete_us` is exp 136\'s new counter: cumulative wall inside '
    'the synchronous post-`await` body of `StreamEngine._requery` '
    '(bookkeeping, hash-changed shortcut, `entry.emit`, and the trailing '
    '`_flushQueue` re-entry). Captures the per-re-query completion '
    'cost that runs after the reader pool resolves.',
  );
  buf.writeln(
    '- `emit_us` is a strict subset of `complete_us`: the `for` loop '
    'in `StreamEntry.emit` that calls `StreamController.add` on every '
    'open subscriber. Captures per-subscriber fan-out, not bookkeeping.',
  );
  buf.writeln(
    '- `accounted / wall` = `(invalidate_us + complete_us) / wall_us` '
    'is the share of writer-burst wall that the main-isolate '
    'synchronous stream-engine code accounts for. The remainder lives '
    'in framework microtask scheduling, subscriber callbacks, reader-'
    'pool internals, and any unmeasured async boundary.',
  );
  buf.writeln(
    '- `parked_total` and `max_parked` should both stay at zero post-'
    'exp-120 / 122, reproducing earlier acceptance signals as a sanity '
    'check on top of the new counters.',
  );
  buf.writeln();
  buf.writeln('## Interpretation');
  buf.writeln();
  buf.writeln(
    'See `experiments/136-stream-completion-counter.md` for the '
    'decision and follow-up notes attached to these numbers.',
  );
  return buf.toString();
}
