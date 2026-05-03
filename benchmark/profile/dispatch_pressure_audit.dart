// ignore_for_file: avoid_print
//
// Post-FIFO dispatch-pressure audit — exp 119.
//
// Runs resqlite-only profile workloads after exp 118's FIFO dispatch
// waiters to answer one question before trying another dispatch
// optimization:
//
//   Do real app-shaped workloads still produce ReaderPool dispatch
//   parking or wake retries?
//
// The direct-read control intentionally overloads the reader pool so
// the counters prove they are live. The stream workloads mirror the
// current A11c and keyed-PK pressure shapes, where upstream stream
// admission and result hashing may dominate before ReaderPool._dispatch
// ever parks.
//
// Workload runners are shared with `invalidation_traversal_audit.dart`
// (exp 121) via `audit_workloads.dart`, so the two reports stay
// directly comparable as a structural property — workload tweaks land
// in one place. The shared runners also stop the stopwatch on the last
// write, leaving emission drains outside the wall_us measurement.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/dispatch_pressure_audit.dart --markdown

import 'dart:io';

import 'package:resqlite/src/profile_mode.dart';

import 'audit_workloads.dart';

final class _AuditRow {
  _AuditRow({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.parked,
    required this.retries,
    required this.maxParked,
    required this.invalidateCount,
    required this.intersectionEntries,
    required this.emissions,
    required this.observedHits,
  });

  factory _AuditRow.fromScenario(AuditScenarioResult r) => _AuditRow(
    workload: r.workload,
    shape: r.shape,
    wallUs: r.wallUs,
    parked: r.counters['dispatcher_parked_total']!,
    retries: r.counters['dispatcher_wake_retry_total']!,
    maxParked: r.counters['dispatcher_max_parked_concurrent']!,
    invalidateCount: r.counters['invalidate_count']!,
    intersectionEntries: r.counters['intersection_entries']!,
    emissions: r.emissions,
    observedHits: r.observedHits,
  );

  final String workload;
  final String shape;
  final int wallUs;
  final int parked;
  final int retries;
  final int maxParked;
  final int invalidateCount;
  final int intersectionEntries;
  final int emissions;
  final int observedHits;

  double get wallMs => wallUs / 1000.0;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; dispatch counters will stay zero. '
      'Rerun with -DRESQLITE_PROFILE=true.',
    );
  }

  final writeMarkdown = args.contains('--markdown');

  final rows = <_AuditRow>[];
  rows.add(_AuditRow.fromScenario(await runDirectReadControl()));
  rows.addAll((await _runA11cAudit()).map(_AuditRow.fromScenario));
  rows.add(_AuditRow.fromScenario(await runKeyedPkScenario()));

  final markdown = _renderMarkdown(rows);
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-119-dispatch-pressure-audit.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<List<AuditScenarioResult>> _runA11cAudit() async {
  final setup = await setupA11cDb(prefix: 'dispatch_audit_a11c_');
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
  buf.writeln('# Experiment 119 - Dispatch Pressure Audit');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: `benchmark/profile/dispatch_pressure_audit.dart`',
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
    'benchmark/profile/dispatch_pressure_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | parked_total | wake_retry_total | '
    'max_parked | invalidate_count | intersection_entries | emissions | observed_hits |',
  );
  buf.writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | '
      '${row.wallMs.toStringAsFixed(2)} | ${row.parked} | '
      '${row.retries} | ${row.maxParked} | ${row.invalidateCount} | '
      '${row.intersectionEntries} | ${row.emissions} | '
      '${row.observedHits} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `direct reads control` intentionally overloads the reader pool. '
    'It should still park, but FIFO dispatch should keep '
    '`wake_retry_total` at zero.',
  );
  buf.writeln(
    '- A11c rows use the same 50-stream, 20-column shape as the release '
    'many-streams writer-throughput workload. Disjoint writes update `c`; '
    'overlap writes update `a`, which every stream projects.',
  );
  buf.writeln(
    '- `keyed PK subscriptions` mirrors the release keyed-PK miss-path: '
    '50 streams watch fixed primary keys while 200 deterministic writes '
    'target random rows.',
  );
  buf.writeln();
  buf.writeln('## Interpretation');
  buf.writeln();
  buf.writeln(
    'The post-FIFO signal is not wake amplification: `wake_retry_total` '
    'is zero in every workload. The remaining dispatch pressure is '
    'admission/completion shaped. Overlap and keyed-PK stream workloads '
    'still create parked dispatchers even though visible emissions are '
    'heavily coalesced or hash-suppressed.',
  );
  buf.writeln();
  buf.writeln(
    'A follow-up dispatch experiment should therefore target stream '
    're-query admission or completion-side scheduling. Another '
    'ReaderPool wake-policy change needs a new nonzero retry signal '
    'before it is worth trying.',
  );
  return buf.toString();
}
