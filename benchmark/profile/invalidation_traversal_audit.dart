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
// Workload shapes mirror exp 119's `dispatch_pressure_audit.dart`. To
// keep that "directly comparable" claim a structural property — not
// something that drifts the next time someone tweaks a workload — both
// harnesses call into `audit_workloads.dart` for the actual scenario
// runners, including the wall-measurement convention (wall stops on
// the last write; emission drains run after the stopwatch).
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/invalidation_traversal_audit.dart --markdown

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
    required this.intersectionUs,
    required this.intersectionEntries,
    required this.parkedTotal,
    required this.maxParked,
    required this.emissions,
  });

  factory _AuditRow.fromScenario(AuditScenarioResult r) => _AuditRow(
    workload: r.workload,
    shape: r.shape,
    wallUs: r.wallUs,
    invalidateUs: r.counters['invalidate_us']!,
    invalidateCount: r.counters['invalidate_count']!,
    intersectionUs: r.counters['intersection_us']!,
    intersectionEntries: r.counters['intersection_entries']!,
    parkedTotal: r.counters['dispatcher_parked_total']!,
    maxParked: r.counters['dispatcher_max_parked_concurrent']!,
    emissions: r.emissions,
  );

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
  rows.addAll((await _runA11cAudit()).map(_AuditRow.fromScenario));
  rows.add(_AuditRow.fromScenario(await runKeyedPkScenario()));

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

Future<List<AuditScenarioResult>> _runA11cAudit() async {
  final setup = await setupA11cDb(prefix: 'invalidation_audit_a11c_');
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
  buf.writeln(
    'Wall-clock convention: `wall_us` is writer-side burst wall — the '
    'stopwatch stops on the last write. Emission drains run after the '
    'stopwatch so the denominator is not padded with idle waiting.',
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
    '| workload | invalidate_us / wall_us | intersection_us / wall_us | '
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
    '- `invalidate_us / wall_us` is the fraction of writer-side burst wall '
    'attributable to invalidation traversal. A11c overlap is the workload '
    'exp 119/120 flagged as the next signal source; if that fraction is '
    'small, future dispatch work should branch off invalidation and toward '
    'completion-side or writer-side wall.',
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
