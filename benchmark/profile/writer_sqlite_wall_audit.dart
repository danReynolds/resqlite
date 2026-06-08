// ignore_for_file: avoid_print
//
// Writer SQLite wall split audit - exp 147.
//
// This measurement consumes the stream-rerun-dispatch signal-map blocker:
// future dispatch work needs to know how much writer-side burst wall is
// SQLite work, stream invalidation, or remaining Dart/IPC overhead.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/writer_sqlite_wall_audit.dart --markdown

import 'dart:io';

import 'package:resqlite/src/profile_mode.dart';

import 'audit_workloads.dart';

final class _AuditRow {
  _AuditRow({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.writerSqliteUs,
    required this.writerSqliteCount,
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
    writerSqliteUs: r.counters['writer_sqlite_us']!,
    writerSqliteCount: r.counters['writer_sqlite_count']!,
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
  final int writerSqliteUs;
  final int writerSqliteCount;
  final int invalidateUs;
  final int invalidateCount;
  final int intersectionUs;
  final int intersectionEntries;
  final int parkedTotal;
  final int maxParked;
  final int emissions;

  int get residualUs => wallUs - writerSqliteUs - invalidateUs;
  double get wallMs => wallUs / 1000.0;
  double get sqliteFractionPct =>
      wallUs == 0 ? 0.0 : (writerSqliteUs / wallUs) * 100.0;
  double get invalidateFractionPct =>
      wallUs == 0 ? 0.0 : (invalidateUs / wallUs) * 100.0;
  double get residualFractionPct =>
      wallUs == 0 ? 0.0 : (residualUs / wallUs) * 100.0;
  double get sqliteUsPerWrite =>
      writerSqliteCount == 0 ? 0.0 : writerSqliteUs / writerSqliteCount;
  double get invalidateUsPerWrite =>
      invalidateCount == 0 ? 0.0 : invalidateUs / invalidateCount;
  double get nsPerIntersectionEntry => intersectionEntries == 0
      ? 0.0
      : (intersectionUs * 1000.0) / intersectionEntries;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; writer SQLite counters will stay zero. '
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
      'benchmark/profile/results/exp-147-writer-sqlite-wall-aggregate.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<List<AuditScenarioResult>> _runA11cAudit() async {
  final setup = await setupA11cDb(prefix: 'writer_sqlite_wall_a11c_');
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
  buf.writeln('# Experiment 147 - Writer SQLite Wall Split Audit');
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
  buf.writeln();
  buf.writeln(
    '`wall_us` is writer-side burst wall; the stopwatch stops on the '
    'last write. `writer_sqlite_us` is measured inside the writer isolate '
    'around the SQLite-facing write call and carried back in the write '
    'response. `residual_us = wall_us - writer_sqlite_us - invalidate_us`.',
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
    '| workload | shape | wall_ms | writer_sqlite_us | writer_sqlite_count | '
    'invalidate_us | invalidate_count | residual_us | parked_total | '
    'max_parked | emissions |',
  );
  buf.writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.writerSqliteUs} | ${row.writerSqliteCount} | '
      '${row.invalidateUs} | ${row.invalidateCount} | '
      '${row.residualUs} | ${row.parkedTotal} | ${row.maxParked} | '
      '${row.emissions} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived fractions');
  buf.writeln();
  buf.writeln(
    '| workload | SQLite / wall | invalidation / wall | residual / wall | '
    'SQLite us/write | invalidation us/write | ns/intersection entry |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | '
      '${row.sqliteFractionPct.toStringAsFixed(2)}% | '
      '${row.invalidateFractionPct.toStringAsFixed(2)}% | '
      '${row.residualFractionPct.toStringAsFixed(2)}% | '
      '${row.sqliteUsPerWrite.toStringAsFixed(2)} | '
      '${row.invalidateUsPerWrite.toStringAsFixed(2)} | '
      '${row.nsPerIntersectionEntry.toStringAsFixed(0)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `writer_sqlite_us` covers the SQLite-facing write call on the writer '
    'isolate: single-write execution or batch execution. Dirty-set harvest '
    'and reply send are outside this counter.',
  );
  buf.writeln(
    '- `invalidate_us` is the main-isolate synchronous stream invalidation '
    'body already audited by exp 121.',
  );
  buf.writeln(
    '- `residual_us` is the remaining local wall budget: writer isolate '
    'round-trip, dirty-set harvest, main-isolate await/reply scheduling, '
    'and any measurement overhead.',
  );
  return buf.toString();
}
