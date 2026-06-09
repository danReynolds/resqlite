// ignore_for_file: avoid_print
//
// Residual writer/request wall split audit - exp 149.
//
// Exp 147 split writer-side burst wall into SQLite-facing call,
// stream invalidation, and a residual "writer/request" bucket
// (71.8 % of A11c overlap wall, 63.3 % of keyed-PK wall). Exp 148
// rejected plain reader-reply batching as the next implementation
// candidate. This audit subdivides exp 147's residual into named
// sub-buckets so the next dispatch-area experiment can target the
// largest one.
//
// Counters introduced for this experiment (see profile_counters.dart):
//
// - `writer_handle_us` / `writer_handle_count` — total per-request
//   writer-isolate handler wall (includes SQLite + dirty harvest +
//   writer-internal overhead, excludes the writer's own SendPort send
//   and the main-isolate reply handler).
// - `writer_dirty_us` / `writer_dirty_count` — `getDirtyTableDependencies`
//   cost on the writer isolate.
// - `main_writer_reply_us` / `main_writer_reply_count` — main-isolate
//   `Writer._request<T>` reply handler wall (port close, exception
//   unwrap, completer.complete).
//
// Derived per workload:
//
//   writer_send_us = writer_handle_us - writer_sqlite_us - writer_dirty_us
//   rest_us        = wall_us
//                  - writer_handle_us
//                  - invalidate_us
//                  - main_writer_reply_us
//
// `writer_send_us` approximates "writer reply send" (residual writer
// handler overhead after SQLite + dirty); `rest_us` covers main-isolate
// inter-request scheduling: mutex acquisition, request build, awaits
// between writes, etc.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/residual_writer_wall_audit.dart --markdown

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
    required this.writerHandleUs,
    required this.writerHandleCount,
    required this.writerDirtyUs,
    required this.writerDirtyCount,
    required this.invalidateUs,
    required this.mainWriterReplyUs,
    required this.mainWriterReplyCount,
    required this.completionHandlerUs,
    required this.completionHandlerCount,
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
    writerHandleUs: r.counters['writer_handle_us']!,
    writerHandleCount: r.counters['writer_handle_count']!,
    writerDirtyUs: r.counters['writer_dirty_us']!,
    writerDirtyCount: r.counters['writer_dirty_count']!,
    invalidateUs: r.counters['invalidate_us']!,
    mainWriterReplyUs: r.counters['main_writer_reply_us']!,
    mainWriterReplyCount: r.counters['main_writer_reply_count']!,
    completionHandlerUs: r.counters['completion_handler_us']!,
    completionHandlerCount: r.counters['completion_handler_count']!,
    parkedTotal: r.counters['dispatcher_parked_total']!,
    maxParked: r.counters['dispatcher_max_parked_concurrent']!,
    emissions: r.emissions,
  );

  final String workload;
  final String shape;
  final int wallUs;
  final int writerSqliteUs;
  final int writerSqliteCount;
  final int writerHandleUs;
  final int writerHandleCount;
  final int writerDirtyUs;
  final int writerDirtyCount;
  final int invalidateUs;
  final int mainWriterReplyUs;
  final int mainWriterReplyCount;
  final int completionHandlerUs;
  final int completionHandlerCount;
  final int parkedTotal;
  final int maxParked;
  final int emissions;

  int get writerSendUs => writerHandleUs - writerSqliteUs - writerDirtyUs;
  int get restUs => wallUs - writerHandleUs - invalidateUs - mainWriterReplyUs;
  double get wallMs => wallUs / 1000.0;
  double get sqliteFractionPct =>
      wallUs == 0 ? 0.0 : (writerSqliteUs / wallUs) * 100.0;
  double get dirtyFractionPct =>
      wallUs == 0 ? 0.0 : (writerDirtyUs / wallUs) * 100.0;
  double get sendFractionPct =>
      wallUs == 0 ? 0.0 : (writerSendUs / wallUs) * 100.0;
  double get invalidateFractionPct =>
      wallUs == 0 ? 0.0 : (invalidateUs / wallUs) * 100.0;
  double get mainReplyFractionPct =>
      wallUs == 0 ? 0.0 : (mainWriterReplyUs / wallUs) * 100.0;
  double get restFractionPct => wallUs == 0 ? 0.0 : (restUs / wallUs) * 100.0;
  double get completionFractionPct =>
      wallUs == 0 ? 0.0 : (completionHandlerUs / wallUs) * 100.0;
  double get handleUsPerWrite =>
      writerHandleCount == 0 ? 0.0 : writerHandleUs / writerHandleCount;
  double get dirtyUsPerWrite =>
      writerDirtyCount == 0 ? 0.0 : writerDirtyUs / writerDirtyCount;
  double get mainReplyUsPerWrite => mainWriterReplyCount == 0
      ? 0.0
      : mainWriterReplyUs / mainWriterReplyCount;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; residual writer counters will stay zero. '
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
      'benchmark/profile/results/exp-149-residual-writer-wall-aggregate.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<List<AuditScenarioResult>> _runA11cAudit() async {
  final setup = await setupA11cDb(prefix: 'residual_writer_wall_a11c_');
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
  buf.writeln('# Experiment 149 - Residual Writer/Request Wall Split');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/residual_writer_wall_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  buf.writeln();
  buf.writeln(
    '`wall_us` is writer-side burst wall; the stopwatch stops on the last '
    'write. `writer_handle_us` is the per-request writer-isolate handler '
    'wall (SQLite + dirty harvest + writer-internal overhead). '
    '`writer_send_us = writer_handle_us - writer_sqlite_us - writer_dirty_us` '
    'approximates writer reply construction beyond SQLite/dirty. '
    '`main_writer_reply_us` is the main-isolate `Writer._request<T>` reply '
    'handler wall. `rest_us = wall_us - writer_handle_us - invalidate_us - '
    'main_writer_reply_us` covers main-isolate inter-request scheduling.',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/residual_writer_wall_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | writer_sqlite_us | writer_dirty_us | '
    'writer_send_us | invalidate_us | main_reply_us | completion_us | '
    'rest_us | parked_total | max_parked | emissions |',
  );
  buf.writeln(
    '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.writerSqliteUs} | ${row.writerDirtyUs} | ${row.writerSendUs} | '
      '${row.invalidateUs} | ${row.mainWriterReplyUs} | '
      '${row.completionHandlerUs} | ${row.restUs} | '
      '${row.parkedTotal} | ${row.maxParked} | ${row.emissions} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived fractions');
  buf.writeln();
  buf.writeln(
    '| workload | SQLite / wall | dirty / wall | send / wall | '
    'invalidation / wall | main_reply / wall | completion / wall | '
    'rest / wall |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | '
      '${row.sqliteFractionPct.toStringAsFixed(2)}% | '
      '${row.dirtyFractionPct.toStringAsFixed(2)}% | '
      '${row.sendFractionPct.toStringAsFixed(2)}% | '
      '${row.invalidateFractionPct.toStringAsFixed(2)}% | '
      '${row.mainReplyFractionPct.toStringAsFixed(2)}% | '
      '${row.completionFractionPct.toStringAsFixed(2)}% | '
      '${row.restFractionPct.toStringAsFixed(2)}% |',
    );
  }
  buf.writeln();
  buf.writeln('## Per-write averages');
  buf.writeln();
  buf.writeln(
    '| workload | writer_handle us/write | writer_dirty us/write | '
    'main_reply us/write |',
  );
  buf.writeln('|---|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | '
      '${row.handleUsPerWrite.toStringAsFixed(2)} | '
      '${row.dirtyUsPerWrite.toStringAsFixed(2)} | '
      '${row.mainReplyUsPerWrite.toStringAsFixed(2)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `writer_sqlite_us` matches exp 147 — the SQLite-facing write call on '
    'the writer isolate.',
  );
  buf.writeln(
    '- `writer_dirty_us` is the writer-isolate dirty-set harvest call '
    '(`getDirtyTableDependencies`).',
  );
  buf.writeln(
    '- `writer_send_us` is writer-handler residual after SQLite + dirty: '
    'response construction, internal handler bookkeeping. Excludes the '
    'SendPort send itself.',
  );
  buf.writeln(
    '- `invalidate_us` is the main-isolate `StreamEngine.onDependencyChanges` '
    'body audited by exp 121.',
  );
  buf.writeln(
    '- `main_reply_us` is the main-isolate `Writer._request<T>` reply '
    'handler wall — port close, exception unwrap, completer.complete. The '
    'downstream `await` continuation runs in a subsequent microtask and is '
    'not counted here.',
  );
  buf.writeln(
    '- `completion_us` is the burst-end value of exp 136 `completion_handler_us`. '
    'On A11c overlap most reader replies fire AFTER the stopwatch stops, so '
    'this captures only the reader-completion work that ran BETWEEN writes '
    'during the burst, NOT the post-burst drain. It overlaps with `rest_us` '
    'because reader replies execute inside the same main-isolate event-loop '
    'turns that the harness `await Future<void>.delayed(Duration.zero)` pairs '
    'release.',
  );
  buf.writeln(
    '- `rest_us` is everything else inside the writer-burst wall: writer '
    'mutex acquisition, request build/serialize, the awaits in the harness '
    'loop, in-burst reader-pool completion work, and any measurement '
    'overhead.',
  );
  return buf.toString();
}
