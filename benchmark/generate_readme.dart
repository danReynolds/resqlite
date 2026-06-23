// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// Assembles `experiments/README.md` from its hand-edited sources:
///
///   experiments/README.template.md    — the prose, section headers, and table
///                                        headers, with `{{ROWS:<status>}}`
///                                        placeholders where each table body goes
///   experiments/index/NNN.json         — one file per experiment: its README
///                                        row data {file, title, impact, status,
///                                        link}
///
/// `README.md` is a *generated* aggregate owned by the post-merge "Update Docs
/// Data" bot — see experiments/RUNNER_INSTRUCTIONS.md. An experiment adds its
/// own `index/NNN.json` (its own file, so two concurrent experiments never
/// touch the same one); rows render newest-first (id descending). Maintainers
/// edit `README.template.md` for prose. Nobody hand-edits `README.md`.
String buildReadme({required Directory experimentsDir}) {
  final templateFile = File('${experimentsDir.path}/README.template.md');
  if (!templateFile.existsSync()) {
    throw StateError('Missing ${templateFile.path}');
  }
  final indexDir = Directory('${experimentsDir.path}/index');
  final rows = <String, List<_Row>>{
    'accepted': [],
    'in_review': [],
    'rejected': [],
  };
  if (indexDir.existsSync()) {
    for (final file in indexDir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final id = file.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), '');
      final decoded = json.decode(file.readAsStringSync());
      // A fragment is one row object, or a list of rows for a "split"
      // experiment (e.g. 014 has an accepted finding and a rejected one).
      final entries = decoded is List ? decoded : [decoded];
      for (final entry in entries) {
        if (entry is! Map<String, Object?>) {
          throw StateError('${file.path} rows must be JSON objects.');
        }
        final status = entry['status'];
        final bucket = rows[status];
        if (bucket == null) {
          throw StateError(
            '${file.path} has invalid status "$status" '
            '(expected accepted | in_review | rejected).',
          );
        }
        bucket.add(
          _Row(
            id: id,
            file: entry['file'] as String? ?? '$id.md',
            title: (entry['title'] as String? ?? '').trim(),
            impact: (entry['impact'] as String? ?? '').trim(),
            link: (entry['link'] as String? ?? '').trim(),
            rejected: status == 'rejected',
          ),
        );
      }
    }
  }

  var out = templateFile.readAsStringSync();
  for (final status in rows.keys) {
    final sorted = rows[status]!..sort((a, b) => _compareIds(b.id, a.id));
    final body = sorted.map((r) => r.render()).join('\n');
    out = out.replaceAll('{{ROWS:$status}}', body);
  }
  return out;
}

class _Row {
  _Row({
    required this.id,
    required this.file,
    required this.title,
    required this.impact,
    required this.link,
    required this.rejected,
  });

  final String id;
  final String file;
  final String title;
  final String impact;
  final String link;
  final bool rejected;

  String render() => rejected
      ? '| [$id]($file) | $title | $impact |'
      : '| [$id]($file) | $title | $impact | $link |';
}

int _compareIds(String a, String b) {
  final ma = RegExp(r'^(\d+)(.*)$').firstMatch(a);
  final mb = RegExp(r'^(\d+)(.*)$').firstMatch(b);
  final na = ma == null ? (1 << 30) : int.parse(ma.group(1)!);
  final nb = mb == null ? (1 << 30) : int.parse(mb.group(1)!);
  if (na != nb) return na.compareTo(nb);
  final sa = ma == null ? a : ma.group(2)!;
  final sb = mb == null ? b : mb.group(2)!;
  return sa.compareTo(sb);
}

Future<void> main() async {
  final readme = buildReadme(experimentsDir: Directory('experiments'));
  File('experiments/README.md').writeAsStringSync(readme);
  print('Wrote experiments/README.md');
}
