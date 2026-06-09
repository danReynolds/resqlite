// ignore_for_file: avoid_print
//
// Writer request residual split audit - exp 150.
//
// Exp 147 showed that SQLite-facing writer calls are a minority of
// stream-fanout write-loop wall. Exp 148 then rejected plain reader-reply
// batching despite a real completion-counter reduction. This audit splits the
// remaining local budget before another implementation attempt:
//
//   - writer_request_us: main-isolate request round trip to the writer isolate
//   - writer_handler_us: writer-isolate active handler wall before reply send
//   - writer_dirty_harvest_us: dirty table/column harvest after SQLite writes
//   - invalidate_us: main-isolate stream invalidation body
//   - coordination_us: write-loop wall not covered by request or invalidation
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/writer_request_residual_audit.dart --markdown

import 'dart:io';

import 'package:resqlite/src/profile_mode.dart';

import 'audit_workloads.dart';

final class _AuditRow {
  _AuditRow({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.drainUs,
    required this.writerRequestUs,
    required this.writerRequestCount,
    required this.writerHandlerUs,
    required this.writerHandlerCount,
    required this.writerSqliteUs,
    required this.writerDirtyHarvestUs,
    required this.writerDirtyHarvestCount,
    required this.invalidateUs,
    required this.completionHandlerUs,
    required this.completionHandlerCount,
    required this.parkedTotal,
    required this.maxParked,
    required this.emissions,
  });

  factory _AuditRow.fromScenario(AuditScenarioResult r) {
    final burst = r.counters;
    final drained = r.countersAfterDrain ?? burst;
    return _AuditRow(
      workload: r.workload,
      shape: r.shape,
      wallUs: r.wallUs,
      drainUs: r.drainUs,
      writerRequestUs: burst['writer_request_us'] ?? 0,
      writerRequestCount: burst['writer_request_count'] ?? 0,
      writerHandlerUs: burst['writer_handler_us'] ?? 0,
      writerHandlerCount: burst['writer_handler_count'] ?? 0,
      writerSqliteUs: burst['writer_sqlite_us'] ?? 0,
      writerDirtyHarvestUs: burst['writer_dirty_harvest_us'] ?? 0,
      writerDirtyHarvestCount: burst['writer_dirty_harvest_count'] ?? 0,
      invalidateUs: burst['invalidate_us'] ?? 0,
      completionHandlerUs: drained['completion_handler_us'] ?? 0,
      completionHandlerCount: drained['completion_handler_count'] ?? 0,
      parkedTotal: burst['dispatcher_parked_total'] ?? 0,
      maxParked: burst['dispatcher_max_parked_concurrent'] ?? 0,
      emissions: r.emissions,
    );
  }

  final String workload;
  final String shape;
  final int wallUs;
  final int drainUs;
  final int writerRequestUs;
  final int writerRequestCount;
  final int writerHandlerUs;
  final int writerHandlerCount;
  final int writerSqliteUs;
  final int writerDirtyHarvestUs;
  final int writerDirtyHarvestCount;
  final int invalidateUs;
  final int completionHandlerUs;
  final int completionHandlerCount;
  final int parkedTotal;
  final int maxParked;
  final int emissions;

  int get totalUs => wallUs + drainUs;
  int get writerLocalOtherUs =>
      writerHandlerUs - writerSqliteUs - writerDirtyHarvestUs;
  int get transferResolutionUs => writerRequestUs - writerHandlerUs;
  int get coordinationUs => wallUs - writerRequestUs - invalidateUs;

  double get wallMs => wallUs / 1000.0;
  double get drainMs => drainUs / 1000.0;
  double get totalMs => totalUs / 1000.0;

  double _pct(int value, int denominator) =>
      denominator == 0 ? 0.0 : (value / denominator) * 100.0;

  double get requestWallPct => _pct(writerRequestUs, wallUs);
  double get handlerWallPct => _pct(writerHandlerUs, wallUs);
  double get sqliteWallPct => _pct(writerSqliteUs, wallUs);
  double get dirtyWallPct => _pct(writerDirtyHarvestUs, wallUs);
  double get invalidateWallPct => _pct(invalidateUs, wallUs);
  double get transferResolutionWallPct => _pct(transferResolutionUs, wallUs);
  double get coordinationWallPct => _pct(coordinationUs, wallUs);
  double get completionTotalPct => _pct(completionHandlerUs, totalUs);

  double get usPerRequest =>
      writerRequestCount == 0 ? 0.0 : writerRequestUs / writerRequestCount;
  double get usPerHandler =>
      writerHandlerCount == 0 ? 0.0 : writerHandlerUs / writerHandlerCount;
  double get usPerDirtyHarvest => writerDirtyHarvestCount == 0
      ? 0.0
      : writerDirtyHarvestUs / writerDirtyHarvestCount;
  double get usPerCompletion => completionHandlerCount == 0
      ? 0.0
      : completionHandlerUs / completionHandlerCount;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; writer residual counters will stay zero. '
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
      'benchmark/profile/results/exp-150-writer-request-residual-aggregate.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<List<AuditScenarioResult>> _runA11cAudit() async {
  final setup = await setupA11cDb(prefix: 'writer_request_residual_a11c_');
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
  buf.writeln('# Experiment 150 - Writer Request Residual Split Audit');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/writer_request_residual_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  buf.writeln();
  buf.writeln(
    '`wall_ms` is writer-side write-loop wall and stops on the last write. '
    '`drain_ms` is the post-burst quiet-window drain. Writer-side counters '
    'come from the burst-end snapshot; completion counters use the post-drain '
    'snapshot because reader replies usually finish after the write burst.',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/writer_request_residual_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | drain_ms | writer_request_us | '
    'writer_handler_us | writer_sqlite_us | writer_dirty_harvest_us | '
    'writer_local_other_us | transfer_resolution_us | invalidate_us | '
    'coordination_us | completion_handler_us | parked_total | max_parked | '
    'emissions |',
  );
  buf.writeln(
    '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.drainMs.toStringAsFixed(2)} | ${row.writerRequestUs} | '
      '${row.writerHandlerUs} | ${row.writerSqliteUs} | '
      '${row.writerDirtyHarvestUs} | ${row.writerLocalOtherUs} | '
      '${row.transferResolutionUs} | ${row.invalidateUs} | '
      '${row.coordinationUs} | ${row.completionHandlerUs} | '
      '${row.parkedTotal} | ${row.maxParked} | ${row.emissions} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived fractions');
  buf.writeln();
  buf.writeln(
    '| workload | request / wall | handler / wall | SQLite / wall | '
    'dirty harvest / wall | transfer+resolution / wall | '
    'invalidation / wall | coordination / wall | completion / total |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.requestWallPct.toStringAsFixed(2)}% | '
      '${row.handlerWallPct.toStringAsFixed(2)}% | '
      '${row.sqliteWallPct.toStringAsFixed(2)}% | '
      '${row.dirtyWallPct.toStringAsFixed(2)}% | '
      '${row.transferResolutionWallPct.toStringAsFixed(2)}% | '
      '${row.invalidateWallPct.toStringAsFixed(2)}% | '
      '${row.coordinationWallPct.toStringAsFixed(2)}% | '
      '${row.completionTotalPct.toStringAsFixed(2)}% |',
    );
  }
  buf.writeln();
  buf.writeln('## Per-event costs');
  buf.writeln();
  buf.writeln(
    '| workload | request_us/op | handler_us/op | dirty_harvest_us/op | '
    'completion_us/callback |',
  );
  buf.writeln('|---|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.usPerRequest.toStringAsFixed(2)} | '
      '${row.usPerHandler.toStringAsFixed(2)} | '
      '${row.usPerDirtyHarvest.toStringAsFixed(2)} | '
      '${row.usPerCompletion.toStringAsFixed(2)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `writer_request_us` is the main-isolate round trip to the writer '
    'isolate. It includes writer queueing, request transfer, handler work, '
    'reply transfer, and main-isolate response scheduling.',
  );
  buf.writeln(
    '- `writer_handler_us` is writer-isolate active work before the response '
    'is sent. `writer_local_other_us` is handler work that is neither SQLite '
    'nor dirty harvest.',
  );
  buf.writeln(
    '- `transfer_resolution_us = writer_request_us - writer_handler_us`; it '
    'contains message transfer, reply send/copy, writer queue wait, and '
    'main-isolate request resolution.',
  );
  buf.writeln(
    '- `coordination_us = wall_us - writer_request_us - invalidate_us`; on '
    'A11c this includes the deliberate microtask yields between writes and '
    'any other write-loop scheduling outside the writer request and '
    'synchronous invalidation body.',
  );
  return buf.toString();
}
