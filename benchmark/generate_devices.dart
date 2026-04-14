// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// Parses `benchmark/HARDWARE_RESULTS.md` into `docs/benchmarks/devices.json`.
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
  final lines = content.split('\n');

  // 1. Parse device metadata from ## Devices table.
  final devices = <String, Map<String, String>>{};
  // 2. Parse benchmark sections into structured data.
  final sections = <Map<String, Object?>>[];

  String? currentSection;
  String? currentDescription;
  List<String>? columnHeaders;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    // Section headers.
    if (line.startsWith('## ')) {
      final title = line.substring(3).trim();

      // Grab the description line(s) that follow the header.
      currentDescription = '';
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j].trim();
        if (next.isEmpty) continue;
        if (next.startsWith('|') || next.startsWith('#')) break;
        currentDescription = next;
        break;
      }

      if (title == 'Devices') {
        currentSection = 'devices';
      } else if (title != 'How to Submit') {
        currentSection = title;
        columnHeaders = null;
      }
      continue;
    }

    // Table rows.
    if (!line.startsWith('|')) continue;
    if (line.contains('---')) continue; // separator

    final cells =
        line.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    if (currentSection == 'devices') {
      // Header row.
      if (cells.first == 'Device') continue;
      // Data row: Device | CPU | OS | Dart | Date | By
      if (cells.length >= 6) {
        final name = cells[0];
        devices[name] = {
          'cpu': cells[1],
          'os': cells[2],
          'dart': cells[3],
          'date': cells[4],
          'by': cells[5],
        };
      }
      continue;
    }

    if (currentSection == null) continue;

    // First data row in a section — detect column headers.
    if (columnHeaders == null) {
      columnHeaders = cells;
      // Start a new section entry.
      sections.add({
        'title': currentSection,
        'description': currentDescription,
        'columns': List<String>.from(cells.skip(1)), // skip Device column
        'rows': <Map<String, Object?>>[],
      });
      continue;
    }

    // Data rows.
    final section = sections.last;
    final rows = section['rows'] as List<Map<String, Object?>>;

    final device = cells[0];
    final values = <String, Object?>{};
    for (var c = 1; c < cells.length && c < columnHeaders.length; c++) {
      final header = columnHeaders[c];
      final raw = cells[c];
      // Try to parse as number, keep as string if not.
      final numVal = double.tryParse(raw.replaceAll(RegExp(r'[Kk]$'), ''));
      if (raw.endsWith('K') || raw.endsWith('k')) {
        values[header] = '${numVal?.round() ?? raw}K';
      } else {
        values[header] = numVal ?? raw;
      }
    }
    rows.add({'device': device, 'values': values});
  }

  // Build output.
  final output = {
    'generated': DateTime.now().toIso8601String(),
    'devices': devices,
    'sections': sections,
  };

  outFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(output),
  );

  print('Parsed ${devices.length} device(s), ${sections.length} sections.');
  print('Wrote ${outFile.path}');
}
