library;

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';

import 'profile_sample.dart';
import 'workloads.dart';

class ProfileWorkloadResult {
  ProfileWorkloadResult({
    required this.name,
    required this.iterations,
    required this.samples,
    required this.rssBeforeMB,
    required this.rssAfterMB,
    required this.rssPeakMB,
    required this.diagnosticsBefore,
    required this.diagnosticsAfter,
    required this.countersBefore,
    required this.countersAfter,
  });

  final String name;
  final int iterations;
  final List<ProfileSample> samples;
  final double rssBeforeMB;
  final double rssAfterMB;
  final double rssPeakMB;
  final Diagnostics diagnosticsBefore;
  final Diagnostics diagnosticsAfter;
  final Map<String, int>? countersBefore;
  final Map<String, int>? countersAfter;

  double get rssDeltaMB => rssAfterMB - rssBeforeMB;

  Map<String, int>? get counterDelta {
    if (countersBefore == null || countersAfter == null) return null;
    return ProfileCounters.diff(countersBefore!, countersAfter!);
  }
}

Map<String, int> diagnosticsJson(Diagnostics d) => {
  'sqlite_page_cache_bytes': d.sqlitePageCacheBytes,
  'sqlite_schema_bytes': d.sqliteSchemaBytes,
  'sqlite_stmt_bytes': d.sqliteStmtBytes,
  'wal_bytes': d.walBytes,
};

Map<String, int> diagnosticsDelta(Diagnostics before, Diagnostics after) => {
  'sqlite_page_cache_bytes_delta':
      after.sqlitePageCacheBytes - before.sqlitePageCacheBytes,
  'sqlite_schema_bytes_delta':
      after.sqliteSchemaBytes - before.sqliteSchemaBytes,
  'sqlite_stmt_bytes_delta': after.sqliteStmtBytes - before.sqliteStmtBytes,
  'wal_bytes_delta': after.walBytes - before.walBytes,
};

Map<String, Object?> profileSamplesArtifact(
  List<ProfileSample> samples, {
  required int? readerFloor,
  required int? writerFloor,
}) {
  return {
    'samples': samples.map((s) => s.toJson()).toList(),
    'summary': summarizeSamples(
      samples,
      readerFloor: readerFloor,
      writerFloor: writerFloor,
    ),
  };
}

Map<String, Object?> profileWorkloadArtifact(
  ProfileWorkloadResult workload, {
  required int? readerFloor,
  required int? writerFloor,
}) {
  final artifact = profileSamplesArtifact(
    workload.samples,
    readerFloor: readerFloor,
    writerFloor: writerFloor,
  );
  artifact['iterations'] = workload.iterations;
  artifact['memory'] = {
    'rss_before_mb': double.parse(workload.rssBeforeMB.toStringAsFixed(3)),
    'rss_after_mb': double.parse(workload.rssAfterMB.toStringAsFixed(3)),
    'rss_peak_mb': double.parse(workload.rssPeakMB.toStringAsFixed(3)),
    'rss_delta_mb': double.parse(workload.rssDeltaMB.toStringAsFixed(3)),
    'diagnostics_before': diagnosticsJson(workload.diagnosticsBefore),
    'diagnostics_after': diagnosticsJson(workload.diagnosticsAfter),
    'diagnostics_delta': diagnosticsDelta(
      workload.diagnosticsBefore,
      workload.diagnosticsAfter,
    ),
    if (workload.counterDelta != null)
      'profile_counters_delta': workload.counterDelta,
  };
  return artifact;
}

String formatProfileSamplesReport(
  List<ProfileSample> samples, {
  required int? readerFloor,
  required int? writerFloor,
}) {
  final summary = summarizeSamples(
    samples,
    readerFloor: readerFloor,
    writerFloor: writerFloor,
  );
  final buf = StringBuffer();
  buf.writeln('${samples.length} samples collected.');
  for (final entry in summary.entries) {
    final s = entry.value! as Map<String, Object?>;
    final workPart = s.containsKey('work_us_median')
        ? ' work=${s['work_us_median']}μs'
        : '';
    buf.writeln(
      '  ${entry.key.padRight(14)} '
      'count=${s['count']} '
      'min=${s['min_us']}μs '
      'p50=${s['median_us']}μs '
      'p90=${s['p90_us']}μs '
      'p99=${s['p99_us']}μs '
      'max=${s['max_us']}μs'
      '$workPart',
    );
  }
  return buf.toString().trimRight();
}

String formatProfileWorkloadReport(
  ProfileWorkloadResult workload, {
  required int? readerFloor,
  required int? writerFloor,
}) {
  final buf = StringBuffer()
    ..writeln(
      formatProfileSamplesReport(
        workload.samples,
        readerFloor: readerFloor,
        writerFloor: writerFloor,
      ),
    );
  final delta = diagnosticsDelta(
    workload.diagnosticsBefore,
    workload.diagnosticsAfter,
  );
  buf.writeln(
    '  memory:        '
    'rss Δ=${workload.rssDeltaMB.toStringAsFixed(2)} MB  '
    'rss peak=${workload.rssPeakMB.toStringAsFixed(2)} MB  '
    'page cache Δ=${delta['sqlite_page_cache_bytes_delta']} B  '
    'stmt Δ=${delta['sqlite_stmt_bytes_delta']} B  '
    'wal Δ=${delta['wal_bytes_delta']} B',
  );
  final cdelta = workload.counterDelta;
  if (cdelta != null) {
    final nonZero = cdelta.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (nonZero.isNotEmpty) {
      buf.writeln(
        '  counters:      '
        '${nonZero.map((e) => '${e.key}=${e.value}').join('  ')}',
      );
    }
  }
  return buf.toString().trimRight();
}
