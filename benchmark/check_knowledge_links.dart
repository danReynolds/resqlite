// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// Knowledge-graph reference linter.
///
/// Errors (exit 1):
///   - a relative link in a source markdown file (experiments/**, doc/**)
///     that does not resolve to a file or directory in the repo — the class
///     of rot that left the architecture doc pointing at an experiment
///     writeup that was never published;
///   - a `claim NNN.M` citation naming a claim no entry defines;
///   - an `index/NNN.json` `supersededBy`/`amendedBy` naming an unknown
///     experiment.
///
/// Warnings (reported, exit 0):
///   - a citation of a claim that is superseded or refuted — legitimate in
///     historical prose, but each mention deserves a look when the claim's
///     state changes.
///
/// Generated aggregates (experiments/README.md, experiments/signals.json,
/// docs/**) are skipped: they are bot-owned, and a branch cannot fix them.
void main() {
  final errors = <String>[];
  final warnings = <String>[];

  // --- claim universe + states, from the entry fragments -------------------
  final claimStates = <String, String>{}; // id -> live|superseded|refuted
  final entriesDir = Directory('experiments/signals/entries');
  final supersededOrRefuted = <String, String>{};
  if (entriesDir.existsSync()) {
    final claims = <String, List>{};
    for (final f in entriesDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final note = json.decode(f.readAsStringSync());
      if (note is! Map) continue;
      for (final c in (note['claims'] as List? ?? const [])) {
        if (c is Map && c['id'] is String) {
          claims[c['id'] as String] = (c['edges'] as List? ?? const []);
        }
      }
    }
    for (final id in claims.keys) {
      claimStates[id] = 'live';
    }
    for (final e in claims.entries) {
      for (final edge in e.value) {
        if (edge is! Map || edge['target'] is! String) continue;
        final t = edge['target'] as String;
        if (edge['type'] == 'refutes') {
          claimStates[t] = 'refuted';
          supersededOrRefuted[t] = 'refuted by ${e.key}';
        } else if (edge['type'] == 'supersedes' &&
            claimStates[t] != 'refuted') {
          claimStates[t] = 'superseded';
          supersededOrRefuted[t] = 'superseded by ${e.key}';
        }
      }
    }
  }

  // --- experiment universe, from index fragments ---------------------------
  final experimentIds = <String>{};
  final indexDir = Directory('experiments/index');
  if (indexDir.existsSync()) {
    for (final f in indexDir.listSync().whereType<File>()) {
      if (f.path.endsWith('.json')) {
        experimentIds.add(
          f.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), ''),
        );
      }
    }
  }

  // --- index lineage fields ------------------------------------------------
  if (indexDir.existsSync()) {
    for (final f in indexDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final decoded = json.decode(f.readAsStringSync());
      final rows = decoded is List ? decoded : [decoded];
      for (final row in rows.whereType<Map>()) {
        for (final key in const ['supersededBy', 'amendedBy']) {
          final targets = row[key];
          if (targets == null) continue;
          if (targets is! List) {
            errors.add('${f.path}: $key must be a list of experiment ids.');
            continue;
          }
          for (final t in targets) {
            if (t is! String || !experimentIds.contains(t)) {
              errors.add('${f.path}: $key -> "$t" is not a known experiment.');
            }
          }
        }
      }
    }
  }

  // --- markdown link + citation lint ---------------------------------------
  // architecture.md is blog-rendered (docs/blog/architecture.html), so its
  // links — like the story sources' — are authored for the published site.
  final skip = {'experiments/README.md', 'doc/arch/architecture.md'};
  final mdFiles =
      <File>[
        ...Directory('experiments').listSync(recursive: true).whereType<File>(),
        if (Directory('doc').existsSync())
          ...Directory('doc').listSync(recursive: true).whereType<File>(),
      ].where(
        (f) =>
            f.path.endsWith('.md') &&
            !skip.contains(f.path) &&
            // Story sources render into docs/blog/stories/, so their relative
            // links are authored against the *published* location and cannot be
            // resolved from the source tree.
            !f.path.startsWith('doc/stories/'),
      );

  final linkRe = RegExp(r'\]\(([^)\s]+)\)');
  final claimRe = RegExp(r'\bclaim[s]?\s+(\d+\.\d+)\b');
  // Chapters cite claims inline as [[NNN.M]]; unknown ids are errors, and
  // citations of superseded/refuted claims are the chapter's repair debt.
  final citeRe = RegExp(r'\[\[(\d+\.\d+)\]\]');
  final chapterDebt = <String, int>{};
  for (final f in mdFiles) {
    final text = f.readAsStringSync();
    for (final m in linkRe.allMatches(text)) {
      var href = m.group(1)!;
      if (href.startsWith(RegExp(r'[a-z][a-z0-9+.-]*:')) ||
          href.startsWith('#') ||
          href.startsWith('/')) {
        continue; // scheme, in-page anchor, or absolute — not ours to check
      }
      href = href.split('#').first;
      if (href.isEmpty) continue;
      final resolved = File(f.parent.uri.resolve(href).toFilePath());
      if (!resolved.existsSync() && !Directory(resolved.path).existsSync()) {
        errors.add('${f.path}: dead link ($href)');
      }
    }
    for (final m in claimRe.allMatches(text)) {
      final id = m.group(1)!;
      if (!claimStates.containsKey(id)) {
        errors.add('${f.path}: cites claim $id, which no entry defines.');
      } else if (supersededOrRefuted.containsKey(id)) {
        warnings.add(
          '${f.path}: cites claim $id (${supersededOrRefuted[id]}) — '
          'confirm the surrounding prose still reads correctly.',
        );
      }
    }
    for (final m in citeRe.allMatches(text)) {
      final id = m.group(1)!;
      if (!claimStates.containsKey(id)) {
        errors.add(
          '${f.path}: citation [[${id}]] names a claim no entry defines.',
        );
      } else if (supersededOrRefuted.containsKey(id)) {
        chapterDebt[f.path] = (chapterDebt[f.path] ?? 0) + 1;
        warnings.add(
          '${f.path}: [[${id}]] is ${supersededOrRefuted[id]} — this passage '
          'needs a repair pass.',
        );
      }
    }
  }
  for (final e in chapterDebt.entries) {
    warnings.add('repair debt: ${e.key} has ${e.value} stale citation(s).');
  }

  for (final w in warnings) {
    print('::warning::$w');
  }
  if (errors.isNotEmpty) {
    for (final e in errors) {
      print('::error::$e');
    }
    exitCode = 1;
    return;
  }
  print(
    'Knowledge links are clean '
    '(${claimStates.length} claims, ${warnings.length} warnings).',
  );
}
