// ignore_for_file: avoid_print
/// Peer comparison: resqlite vs sqlite_async on sequential single-row lookups.
///
/// Runs each library in a separate process to avoid native symbol conflicts.
/// Measures 500 sequential single-row lookups by ID after seeding 100 rows.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  print('');
  print('=== Peer Comparison: Sequential Single-Row Lookups ===');
  print('');
  print('Seeding: 100 rows, 6 columns');
  print('Workload: 500 sequential SELECT ... WHERE id = ? lookups');
  print('Each library runs in a separate process.');
  print('');

  final scriptDir = File(Platform.script.toFilePath()).parent.path;

  // Run resqlite benchmark.
  print('Running resqlite...');
  final resqliteResult =
      await _runBenchmark('$scriptDir/peer_comparison_resqlite.dart');

  // Run sqlite_async benchmark.
  print('Running sqlite_async...');
  final asyncResult =
      await _runBenchmark('$scriptDir/peer_comparison_sqlite_async.dart');

  if (resqliteResult == null || asyncResult == null) {
    print('One or both benchmarks failed. Cannot compare.');
    exit(1);
  }

  // Print comparison.
  print('');
  print('--- Results ---');
  print('');
  print('${'Metric'.padRight(40)} ${'resqlite'.padLeft(14)} '
      '${'sqlite_async'.padLeft(14)} ${'ratio'.padLeft(10)}');
  print('-' * 82);

  void compare(String label, String key, {bool lowerIsBetter = true}) {
    final sq = resqliteResult[key];
    final as_ = asyncResult[key];
    if (sq == null || as_ == null) {
      print('${label.padRight(40)} ${'N/A'.padLeft(14)} ${'N/A'.padLeft(14)}');
      return;
    }
    final sqVal = (sq as num).toDouble();
    final asVal = (as_ as num).toDouble();
    final ratio = asVal / sqVal;
    final ratioStr = '${ratio.toStringAsFixed(2)}x';
    print(
      '${label.padRight(40)} '
      '${_formatUs(sqVal).padLeft(14)} '
      '${_formatUs(asVal).padLeft(14)} '
      '${ratioStr.padLeft(10)}',
    );
  }

  compare('Total 500 lookups (us)', 'total_500_us');
  compare('Per-query median (us)', 'per_query_median_us');
  compare('Per-query p95 (us)', 'per_query_p95_us');
  compare('Per-query p99 (us)', 'per_query_p99_us');
  compare('Per-query min (us)', 'per_query_min_us');
  compare('Per-query max (us)', 'per_query_max_us');

  if (resqliteResult['warmup_total_us'] != null &&
      asyncResult['warmup_total_us'] != null) {
    print('');
    compare('Warmup total (us)', 'warmup_total_us');
  }

  // Print raw per-query distributions if available.
  print('');
  print('--- Distribution ---');
  if (resqliteResult['histogram'] != null) {
    print('');
    print('resqlite:');
    print(resqliteResult['histogram']);
  }
  if (asyncResult['histogram'] != null) {
    print('');
    print('sqlite_async:');
    print(asyncResult['histogram']);
  }

  print('');
  exit(0);
}

String _formatUs(double us) {
  if (us >= 1000) {
    return '${(us / 1000).toStringAsFixed(2)} ms';
  }
  return '${us.toStringAsFixed(1)} us';
}

Future<Map<String, dynamic>?> _runBenchmark(String scriptPath) async {
  final dartExe = Platform.resolvedExecutable;
  final result = await Process.run(
    dartExe,
    ['run', scriptPath],
    workingDirectory: Directory.current.path,
    environment: Platform.environment,
  );

  if (result.exitCode != 0) {
    print('  FAILED (exit code ${result.exitCode})');
    print('  stderr: ${result.stderr}');
    print('  stdout: ${result.stdout}');
    return null;
  }

  final stdout = result.stdout as String;
  // Find JSON object on its own line (between RESULT_START and RESULT_END markers).
  final jsonMatch = RegExp(r'RESULT_JSON:(.+)$', multiLine: true).firstMatch(stdout);
  if (jsonMatch == null) {
    print('  No JSON output found');
    print('  stdout: $stdout');
    return null;
  }

  try {
    return jsonDecode(jsonMatch.group(1)!.trim()) as Map<String, dynamic>;
  } catch (e) {
    print('  Failed to parse JSON: $e');
    print('  raw: ${jsonMatch.group(1)}');
    return null;
  }
}
