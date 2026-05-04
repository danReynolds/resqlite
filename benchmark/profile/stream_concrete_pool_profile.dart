// ignore_for_file: avoid_print
//
// Concrete reader-pool stream admission profile — exp 122.
//
// Measures whether stream re-query admission is dispatching beyond reader
// availability after exp 118 eliminated wake retries. Run once on baseline,
// then again on the candidate branch:
//
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/stream_concrete_pool_profile.dart --label=baseline

import 'dart:io';

import 'package:resqlite/src/profile_mode.dart';

import 'audit_workloads.dart';

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; dispatch counters will stay zero. '
      'Rerun with -DRESQLITE_PROFILE=true.',
    );
  }

  final label = _option(args, '--label') ?? 'candidate';

  final rows = <AuditScenarioResult>[
    ...await _runA11cProfile(),
    await runKeyedPkScenario(),
  ];

  final markdown = _renderMarkdown(rows, label);
  print(markdown);
}

Future<List<AuditScenarioResult>> _runA11cProfile() async {
  final setup = await setupA11cDb(prefix: 'stream_concrete_pool_a11c_');
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

String _renderMarkdown(List<AuditScenarioResult> rows, String label) {
  final buf = StringBuffer();
  buf.writeln('# Experiment 122 - Concrete Reader-Pool Admission Profile');
  buf.writeln();
  buf.writeln('Run label: `$label`');
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/stream_concrete_pool_profile.dart '
    '--label=$label',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | parked_total | wake_retry_total | '
    'max_parked | invalidate_count | intersection_entries | emissions | observed_hits |',
  );
  buf.writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    final counters = row.counters;
    buf.writeln(
      '| ${row.workload} | ${row.shape} | '
      '${(row.wallUs / 1000.0).toStringAsFixed(2)} | '
      '${counters['dispatcher_parked_total']} | '
      '${counters['dispatcher_wake_retry_total']} | '
      '${counters['dispatcher_max_parked_concurrent']} | '
      '${counters['invalidate_count']} | '
      '${counters['intersection_entries']} | ${row.emissions} | '
      '${row.observedHits} |',
    );
  }
  return buf.toString();
}

String? _option(List<String> args, String name) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      return arg.substring(prefix.length);
    }
  }
  return null;
}
