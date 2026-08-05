// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'shared/release_artifact.dart';

/// Parses `benchmark/HARDWARE_RESULTS.md` device registry and extracts
/// full cross-library benchmark data from referenced result files into
/// `docs/benchmarks/devices.json`.
///
/// Usage:
///   dart run benchmark/generate_devices.dart
void main() {
  final mdFile = File('benchmark/HARDWARE_RESULTS.md');
  final outFile = File('docs/benchmarks/devices.json');

  if (!mdFile.existsSync()) {
    print('HARDWARE_RESULTS.md not found');
    return;
  }

  final content = mdFile.readAsStringSync();
  final output = buildDevicesData(
    hardwareResultsMarkdown: content,
    resultsDir: Directory('benchmark/results'),
  );

  final devices =
      (output['devices'] as List?)?.cast<Map<String, Object?>>() ??
      const <Map<String, Object?>>[];
  if (devices.isEmpty) {
    print('No devices found in HARDWARE_RESULTS.md');
    return;
  }

  outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));

  final count = devices.length;
  print('Wrote ${outFile.path} ($count device(s))');
}

Map<String, Object?> buildDevicesData({
  required String hardwareResultsMarkdown,
  required Directory resultsDir,
  String? generatedAt,
}) {
  final devices = _parseDeviceRegistry(hardwareResultsMarkdown);

  // Sort devices most-recent-first so the dashboard defaults to the latest
  // run and history appears in reverse chronological order. Primary key is
  // the `date` column (ISO YYYY-MM-DD, which sorts correctly as a string);
  // the result filename (which starts with an ISO timestamp) acts as the
  // tie-breaker so multiple runs on the same date have a stable order.
  devices.sort((a, b) {
    final dateCmp = (b['date'] ?? '').compareTo(a['date'] ?? '');
    if (dateCmp != 0) return dateCmp;
    return (b['resultFile'] ?? '').compareTo(a['resultFile'] ?? '');
  });

  // For each device, parse its result file for full cross-library data.
  final output = <String, Object?>{
    'generated': generatedAt ?? DateTime.now().toIso8601String(),
    'devices': <Map<String, Object?>>[],
  };

  for (final device in devices) {
    final resultPath = '${resultsDir.path}/${device['resultFile']}';
    final resultFile = File(resultPath);
    if (!resultFile.existsSync()) {
      print(
        '  Warning: ${device['name']} references missing file: $resultPath',
      );
      continue;
    }

    final sidecar = loadReleaseArtifactSidecarForMarkdown(resultFile);
    final benchmarksFromSidecar = sidecar != null
        ? artifactBenchmarks(sidecar)
        : null;
    final benchmarks =
        benchmarksFromSidecar == null || benchmarksFromSidecar.isEmpty
        ? parseBenchmarkSections(resultFile.readAsStringSync())
        : benchmarksFromSidecar;
    final environment = sidecar != null ? artifactEnvironment(sidecar) : null;

    (output['devices'] as List).add({
      'name': device['name'],
      'cpu': device['cpu'],
      'os': device['os'],
      'dart': device['dart'],
      'date': device['date'],
      'by': device['by'],
      if (environment != null && environment.isNotEmpty)
        'environment': environment,
      'benchmarks': benchmarks,
    });

    print(
      '  ${device['name']}: ${benchmarks.length} benchmark sections parsed',
    );
  }

  return output;
}

/// Parse the Devices table from HARDWARE_RESULTS.md.
List<Map<String, String>> _parseDeviceRegistry(String content) {
  final devices = <Map<String, String>>[];
  final lines = content.split('\n');
  var inDevices = false;

  for (final line in lines) {
    if (line.startsWith('## Devices')) {
      inDevices = true;
      continue;
    }
    if (line.startsWith('## ') && inDevices) break;

    if (!inDevices || !line.startsWith('|')) continue;
    if (line.contains('---') || line.contains('Device')) continue;

    final cells = line
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (cells.length >= 7) {
      devices.add({
        'name': cells[0],
        'cpu': cells[1],
        'os': cells[2],
        'dart': cells[3],
        'date': cells[4],
        'by': cells[5],
        'resultFile': cells[6],
      });
    }
  }

  return devices;
}
