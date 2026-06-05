// ignore_for_file: avoid_print
//
// Workload driver for `run_tracelite_profile.dart`.
//
// Tracelite owns the persisted trace, workload summary, insights, graph data,
// and comparison artifacts. This helper only runs representative resqlite work
// under `RESQLITE_PROFILE=true` and `RESQLITE_TRACELITE=true` so application
// spans, counters, diagnostics, and RSS samples reach the active trace region.

import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';
import 'package:resqlite/src/tracelite_profile.dart';

import 'profile_reporting.dart';
import 'profiled_database.dart';
import 'workloads.dart';

const int _churnSize = 10000;

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _usage(exitCode: 0);
  }
  if (args.isNotEmpty) {
    stderr.writeln('unexpected argument: ${args.first}');
    _usage();
  }
  if (!kProfileMode || !kTraceliteProfileMode) {
    stderr.writeln(
      'run_tracelite_workloads.dart requires both '
      '-DRESQLITE_PROFILE=true and -DRESQLITE_TRACELITE=true.',
    );
    exit(64);
  }

  print('# resqlite tracelite workloads');
  print('');
  print('profile_mode_enabled: $kProfileMode');
  print('tracelite_profile_enabled: $kTraceliteProfileMode');
  print('tracelite_region: ${Platform.environment['TRACELITE_REGION'] ?? ''}');
  print('');

  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite_tracelite_profile_',
  );
  final db = await Database.open('${tempDir.path}/test.db');
  final profiled = ProfiledDatabase(db);

  try {
    await setupSchema(profiled);
    await warmup(profiled);

    print('=== Workload Z: Noop Baseline (SELECT 1 / UPDATE WHERE 1=0) ===');
    final noop = await _runWorkload(
      name: 'noop',
      profiled: profiled,
      body: (iter) => workloadNoop(profiled, iter),
    );
    final noopSummary = summarizeSamples(noop.samples);
    final readerFloor = (noopSummary['select'] as Map)['median_us'] as int;
    final writerFloor = (noopSummary['execute'] as Map)['median_us'] as int;
    _reportWorkload(noop, readerFloor: null, writerFloor: null);
    print('  reader dispatch floor ~= $readerFloor us');
    print('  writer dispatch floor ~= $writerFloor us');

    print('');
    print('=== Workload A: Single Inserts ===');
    final singleInsert = await _runWorkload(
      name: 'single_insert',
      profiled: profiled,
      body: (iter) => workloadSingleInserts(profiled, iter),
    );
    _reportWorkload(
      singleInsert,
      readerFloor: readerFloor,
      writerFloor: writerFloor,
    );

    print('');
    print('=== Workload B: Point Queries ===');
    final pointQuery = await _runWorkload(
      name: 'point_query',
      profiled: profiled,
      body: (iter) => workloadPointQuery(profiled, iter),
    );
    _reportWorkload(
      pointQuery,
      readerFloor: readerFloor,
      writerFloor: writerFloor,
    );

    print('');
    print('=== Workload C: Merge Rounds ===');
    final mergeRounds = await _runWorkload(
      name: 'merge_rounds',
      profiled: profiled,
      body: (iter) => workloadMergeRounds(profiled, iter),
    );
    _reportWorkload(
      mergeRounds,
      readerFloor: readerFloor,
      writerFloor: writerFloor,
    );
  } finally {
    TraceliteProfile.detach();
    await profiled.close();
    await tempDir.delete(recursive: true);
  }
}

Future<ProfileWorkloadResult> _runWorkload({
  required String name,
  required ProfiledDatabase profiled,
  required Future<void> Function(int iter) body,
  int iterations = measureIterations,
}) async {
  _churnHeap();
  _churnHeap();

  final rssBeforeBytes = _rssBytes();
  final rssBefore = _rssMB(rssBeforeBytes);
  final diagBefore = await profiled.raw.diagnostics();
  final countersBefore = ProfileCounters.snapshot();
  final traceCorrelationId = TraceliteProfile.nextCorrelationId();
  final traceNameId = TraceliteProfile.internString(name);

  TraceliteProfile.diagnostics(diagBefore, correlationId: traceCorrelationId);
  TraceliteProfile.profileCounters(
    countersBefore,
    correlationId: traceCorrelationId,
  );
  var peakRssBytes = rssBeforeBytes;

  profiled.samples.clear();
  Future<void> runMeasuredLoop() async {
    for (var iter = 0; iter < iterations; iter++) {
      await body(iter);
      final rssNow = _rssBytes();
      if (rssNow > peakRssBytes) peakRssBytes = rssNow;
    }
  }

  await TraceliteProfile.traceAsync(
    TraceliteResqliteSpans.profileWorkload,
    runMeasuredLoop,
    correlationId: traceCorrelationId,
    beginArgs: [traceNameId, iterations],
    endArgs: (_) => [profiled.samples.length],
  );

  final rssAfterBytes = _rssBytes();
  final rssAfter = _rssMB(rssAfterBytes);
  final diagAfter = await profiled.raw.diagnostics();
  final countersAfter = ProfileCounters.snapshot();
  TraceliteProfile.diagnostics(diagAfter, correlationId: traceCorrelationId);
  TraceliteProfile.profileCounters(
    countersAfter,
    correlationId: traceCorrelationId,
  );
  TraceliteProfile.rss(
    beforeBytes: rssBeforeBytes,
    afterBytes: rssAfterBytes,
    peakBytes: peakRssBytes,
    correlationId: traceCorrelationId,
  );

  return ProfileWorkloadResult(
    name: name,
    iterations: iterations,
    samples: List.of(profiled.samples),
    rssBeforeMB: rssBefore,
    rssAfterMB: rssAfter,
    rssPeakMB: _rssMB(peakRssBytes),
    diagnosticsBefore: diagBefore,
    diagnosticsAfter: diagAfter,
    countersBefore: countersBefore,
    countersAfter: countersAfter,
  );
}

int _rssBytes() => ProcessInfo.currentRss;

double _rssMB(int bytes) => bytes / (1024 * 1024);

void _churnHeap() {
  final junk = <Map<String, Object?>>[];
  for (var i = 0; i < _churnSize; i++) {
    junk.add({'a': i, 'b': 'x$i', 'c': i * 1.5});
  }
  junk.clear();
}

void _reportWorkload(
  ProfileWorkloadResult result, {
  required int? readerFloor,
  required int? writerFloor,
}) {
  print(
    formatProfileWorkloadReport(
      result,
      readerFloor: readerFloor,
      writerFloor: writerFloor,
    ),
  );
}

Never _usage({int exitCode = 64}) {
  stderr.writeln('usage:');
  stderr.writeln('  dart run \\');
  stderr.writeln('    -DRESQLITE_PROFILE=true \\');
  stderr.writeln('    -DRESQLITE_TRACELITE=true \\');
  stderr.writeln('    benchmark/profile/run_tracelite_workloads.dart');
  stderr.writeln('');
  stderr.writeln(
    'This helper expects TRACELITE_REGION and TRACELITE_RUNTIME to be set by '
    'benchmark/profile/run_tracelite_profile.dart.',
  );
  exit(exitCode);
}
