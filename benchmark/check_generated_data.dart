import 'dart:convert';
import 'dart:io';

import 'generate_devices.dart' as generate_devices;
import 'generate_history.dart' as generate_history;

Future<void> main() async {
  final mismatches = <String>[];

  await _checkJsonFile(
    label: 'devices.json',
    currentPath: 'docs/benchmarks/devices.json',
    buildExpected: (generatedAt) => generate_devices.buildDevicesData(
      hardwareResultsMarkdown: File(
        'benchmark/HARDWARE_RESULTS.md',
      ).readAsStringSync(),
      resultsDir: Directory('benchmark/results'),
      generatedAt: generatedAt,
    ),
    mismatches: mismatches,
  );

  await _checkJsonFile(
    label: 'history.json',
    currentPath: 'docs/experiments/history.json',
    buildExpected: (generatedAt) => generate_history.buildHistoryData(
      resultsDir: Directory('benchmark/results'),
      experimentsDir: Directory('experiments'),
      generatedAt: generatedAt,
    ),
    mismatches: mismatches,
  );

  if (mismatches.isNotEmpty) {
    stderr.writeln('');
    stderr.writeln(
      'Benchmark-generated docs are stale. Re-run the generators and commit the updated files:',
    );
    stderr.writeln('  dart run benchmark/generate_devices.dart');
    stderr.writeln('  dart run benchmark/generate_history.dart');
    stderr.writeln('For experiment writeups, prefer:');
    stderr.writeln(
      '  dart run benchmark/finalize_experiment.dart --experiment=experiments/NNN-short-slug.md',
    );
    exitCode = 1;
    return;
  }

  print('Benchmark-generated docs are up to date.');
}

Future<void> _checkJsonFile({
  required String label,
  required String currentPath,
  required Object Function(String? generatedAt) buildExpected,
  required List<String> mismatches,
}) async {
  final currentFile = File(currentPath);
  if (!currentFile.existsSync()) {
    throw StateError(
      'Missing generated docs artifact: $currentPath. '
      'Re-run the generator and commit the updated file.',
    );
  }

  final currentText = currentFile.readAsStringSync();
  final currentJson = json.decode(currentText);
  if (currentJson is! Map<String, Object?>) {
    throw StateError('$currentPath does not contain a top-level JSON object.');
  }

  final expected = buildExpected(currentJson['generated']?.toString());
  const encoder = JsonEncoder.withIndent('  ');
  final currentComparable = '${encoder.convert(currentJson)}\n';
  final expectedText = '${encoder.convert(expected)}\n';

  if (currentComparable == expectedText) {
    print('$label is current.');
    return;
  }

  mismatches.add(label);
  stderr.writeln('::error file=$currentPath::$label is stale.');

  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite-generated-data-diff_',
  );
  try {
    final normalizedCurrentFile = File(
      '${tempDir.path}/current_${currentFile.uri.pathSegments.last}',
    )..writeAsStringSync(currentComparable);
    final expectedFile = File(
      '${tempDir.path}/${currentFile.uri.pathSegments.last}',
    )..writeAsStringSync(expectedText);
    final diff = await Process.run('diff', [
      '-u',
      normalizedCurrentFile.path,
      expectedFile.path,
    ]);
    if ((diff.stdout as String).trim().isNotEmpty) {
      stderr.writeln(diff.stdout);
    } else if ((diff.stderr as String).trim().isNotEmpty) {
      stderr.writeln(diff.stderr);
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}
