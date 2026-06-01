// ignore_for_file: avoid_print
//
// Writer wall vs SQLite-call split audit - exp 135.
//
// Exp 121 removed invalidation traversal as the active stream-dispatch
// implementation target and left two measurement blockers: completion-side
// scheduling cost and writer-isolate wall vs SQLite work. The writer timing
// counters added for this audit split the existing A11c/keyed-PK write burst
// into:
//
//   writer_request_us      main-isolate wait for the writer isolate response
//   writer_sqlite_us       writer-isolate native write call wall
//   writer_dirty_drain_us  writer-isolate dirty dependency drain wall
//   invalidate_us          synchronous StreamEngine.onDependencyChanges wall
//
// Whatever remains in wall_us is the per-write yield/completion side of the
// shared audit workload plus loop overhead.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/writer_sqlite_wall_audit.dart --markdown

import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_mode.dart';

import 'audit_workloads.dart';

const int _warmupPasses = 1;
const int _measuredPasses = 3;

final class _AuditRow {
  _AuditRow({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.writerRequestUs,
    required this.writerRequestCount,
    required this.writerSqliteUs,
    required this.writerDirtyDrainUs,
    required this.invalidateUs,
    required this.intersectionUs,
    required this.emissions,
    required this.observedHits,
  });

  factory _AuditRow.fromScenario(AuditScenarioResult r) => _AuditRow(
    workload: r.workload,
    shape: r.shape,
    wallUs: r.wallUs,
    writerRequestUs: r.counters['writer_request_us']!,
    writerRequestCount: r.counters['writer_request_count']!,
    writerSqliteUs: r.counters['writer_sqlite_us']!,
    writerDirtyDrainUs: r.counters['writer_dirty_drain_us']!,
    invalidateUs: r.counters['invalidate_us']!,
    intersectionUs: r.counters['intersection_us']!,
    emissions: r.emissions,
    observedHits: r.observedHits,
  );

  final String workload;
  final String shape;
  final int wallUs;
  final int writerRequestUs;
  final int writerRequestCount;
  final int writerSqliteUs;
  final int writerDirtyDrainUs;
  final int invalidateUs;
  final int intersectionUs;
  final int emissions;
  final int observedHits;

  double get wallMs => wallUs / 1000.0;
  double get writerRequestMs => writerRequestUs / 1000.0;
  double get writerSqliteMs => writerSqliteUs / 1000.0;
  double get writerDirtyDrainMs => writerDirtyDrainUs / 1000.0;
  double get invalidateMs => invalidateUs / 1000.0;
  double get writerRequestFractionPct =>
      wallUs == 0 ? 0.0 : (writerRequestUs / wallUs) * 100.0;
  double get writerSqliteFractionPct =>
      writerRequestUs == 0 ? 0.0 : (writerSqliteUs / writerRequestUs) * 100.0;
  double get writerDirtyFractionPct => writerRequestUs == 0
      ? 0.0
      : (writerDirtyDrainUs / writerRequestUs) * 100.0;
  double get invalidateFractionPct =>
      wallUs == 0 ? 0.0 : (invalidateUs / wallUs) * 100.0;
  int get writerResidualUs =>
      _nonNegative(writerRequestUs - writerSqliteUs - writerDirtyDrainUs);
  int get wallResidualUs =>
      _nonNegative(wallUs - writerRequestUs - invalidateUs);
  double get writerResidualMs => writerResidualUs / 1000.0;
  double get wallResidualMs => wallResidualUs / 1000.0;
  double get avgRequestUs =>
      writerRequestCount == 0 ? 0.0 : writerRequestUs / writerRequestCount;
  double get avgSqliteUs =>
      writerRequestCount == 0 ? 0.0 : writerSqliteUs / writerRequestCount;
  double get avgDirtyUs =>
      writerRequestCount == 0 ? 0.0 : writerDirtyDrainUs / writerRequestCount;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; writer timing counters will stay zero. '
      'Rerun with -DRESQLITE_PROFILE=true.',
    );
  }

  final writeMarkdown = args.contains('--markdown');

  final rows = <_AuditRow>[];
  rows.addAll((await _runA11cAudit()).map(_AuditRow.fromScenario));
  rows.add(_AuditRow.fromScenario(await _medianKeyedPkScenario()));

  final markdown = _renderMarkdown(rows);
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-135-writer-sqlite-wall-split.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<List<AuditScenarioResult>> _runA11cAudit() async {
  final setup = await setupA11cDb(prefix: 'writer_sqlite_wall_a11c_');
  try {
    return [
      await _medianA11cScenario(
        setup.db,
        name: 'A11c baseline',
        streamCount: 0,
        updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
        valuePrefix: 'b',
      ),
      await _medianA11cScenario(
        setup.db,
        name: 'A11c disjoint',
        streamCount: a11cStreamCount,
        updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
        valuePrefix: 'd',
      ),
      await _medianA11cScenario(
        setup.db,
        name: 'A11c overlap',
        streamCount: a11cStreamCount,
        updateSql: 'UPDATE wide SET a = ? WHERE id = ?',
        valuePrefix: 'o',
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
  buf.writeln('# Experiment 135 - Writer Wall vs SQLite-Call Split');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/writer_sqlite_wall_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  buf.writeln(
    'Passes: $_warmupPasses discarded warmup, $_measuredPasses measured '
    'passes per row; tables report medians.',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/writer_sqlite_wall_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | writer_request_ms | writer_sqlite_ms | '
    'dirty_drain_ms | invalidate_ms | writer_residual_ms | '
    'wall_residual_ms | writes | emissions | observed_hits |',
  );
  buf.writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | '
      '${row.wallMs.toStringAsFixed(2)} | '
      '${row.writerRequestMs.toStringAsFixed(2)} | '
      '${row.writerSqliteMs.toStringAsFixed(2)} | '
      '${row.writerDirtyDrainMs.toStringAsFixed(2)} | '
      '${row.invalidateMs.toStringAsFixed(2)} | '
      '${row.writerResidualMs.toStringAsFixed(2)} | '
      '${row.wallResidualMs.toStringAsFixed(2)} | '
      '${row.writerRequestCount} | ${row.emissions} | '
      '${row.observedHits} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived fractions');
  buf.writeln();
  buf.writeln(
    '| workload | writer_request / wall | sqlite / writer_request | '
    'dirty_drain / writer_request | invalidate / wall | '
    'avg_request_us | avg_sqlite_us | avg_dirty_us |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | '
      '${row.writerRequestFractionPct.toStringAsFixed(2)}% | '
      '${row.writerSqliteFractionPct.toStringAsFixed(2)}% | '
      '${row.writerDirtyFractionPct.toStringAsFixed(2)}% | '
      '${row.invalidateFractionPct.toStringAsFixed(2)}% | '
      '${row.avgRequestUs.toStringAsFixed(1)} | '
      '${row.avgSqliteUs.toStringAsFixed(1)} | '
      '${row.avgDirtyUs.toStringAsFixed(1)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `writer_request_ms` is measured on the main isolate around the '
    'writer request/response after the write mutex is held. It excludes '
    '`StreamEngine.onDependencyChanges`.',
  );
  buf.writeln(
    '- `writer_sqlite_ms` is measured on the writer isolate around the '
    'native write call. It includes SQLite prepare/cache lookup, bind, '
    'step/commit, reset, and native result extraction.',
  );
  buf.writeln(
    '- `dirty_drain_ms` is the writer-isolate drain of dirty table/column '
    'metadata after the native write completes.',
  );
  buf.writeln(
    '- `writer_residual_ms` is writer request wall not explained by the '
    'native write call or dirty drain. It is the IPC / Dart request '
    'handling / response delivery bucket.',
  );
  buf.writeln(
    '- `wall_residual_ms` is outer workload wall not explained by writer '
    'request or synchronous invalidation. On A11c rows this mainly captures '
    'the two zero-duration yields per write, where stream re-query '
    'completion and listener microtasks can run.',
  );
  buf.writeln();
  buf.writeln('## Interpretation');
  buf.writeln();
  buf.writeln(
    'See `experiments/135-writer-sqlite-wall-split.md` for the decision '
    'and follow-up notes attached to these numbers.',
  );
  return buf.toString();
}

Future<AuditScenarioResult> _medianA11cScenario(
  Database db, {
  required String name,
  required int streamCount,
  required String updateSql,
  required String valuePrefix,
}) async {
  var pass = 0;
  return _medianScenario(() {
    final passId = pass++;
    return runA11cScenario(
      db,
      name: name,
      streamCount: streamCount,
      updateSql: updateSql,
      valueFor: (writeIndex) => '${valuePrefix}_${passId}_$writeIndex',
    );
  });
}

Future<AuditScenarioResult> _medianScenario(
  Future<AuditScenarioResult> Function() run,
) async {
  for (var i = 0; i < _warmupPasses; i++) {
    await run();
  }

  final results = <AuditScenarioResult>[];
  for (var i = 0; i < _measuredPasses; i++) {
    results.add(await run());
  }

  final first = results.first;
  final keys = <String>{for (final result in results) ...result.counters.keys};
  return AuditScenarioResult(
    workload: first.workload,
    shape: '${first.shape}, median of $_measuredPasses',
    wallUs: _medianInt([for (final result in results) result.wallUs]),
    emissions: _medianInt([for (final result in results) result.emissions]),
    observedHits: _medianInt([
      for (final result in results) result.observedHits,
    ]),
    counters: {
      for (final key in keys)
        key: _medianInt([
          for (final result in results) result.counters[key] ?? 0,
        ]),
    },
  );
}

Future<AuditScenarioResult> _medianKeyedPkScenario() {
  return _medianScenario(runKeyedPkScenario);
}

int _medianInt(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

int _nonNegative(int value) => value < 0 ? 0 : value;
