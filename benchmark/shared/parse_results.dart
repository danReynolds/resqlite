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
        // Standard timing rows have 4 numeric columns after the label
        // (wall med, wall p90, main med, main p90). Non-timing rows
        // under `### QPS + MDE` have a dotted CI string at column 2
        // (e.g. "120482..127194"), which fails the numeric check. That
        // gate stops the parser from polluting `metrics` with QPS
        // values misread as ms. Single-cell rows like `| resqlite qps |
        // N |` (parts.length == 2) remain fully supported.
        final isTimingRow = parts.length < 3 ||
            double.tryParse(parts[2]) != null;
        if (wallMed != null && isTimingRow) {
          final key = currentSubsection != null
              ? '$currentSection / $currentSubsection / $label'
              : '$currentSection / $label';
          results[key] = wallMed;
        }
        // Also extract main isolate median (column index 3).
        if (parts.length >= 4 && isTimingRow) {
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

/// Memory suite metrics parsed from a benchmark results markdown file.
///
/// Emitted by `suites/memory.dart` in the `## Memory` section. Columns:
/// `| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |`.
///
/// The MDE (minimum detectable effect) is expressed in absolute MB
/// rather than percent — memory deltas are often 0 MB, which makes a
/// percentage formulation nonsensical. `mdeMB` is the half-width of the
/// 95% bootstrap CI around the median and represents the smallest
/// reduction (in MB) that could be distinguished from current noise.
class MemoryMetric {
  MemoryMetric({
    required this.rssDeltaMedMB,
    required this.rssDeltaP90MB,
    required this.ciLowMB,
    required this.ciHighMB,
    required this.mdeMB,
  });

  final double rssDeltaMedMB;
  final double rssDeltaP90MB;
  final double ciLowMB;
  final double ciHighMB;
  final double mdeMB;
}

/// Extract memory suite medians from markdown content.
///
/// Returns a map of `Memory / subsection / library` → [MemoryMetric].
/// Scans only the `## Memory` section; stops at the next `## ` header
/// to avoid cross-section bleed.
Map<String, MemoryMetric> extractMemoryMedians(String content) {
  final results = <String, MemoryMetric>{};
  final lines = content.split('\n');

  var inMemory = false;
  String? subsection;

  for (final line in lines) {
    if (line.startsWith('## ')) {
      inMemory = line.substring(3).trim() == 'Memory';
      subsection = null;
      continue;
    }
    if (!inMemory) continue;
    if (line.startsWith('### ')) {
      subsection = line.substring(4).trim();
      continue;
    }
    if (line.startsWith('|') &&
        !line.startsWith('|---') &&
        !line.startsWith('| Library')) {
      final parts = line
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length < 5) continue;
      final label = parts[0];
      final med = double.tryParse(parts[1]);
      final p90 = double.tryParse(parts[2]);
      final ciParts = parts[3].split('..');
      if (ciParts.length != 2) continue;
      final ciLow = double.tryParse(ciParts[0].trim());
      final ciHigh = double.tryParse(ciParts[1].trim());
      // MDE column rendered as "±N.NN"; strip the leading ±.
      final mdeStr = parts[4].replaceFirst('±', '').trim();
      final mde = double.tryParse(mdeStr);
      if (med == null || p90 == null || ciLow == null || ciHigh == null ||
          mde == null) {
        continue;
      }
      final key = subsection != null
          ? 'Memory / $subsection / $label'
          : 'Memory / $label';
      results[key] = MemoryMetric(
        rssDeltaMedMB: med,
        rssDeltaP90MB: p90,
        ciLowMB: ciLow,
        ciHighMB: ciHigh,
        mdeMB: mde,
      );
    }
  }

  return results;
}

/// Streaming column-granularity metrics parsed from a results markdown.
///
/// Emitted by `suites/disjoint_columns.dart` in the
/// `## Streaming (Column Granularity)` section. Columns:
/// `| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |`.
class StreamingColumnMetric {
  StreamingColumnMetric({
    required this.reemits,
    required this.drainMs,
    required this.ratio,
  });

  final int reemits;
  final double drainMs;
  final double ratio;
}

/// Extract streaming column-granularity metrics from markdown content.
///
/// Returns a map of `Streaming (Column Granularity) / subsection / library`
/// → [StreamingColumnMetric]. Scans only the owning `## Streaming
/// (Column Granularity)` section and stops at the next `## ` header.
Map<String, StreamingColumnMetric> extractStreamingColumnMedians(
  String content,
) {
  final results = <String, StreamingColumnMetric>{};
  final lines = content.split('\n');

  var inSection = false;
  String? subsection;

  for (final line in lines) {
    if (line.startsWith('## ')) {
      inSection =
          line.substring(3).trim() == 'Streaming (Column Granularity)';
      subsection = null;
      continue;
    }
    if (!inSection) continue;
    if (line.startsWith('### ')) {
      subsection = line.substring(4).trim();
      continue;
    }
    if (line.startsWith('|') &&
        !line.startsWith('|---') &&
        !line.startsWith('| Library')) {
      final parts = line
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length < 4) continue;
      final label = parts[0];
      final reemits = int.tryParse(parts[1]);
      final drain = double.tryParse(parts[2]);
      final ratio = double.tryParse(parts[3]);
      if (reemits == null || drain == null || ratio == null) continue;
      final key = subsection != null
          ? 'Streaming (Column Granularity) / $subsection / $label'
          : 'Streaming (Column Granularity) / $label';
      results[key] = StreamingColumnMetric(
        reemits: reemits,
        drainMs: drain,
        ratio: ratio,
      );
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
