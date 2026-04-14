/// Shared parsing utilities for benchmark result markdown files.
///
/// Used by both `run_all.dart` (for pairwise comparison) and
/// `generate_history.dart` (for historical timeline generation).

/// Extract resqlite median wall times from markdown content.
///
/// Returns a map of benchmark label → median ms value. Keys follow the
/// pattern `section / subsection / library` with an optional `[main]`
/// suffix for main-isolate timings.
Map<String, double> extractResqliteMedians(String content) {
  final results = <String, double>{};
  final lines = content.split('\n');

  String? currentSection;
  String? currentSubsection;

  for (final line in lines) {
    if (line.startsWith('## ')) {
      currentSection = line.substring(3).trim();
      currentSubsection = null;
    } else if (line.startsWith('### ')) {
      currentSubsection = line.substring(4).trim();
    } else if (line.startsWith('| resqlite')) {
      final parts = line
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        final label = parts[0];
        final wallMed = double.tryParse(parts[1]);
        if (wallMed != null) {
          final key = currentSubsection != null
              ? '$currentSection / $currentSubsection / $label'
              : '$currentSection / $label';
          results[key] = wallMed;
        }
        // Also extract main isolate median (column index 3).
        if (parts.length >= 4) {
          final mainMed = double.tryParse(parts[3]);
          if (mainMed != null) {
            final key = currentSubsection != null
                ? '$currentSection / $currentSubsection / $label [main]'
                : '$currentSection / $label [main]';
            results[key] = mainMed;
          }
        }
      }
    } else if (currentSection != null &&
        currentSection.contains('Concurrent Reads') &&
        line.startsWith('| ') &&
        !line.startsWith('|---') &&
        !line.startsWith('| Concurrency')) {
      // Concurrent reads: rows like "| 4 | 0.88 | 0.22 | 1.83 | 0.46 |"
      final parts = line
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        final concurrency = int.tryParse(parts[0]);
        final wallTime = double.tryParse(parts[1]);
        if (concurrency != null && wallTime != null) {
          results['$currentSection / resqlite concurrent ${concurrency}x'] =
              wallTime;
        }
      }
    }
  }

  return results;
}

/// Parse metadata from a benchmark result filename.
///
/// Handles formats like:
/// - `2026-04-08T15-43-57-with-streaming.md`
/// - `2026-04-08-codex-main-four-way.md`
/// - `2026-04-13T14-44-30-MacBook Pro 14in.md`
({String date, String timestamp, String label})? parseFilenameMetadata(
  String filename,
) {
  // Strip directory prefix if present.
  final basename = filename.split('/').last.split('\\').last;
  if (!basename.endsWith('.md')) return null;
  final withoutExt = basename.substring(0, basename.length - 3);

  // Try full timestamp format: YYYY-MM-DDTHH-MM-SS-label
  final full = RegExp(r'^(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})-(.+)$');
  final fullMatch = full.firstMatch(withoutExt);
  if (fullMatch != null) {
    final date = fullMatch.group(1)!;
    final h = fullMatch.group(2)!;
    final m = fullMatch.group(3)!;
    final s = fullMatch.group(4)!;
    return (
      date: date,
      timestamp: '${date}T$h:$m:$s',
      label: fullMatch.group(5)!,
    );
  }

  // Try date-only format: YYYY-MM-DD-label
  final dateOnly = RegExp(r'^(\d{4}-\d{2}-\d{2})-(.+)$');
  final dateMatch = dateOnly.firstMatch(withoutExt);
  if (dateMatch != null) {
    final date = dateMatch.group(1)!;
    return (
      date: date,
      timestamp: '${date}T00:00:00',
      label: dateMatch.group(2)!,
    );
  }

  return null;
}
