// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'generate_knowledge_graph.dart' as kg;

/// Renders `docs/knowledge/index.html` — the human documentation layer over
/// the knowledge graph.
///
/// Sources:
///   doc/arch/chapters/NN-<component>.md  — authored narrative chapters with
///                                           front-matter and inline
///                                           `[[NNN.M]]` claim citations
///   doc/arch/chapters/_viewer.html       — the page template
///   the knowledge graph                  — built in-memory (same builder the
///                                           bot uses for knowledge-graph.json)
///
/// The chapters are the *authored* layer: they never regenerate from claims.
/// The page injects the live graph beside them, so citation chips always show
/// each claim's current state — a chapter standing on superseded evidence
/// renders its citation struck-through even before the prose is repaired, and
/// `check_knowledge_links.dart` reports the repair debt per chapter.
String buildKnowledgePage({required Directory repoRoot}) {
  final chaptersDir = Directory('${repoRoot.path}/doc/arch/chapters');
  final template = File('${chaptersDir.path}/_viewer.html').readAsStringSync();

  final sysmap = <Map<String, Object?>>[];
  final stories = <String, Object?>{};
  final files =
      chaptersDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) throw StateError('No chapters in ${chaptersDir.path}');

  for (final file in files) {
    final (meta, sections) = _parseChapter(file);
    final lede = sections.isNotEmpty && sections.first['lede'] == true
        ? (sections.first['ps'] as List).first as String
        : '';
    sysmap.add({
      'id': meta['component'],
      'zone': meta['zone'],
      'kicker': meta['kicker'],
      'name': meta['title'],
      'summary': _firstSentences(lede.replaceAll(RegExp(r'\[\[[\d.]+\]\]'), ''), 2),
      'dirs': meta['directions'] ?? const [],
      if (meta['extraClaims'] != null) 'claims': meta['extraClaims'],
    });
    stories[meta['component'] as String] = {
      if (meta['diagram'] != null) 'diagram': meta['diagram'],
      'sections': sections,
    };
  }

  final graph = kg.buildKnowledgeGraph(
    experimentsDir: Directory('${repoRoot.path}/experiments'),
  );
  return template
      .replaceFirst('__KG__', json.encode(graph))
      .replaceFirst('__SYSMAP__', json.encode(sysmap))
      .replaceFirst('__STORIES__', json.encode(stories));
}

(Map<String, Object?>, List<Map<String, Object?>>) _parseChapter(File file) {
  final lines = file.readAsStringSync().split('\n');
  if (lines.first.trim() != '---') {
    throw StateError('${file.path}: missing front-matter');
  }
  final end = lines.indexOf('---', 1);
  final meta = <String, Object?>{};
  for (final line in lines.sublist(1, end)) {
    final i = line.indexOf(':');
    if (i < 0) continue;
    final key = line.substring(0, i).trim();
    var value = line.substring(i + 1).trim();
    if (value.startsWith('[') && value.endsWith(']')) {
      meta[key] = value
          .substring(1, value.length - 1)
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      meta[key] = value;
    }
  }
  for (final key in ['component', 'title', 'kicker', 'zone']) {
    if (meta[key] == null) throw StateError('${file.path}: missing $key');
  }

  final sections = <Map<String, Object?>>[];
  var current = <String, Object?>{'lede': true, 'ps': <String>[]};
  final para = StringBuffer();
  void flushPara() {
    final text = para.toString().trim();
    if (text.isNotEmpty) (current['ps'] as List).add(text);
    para.clear();
  }

  void flushSection() {
    flushPara();
    if ((current['ps'] as List).isNotEmpty) sections.add(current);
  }

  for (final line in lines.sublist(end + 1)) {
    if (line.startsWith('## ')) {
      flushSection();
      current = <String, Object?>{'h': line.substring(3).trim(), 'ps': <String>[]};
    } else if (line.trim().isEmpty) {
      flushPara();
    } else {
      if (para.isNotEmpty) para.write(' ');
      para.write(line.trim());
    }
  }
  flushSection();
  return (meta, sections);
}

String _firstSentences(String s, int n) {
  final re = RegExp(r'[^.!?]*[.!?]');
  final out = StringBuffer();
  var count = 0;
  for (final m in re.allMatches(s)) {
    out.write(m.group(0));
    if (++count >= n) break;
  }
  final result = out.toString().trim();
  return result.isEmpty ? s : result;
}

Future<void> main() async {
  final page = buildKnowledgePage(repoRoot: Directory('.'));
  final out = File('docs/knowledge/index.html');
  out.createSync(recursive: true);
  out.writeAsStringSync(page);
  print('Wrote ${out.path} (${page.length} bytes)');
}
