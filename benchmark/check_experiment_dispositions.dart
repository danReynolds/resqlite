import 'dart:convert';
import 'dart:io';

/// Fails when any experiment is still in the `in_review` soak state.
///
/// `in_review` is meant to be transient: an experiment merges only once it has
/// a verdict, so its recorded disposition must be terminal (accepted/rejected)
/// by merge time. Historically the post-merge flip was skipped and the bucket
/// silently accumulated accepted-but-unpromoted experiments. This guard makes
/// that impossible: a PR cannot go green while an experiment it touches is
/// still in review.
///
/// The disposition lives in three per-experiment sources that must agree, so
/// all three are checked — none can strand independently:
///   - experiments/index/NNN.json          `status`
///   - experiments/NNN-*.md                `**Status:**`
///   - experiments/signals/entries/NNN.json `outcomeClass`
const _experimentsDir = 'experiments';
const _terminalStatuses = {'accepted', 'rejected'};

final _statusLinePattern = RegExp(r'^\*\*Status:\*\*\s*(.+)$', multiLine: true);
final _experimentFilePattern = RegExp(r'^\d+\w?-.+\.md$');

/// Pure detector used by [main]; returns one human-readable issue line per
/// offending source (empty when clean), so the rule is unit-testable without
/// the `exit(1)` side effect. Each line is `path::message`.
List<String> findStrandedInReview({String root = _experimentsDir}) {
  final issues = <String>[];

  // 1. index/NNN.json — the authoritative status (drives README + history.json).
  final indexDir = Directory('$root/index');
  if (indexDir.existsSync()) {
    final files = indexDir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      if (!file.path.endsWith('.json')) continue;
      final rows = _rows(file, issues);
      for (final row in rows) {
        final status = row['status']?.toString();
        if (status == null || _terminalStatuses.contains(status)) continue;
        issues.add(
          '${file.path}::status "$status" is not terminal — set "accepted" or '
          '"rejected" before merge (apply the matching approved/rejected PR label).',
        );
      }
    }
  }

  // 2. writeup **Status:** — drives the blog; keep it consistent with the index.
  final expDir = Directory(root);
  if (expDir.existsSync()) {
    final files = expDir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      if (!_experimentFilePattern.hasMatch(file.uri.pathSegments.last))
        continue;
      final match = _statusLinePattern.firstMatch(file.readAsStringSync());
      if (match == null) continue;
      final value = match.group(1)!.trim();
      final norm = value.toLowerCase();
      if (norm.startsWith('in review') || norm.startsWith('in_review')) {
        issues.add(
          '${file.path}::**Status:** "$value" is still in review — set '
          '"Accepted" or "Rejected" before merge.',
        );
      }
    }
  }

  // 3. signals/entries/NNN.json outcomeClass — drives the research map.
  final entriesDir = Directory('$root/signals/entries');
  if (entriesDir.existsSync()) {
    final files = entriesDir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      if (!file.path.endsWith('.json')) continue;
      final rows = _rows(file, issues);
      for (final row in rows) {
        final outcome = row['outcomeClass']?.toString();
        if (outcome == null || !outcome.toLowerCase().startsWith('in_review')) {
          continue;
        }
        issues.add(
          '${file.path}::outcomeClass "$outcome" is still in review — set the '
          'terminal class (accepted… / rejected…) before merge.',
        );
      }
    }
  }

  return issues;
}

List<Map<Object?, Object?>> _rows(File file, List<String> issues) {
  Object? decoded;
  try {
    decoded = json.decode(file.readAsStringSync());
  } on FormatException catch (error) {
    issues.add('${file.path}::not valid JSON: ${error.message}');
    return const [];
  }
  final rows = decoded is List ? decoded : [decoded];
  return rows.whereType<Map<Object?, Object?>>().toList();
}

void main() {
  final issues = findStrandedInReview();
  if (issues.isNotEmpty) {
    for (final issue in issues) {
      final sep = issue.indexOf('::');
      stderr.writeln(
        '::error file=${issue.substring(0, sep)}::${issue.substring(sep + 2)}',
      );
    }
    stderr.writeln(
      'Found ${issues.length} experiment(s) still in review. Experiments must '
      'reach a terminal disposition (accepted/rejected) before merge.',
    );
    exitCode = 1;
    return;
  }
  print(
    'All experiments are in a terminal disposition (no stranded in-review).',
  );
}
