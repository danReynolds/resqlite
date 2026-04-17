// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

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
  final devices = _parseDeviceRegistry(content);

  if (devices.isEmpty) {
    print('No devices found in HARDWARE_RESULTS.md');
    return;
  }

  // For each device, parse its result file for full cross-library data.
  final output = <String, Object?>{
    'generated': DateTime.now().toIso8601String(),
    'devices': <Map<String, Object?>>[],
  };

  for (final device in devices) {
    final resultPath = 'benchmark/results/${device['resultFile']}';
    final resultFile = File(resultPath);
    if (!resultFile.existsSync()) {
      print('  Warning: ${device['name']} references missing file: $resultPath');
      continue;
    }

    final resultContent = resultFile.readAsStringSync();
    final benchmarks = _parseResultFile(resultContent);

    (output['devices'] as List).add({
      'name': device['name'],
      'cpu': device['cpu'],
      'os': device['os'],
      'dart': device['dart'],
      'date': device['date'],
      'by': device['by'],
      'benchmarks': benchmarks,
    });

    print('  ${device['name']}: ${benchmarks.length} benchmark sections parsed');
  }

  // Sort devices most-recent-first so the dashboard defaults to the
  // latest run and history appears in reverse chronological order.
  (output['devices'] as List).sort((a, b) {
    final aDate = (a as Map)['date']?.toString() ?? '';
    final bDate = (b as Map)['date']?.toString() ?? '';
    return bDate.compareTo(aDate);
  });

  outFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(output),
  );

  final count = (output['devices'] as List).length;
  print('Wrote ${outFile.path} ($count device(s))');
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

    final cells =
        line.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
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

/// Parse a full benchmark result .md file into structured cross-library data.
///
/// Returns a list of benchmark sections, each with a title and data for
/// all three libraries.
List<Map<String, Object?>> _parseResultFile(String content) {
  final sections = <Map<String, Object?>>[];
  final lines = content.split('\n');

  String? currentSection;
  String? currentSubsection;

  for (final line in lines) {
    if (line.startsWith('## ')) {
      currentSection = line.substring(3).trim();
      currentSubsection = null;
      // Skip non-benchmark sections.
      if (currentSection.startsWith('Comparison') ||
          currentSection.startsWith('Repeat') ||
          currentSection.startsWith('resqlite Benchmark')) {
        currentSection = null;
      }
      continue;
    }
    if (line.startsWith('### ')) {
      currentSubsection = line.substring(4).trim();
      continue;
    }

    if (currentSection == null) continue;

    // Parse table data rows (start with |, not separator rows).
    if (!line.startsWith('|') || line.contains('---')) continue;

    final cells =
        line.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (cells.length < 2) continue;

    // Skip header rows.
    final firstCell = cells[0].toLowerCase();
    if (firstCell == 'library' || firstCell == 'rows' ||
        firstCell == 'concurrency' || firstCell == 'n') continue;

    final sectionKey = currentSubsection != null
        ? '$currentSection / $currentSubsection'
        : currentSection;

    // Find or create section.
    var section = sections.firstWhere(
      (s) => s['key'] == sectionKey,
      orElse: () {
        final s = <String, Object?>{
          'key': sectionKey,
          'title': currentSection,
          'subtitle': currentSubsection,
          'entries': <Map<String, Object?>>[],
        };
        sections.add(s);
        return s;
      },
    );

    final entries = section['entries'] as List<Map<String, Object?>>;
    final library = cells[0];

    // Parse numeric values from remaining cells.
    final values = <double?>[];
    for (var i = 1; i < cells.length; i++) {
      values.add(double.tryParse(cells[i]));
    }

    entries.add({
      'library': library,
      'values': values,
    });
  }

  return sections;
}
