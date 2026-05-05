// ignore_for_file: avoid_print
//
// Stream-completion scheduling cost audit - exp 124.
//
// Exp 120 closed the over-dispatch path inside `StreamEngine._flushQueue`
// and dropped `dispatcherParkedTotal` to zero on every measured stream
// workload. Exp 121 then ruled out invalidation traversal as a wall-time
// target - 10-15% of A11c overlap wall, 2.5-5.7% on column intersection.
// Both pointed `signals.json` at completion-side scheduling cost as the
// remaining wall-time source on the writer-side burst path.
//
// The matching counter (`ProfileCounters.streamCompletionUs` /
// `streamCompletionCount`) was missing - it sat in the
// `stream-rerun-dispatch.blockedOnMeasurement` list and the
// `measurement-system.openCandidates` list as the next gating
// measurement. Exp 124 adds the counter and runs this audit.
//
// `streamCompletionUs` accumulates the synchronous wall the main
// isolate event loop runs *after* the reader-pool await returns inside
// `StreamEngine._requery` and `_createStream`: the result-change check,
// `entry.emit(rows)` to subscribers, and the trailing `_flushQueue`
// kickoff that admits the next dequeue. That is the "completion side"
// the previous audits could not see directly.
//
// The harness asks one question:
//
//   What fraction of A11c overlap (and keyed-PK) writer-side burst wall
//   is the synchronous body of stream completions on the main isolate?
//
// Workload shapes reuse `audit_workloads.dart` so this audit stays
// directly comparable to exp 119/121.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/stream_completion_audit.dart --markdown

import 'dart:io';

import 'package:resqlite/src/profile_mode.dart';

import 'audit_workloads.dart';

int _writeCountForWorkload(String workload) {
  // Explicit write counts taken from `audit_workloads.dart` constants
  // (a11cWriteCount, keyedPkWriteCount). Carrying them through the row
  // avoids deriving 'us per write' from `invalidate_count`, which is an
  // invalidation counter and would silently break if a workload ever
  // fired multiple dependency changes per write.
  if (workload.startsWith('A11c')) return a11cWriteCount;
  if (workload.startsWith('keyed PK')) return keyedPkWriteCount;
  return 0;
}

final class _AuditRow {
  _AuditRow({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.writeCount,
    required this.completionUs,
    required this.completionCount,
    required this.invalidateUs,
    required this.invalidateCount,
    required this.parkedTotal,
    required this.maxParked,
    required this.emissions,
  });

  factory _AuditRow.fromScenario(AuditScenarioResult r) => _AuditRow(
    workload: r.workload,
    shape: r.shape,
    wallUs: r.wallUs,
    writeCount: _writeCountForWorkload(r.workload),
    completionUs: r.counters['stream_completion_us'] ?? 0,
    completionCount: r.counters['stream_completion_count'] ?? 0,
    invalidateUs: r.counters['invalidate_us'] ?? 0,
    invalidateCount: r.counters['invalidate_count'] ?? 0,
    parkedTotal: r.counters['dispatcher_parked_total'] ?? 0,
    maxParked: r.counters['dispatcher_max_parked_concurrent'] ?? 0,
    emissions: r.emissions,
  );

  final String workload;
  final String shape;
  final int wallUs;
  final int writeCount;
  final int completionUs;
  final int completionCount;
  final int invalidateUs;
  final int invalidateCount;
  final int parkedTotal;
  final int maxParked;
  final int emissions;

  double get wallMs => wallUs / 1000.0;
  double get completionFractionPct =>
      wallUs == 0 ? 0.0 : (completionUs / wallUs) * 100.0;
  double get invalidateFractionPct =>
      wallUs == 0 ? 0.0 : (invalidateUs / wallUs) * 100.0;
  double get usPerCompletion =>
      completionCount == 0 ? 0.0 : completionUs / completionCount;
  double get usPerWriteCompletion =>
      writeCount == 0 ? 0.0 : completionUs / writeCount;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; completion counters will stay zero. '
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
      'benchmark/profile/results/exp-124-stream-completion-aggregate.md',
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
  buf.writeln('# Experiment 124 - Stream Completion Audit');
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
    'stopwatch stops on the last write. Emission drains run after the '
    'stopwatch so the denominator is not padded with idle waiting '
    '(same convention as exp 119 / exp 121, enforced by '
    '`audit_workloads.dart`).',
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
    '| workload | shape | wall_ms | completion_us | completion_count | '
    'invalidate_us | invalidate_count | parked_total | max_parked | emissions |',
  );
  buf.writeln(
    '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.completionUs} | ${row.completionCount} | '
      '${row.invalidateUs} | ${row.invalidateCount} | '
      '${row.parkedTotal} | ${row.maxParked} | ${row.emissions} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived fractions');
  buf.writeln();
  buf.writeln(
    '| workload | completion_us / wall_us | invalidate_us / wall_us | '
    'us per completion | us per write |',
  );
  buf.writeln('|---|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | '
      '${row.completionFractionPct.toStringAsFixed(2)}% | '
      '${row.invalidateFractionPct.toStringAsFixed(2)}% | '
      '${row.usPerCompletion.toStringAsFixed(2)} | '
      '${row.usPerWriteCompletion.toStringAsFixed(2)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `completion_us` is the cumulative wall-clock microseconds spent '
    'in the synchronous body of `StreamEngine._requery` and '
    '`_createStream` *after* the reader-pool `await` returns: the '
    'result-change check, `entry.emit(rows)` to subscribers, and the '
    'trailing `_flushQueue` kickoff. This is the work the main-isolate '
    'event loop runs in response to a stream re-query reply - the '
    'completion-side scheduling cost exp 120 / exp 121 left as an open '
    'counter for `stream-rerun-dispatch`.',
  );
  buf.writeln(
    '- `completion_count` increments once per resumed `_requery` body '
    '(plus initial-emit body in `_createStream`). For A11c workloads it '
    'is dominated by re-query completions during the burst.',
  );
  buf.writeln(
    '- `completion_us / wall_us` is the fraction of writer-side burst '
    'wall attributable to completion-side scheduling on the main '
    'isolate. Compare against `invalidate_us / wall_us` (exp 121) to '
    'see whether the remaining writer-side wall sits in invalidation '
    'traversal or completion-side scheduling.',
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
    'See `experiments/124-stream-completion-counter.md` for the '
    'decision and follow-up notes attached to these numbers.',
  );
  return buf.toString();
}
