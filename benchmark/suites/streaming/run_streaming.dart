// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// Runs streaming benchmarks for resqlite and sqlite_async in separate
/// processes (to avoid native symbol conflicts), then combines results.
Future<void> main() async {
  print('');
  print('=== Streaming Benchmarks ===');
  print('');
  print('Running each library in a separate process to avoid symbol conflicts.');
  print('');

  final scriptDir = File(Platform.script.toFilePath()).parent.path;

  // Run resqlite benchmark.
  print('Running resqlite streams...');
  final resqliteResult = await _runBenchmark('$scriptDir/resqlite_streams.dart');

  // Run sqlite_async benchmark.
  print('Running sqlite_async streams...');
  final asyncResult = await _runBenchmark('$scriptDir/sqlite_async_streams.dart');

  if (resqliteResult == null || asyncResult == null) {
    print('One or both benchmarks failed. Cannot compare.');
    exit(1);
  }

  // Print comparison.
  print('');
  print('--- Results ---');
  print('');
  print('${'Metric'.padRight(35)} ${'resqlite'.padLeft(12)} ${'sqlite_async'.padLeft(14)} ${'winner'.padLeft(10)}');
  print('-' * 75);

  void compare(String label, String key) {
    final sq = resqliteResult[key];
    final as_ = asyncResult[key];
    if (sq == null || as_ == null) {
      print('${label.padRight(35)} ${'N/A'.padLeft(12)} ${'N/A'.padLeft(14)}');
      return;
    }
    final sqUs = sq as int;
    final asUs = as_ as int;
    if (sqUs < 0 || asUs < 0) {
      final sqDisplay = sqUs < 0 ? 'unsupported' : '${(sqUs / 1000).toStringAsFixed(2)} ms';
      final asDisplay = asUs < 0 ? 'unsupported' : '${(asUs / 1000).toStringAsFixed(2)} ms';
      print(
        '${label.padRight(35)} '
        '${sqDisplay.padLeft(12)} '
        '${asDisplay.padLeft(14)} '
        '${''.padLeft(10)}',
      );
      return;
    }
    final sqMs = sqUs / 1000;
    final asMs = asUs / 1000;
    final winner = sqMs < asMs ? 'resqlite' : 'async';
    print(
      '${label.padRight(35)} '
      '${sqMs.toStringAsFixed(2).padLeft(10)} ms '
      '${asMs.toStringAsFixed(2).padLeft(12)} ms '
      '${winner.padLeft(10)}',
    );
  }

  compare('Initial emission', 'initial_emission_us');
  compare('Invalidation latency', 'invalidation_latency_us');
  compare('Fan-out (10 streams)', 'fanout_10_streams_us');

  print('');
  exit(0);
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
    return null;
  }

  // The benchmark script outputs JSON. Find it anywhere in stdout.
  final stdout = result.stdout as String;
  final jsonStart = stdout.lastIndexOf('{');
  final jsonEnd = stdout.lastIndexOf('}');
  if (jsonStart == -1 || jsonEnd == -1 || jsonEnd < jsonStart) {
    print('  No JSON output found');
    print('  stdout: $stdout');
    return null;
  }

  try {
    return jsonDecode(stdout.substring(jsonStart, jsonEnd + 1)) as Map<String, dynamic>;
  } catch (e) {
    print('  Failed to parse JSON: $e');
    return null;
  }
}
