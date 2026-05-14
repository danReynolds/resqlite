// ignore_for_file: avoid_print
//
// Completion-side scheduling cost audit — exp 136.
//
// Exp 120 closed the over-dispatch path inside `StreamEngine._flushQueue`
// and dropped `dispatcherParkedTotal` / `dispatcherMaxParkedConcurrent`
// to zero on every measured stream workload. Exp 121 then audited
// invalidation traversal (`onDependencyChanges` synchronous body) and
// landed it at the per-benchmark decision threshold edge — 10–15% of
// A11c overlap wall, with column intersection 2.5–5.7%.
//
// That left two named gating measurements in
// `signals.json#stream-rerun-dispatch.blockedOnMeasurement`:
//
//   - writer-isolate wall vs SQLite step wall split (addressed by
//     exp 135 in a parallel PR — adds writer-isolate counters)
//   - completion-side microtask scheduling cost counter (this exp)
//
// This harness asks one question:
//
//   What fraction of A11c (and keyed-PK) wall time is the synchronous
//   main-isolate completion-side work that fires when reader-pool
//   replies land — `_dispatch` resolution, `_requery` continuation,
//   `entry.emit` to subscribers, and the `_flushQueue` that follows?
//
// If the fraction is small, future dispatch work should branch off
// reader-completion churn entirely (and look elsewhere, e.g. result
// delivery itself or write-handler dispatch). If it is large, reader
// completion batching / coalescing becomes a bounded implementation
// candidate worth a focused experiment.
//
// Workload shapes mirror exp 119 / 121: A11c baseline, A11c disjoint,
// A11c overlap, and keyed-PK subscriptions, all via the shared
// `audit_workloads.dart` runners. The wall-measurement convention is
// the same (stopwatch stops on the last write).
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/completion_scheduling_audit.dart --markdown

import 'dart:io';

import 'package:resqlite/src/profile_mode.dart';

import 'audit_workloads.dart';

final class _AuditRow {
  _AuditRow({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.drainUs,
    required this.completionHandlerUs,
    required this.completionHandlerCount,
    required this.streamEmitUs,
    required this.streamEmitCount,
    required this.invalidateUs,
    required this.parkedTotal,
    required this.maxParked,
    required this.emissions,
  });

  factory _AuditRow.fromScenario(AuditScenarioResult r) {
    // Completion-side work mostly fires AFTER the writer-burst wall
    // ends (reader replies arrive during the drain). Read the
    // post-drain snapshot when available so the counter is complete;
    // fall back to the burst-end snapshot for scenarios that don't
    // populate the drain snapshot.
    final c = r.countersAfterDrain ?? r.counters;
    return _AuditRow(
      workload: r.workload,
      shape: r.shape,
      wallUs: r.wallUs,
      drainUs: r.drainUs,
      completionHandlerUs: c['completion_handler_us'] ?? 0,
      completionHandlerCount: c['completion_handler_count'] ?? 0,
      streamEmitUs: c['stream_emit_us'] ?? 0,
      streamEmitCount: c['stream_emit_count'] ?? 0,
      // Writer-side counters stop incrementing once writes stop, so
      // the burst-end snapshot matches the post-drain snapshot. Use
      // either.
      invalidateUs: c['invalidate_us'] ?? 0,
      parkedTotal: c['dispatcher_parked_total'] ?? 0,
      maxParked: c['dispatcher_max_parked_concurrent'] ?? 0,
      emissions: r.emissions,
    );
  }

  final String workload;
  final String shape;
  final int wallUs;
  final int drainUs;
  final int completionHandlerUs;
  final int completionHandlerCount;
  final int streamEmitUs;
  final int streamEmitCount;
  final int invalidateUs;
  final int parkedTotal;
  final int maxParked;
  final int emissions;

  /// Burst wall (writer-side): from first write to last write.
  double get wallMs => wallUs / 1000.0;

  /// Drain wall: from last write to last subscriber emission (or
  /// quiet-window timeout).
  double get drainMs => drainUs / 1000.0;

  /// Total wall (burst + drain): the wall in which the cumulative
  /// completion-side counters fired. Used as the proper denominator
  /// for "fraction of main-isolate wall in reader-completion work".
  int get totalUs => wallUs + drainUs;
  double get totalMs => totalUs / 1000.0;

  double get completionFractionBurstPct =>
      wallUs == 0 ? 0.0 : (completionHandlerUs / wallUs) * 100.0;

  double get completionFractionTotalPct =>
      totalUs == 0 ? 0.0 : (completionHandlerUs / totalUs) * 100.0;

  double get emitFractionTotalPct =>
      totalUs == 0 ? 0.0 : (streamEmitUs / totalUs) * 100.0;

  double get emitOfCompletionPct => completionHandlerUs == 0
      ? 0.0
      : (streamEmitUs / completionHandlerUs) * 100.0;

  double get invalidateFractionBurstPct =>
      wallUs == 0 ? 0.0 : (invalidateUs / wallUs) * 100.0;

  double get usPerCompletion => completionHandlerCount == 0
      ? 0.0
      : completionHandlerUs / completionHandlerCount;

  double get usPerEmit =>
      streamEmitCount == 0 ? 0.0 : streamEmitUs / streamEmitCount;
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
      'benchmark/profile/results/exp-136-completion-scheduling-aggregate.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<List<AuditScenarioResult>> _runA11cAudit() async {
  final setup = await setupA11cDb(prefix: 'completion_audit_a11c_');
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
  buf.writeln('# Experiment 136 - Completion-side Scheduling Audit');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/completion_scheduling_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  buf.writeln();
  buf.writeln(
    'Wall-clock convention: `wall_ms` is writer-side burst wall — the '
    'stopwatch stops on the last write (same convention as exp 121). '
    '`drain_ms` is the post-burst drain (quiet-window) during which '
    'reader-pool replies finish landing on the main isolate. The '
    'completion-side counters are snapshotted AFTER the drain '
    'finishes — most reader-completion wall fires in the drain, not '
    'inside the burst.',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/completion_scheduling_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | drain_ms | total_ms | '
    'completion_us | completion_count | emit_us | emit_count | '
    'invalidate_us | parked_total | max_parked | emissions |',
  );
  buf.writeln(
    '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.drainMs.toStringAsFixed(2)} | ${row.totalMs.toStringAsFixed(2)} | '
      '${row.completionHandlerUs} | ${row.completionHandlerCount} | '
      '${row.streamEmitUs} | ${row.streamEmitCount} | '
      '${row.invalidateUs} | '
      '${row.parkedTotal} | ${row.maxParked} | ${row.emissions} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived fractions');
  buf.writeln();
  buf.writeln(
    '| workload | completion_us / burst | completion_us / total | '
    'emit_us / total | emit_us / completion_us | us per completion | '
    'us per emit | invalidate_us / burst |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | '
      '${row.completionFractionBurstPct.toStringAsFixed(2)}% | '
      '${row.completionFractionTotalPct.toStringAsFixed(2)}% | '
      '${row.emitFractionTotalPct.toStringAsFixed(2)}% | '
      '${row.emitOfCompletionPct.toStringAsFixed(2)}% | '
      '${row.usPerCompletion.toStringAsFixed(2)} | '
      '${row.usPerEmit.toStringAsFixed(2)} | '
      '${row.invalidateFractionBurstPct.toStringAsFixed(2)}% |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `completion_us` is the cumulative wall-clock microseconds spent in '
    'the main-isolate reader worker port handler synchronous body. Because '
    '`_WorkerSlot.request` uses `Completer<Object?>.sync()`, this captures '
    'the entire downstream `_dispatch` resume / `_requery` continuation / '
    '`entry.emit` / `_flushQueue` chain that runs synchronously inside the '
    'handler. Most of it fires in the post-burst drain, so the counter is '
    'snapshotted AFTER the quiet-window drain completes.',
  );
  buf.writeln(
    '- `emit_us` is the sub-fraction spent inside `StreamEntry.emit` — the '
    'subscriber controller fanout loop. `emit_us / completion_us` reveals '
    'whether reader-completion wall is dominated by subscriber delivery '
    '(higher fraction = batching subscriber notifications is the candidate) '
    'or by hashing/dispatch (lower fraction = reader completion batching '
    'would not help much).',
  );
  buf.writeln(
    '- `completion_us / burst` is the fraction of writer-side burst wall '
    'spent in main-isolate reader-completion handling that fires *inside* '
    'the burst. Compare to exp 121\'s `invalidate_us / wall_us` (writer-side, '
    'runs inside the writer-reply handler chain) — together they bound the '
    'observable in-burst main-isolate cost.',
  );
  buf.writeln(
    '- `completion_us / total` is the fraction of total wall (burst + '
    'drain) spent in reader-completion handling. This is the proper '
    'denominator for "is reader-completion work a realistic optimization '
    'target?" — it asks how much of the main-isolate budget the '
    'completion-side path actually consumes.',
  );
  buf.writeln(
    '- `us per completion` is the average synchronous wall added per '
    'reader-reply handler invocation. On stream workloads each re-query '
    'reply runs the chain once.',
  );
  buf.writeln(
    '- `parked_total` and `max_parked` should both stay at zero post-'
    'exp-120, reproducing exp 120\'s acceptance signal as a sanity check.',
  );
  buf.writeln();
  buf.writeln('## Interpretation');
  buf.writeln();
  buf.writeln(
    'See `experiments/136-completion-microtask-counter.md` for the decision '
    'and follow-up notes attached to these numbers.',
  );
  return buf.toString();
}
