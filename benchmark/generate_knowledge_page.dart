// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'generate_knowledge_graph.dart' as kg;

/// Renders `docs/knowledge/index.html` — the human documentation layer over
/// the knowledge graph.
///
/// Sources:
///   doc/arch/home.md                     — the landing page
///   doc/arch/chapters/NN-<component>.md  — one page per subsystem, each with
///                                           front-matter and inline `[[NNN.M]]`
///                                           claim citations
///   doc/arch/chapters/_viewer.html       — the page template
///   the knowledge graph                  — built in-memory (same builder the
///                                           bot uses for knowledge-graph.json)
///
/// The prose is the *authored* layer: it never regenerates from claims. The
/// page injects the live graph beside it, so citation chips always show each
/// claim's current state — a page standing on superseded evidence renders its
/// citation struck-through even before the prose is repaired, and
/// `check_knowledge_links.dart` reports the repair debt per page.
String buildKnowledgePage({required Directory repoRoot}) {
  final chaptersDir = Directory('${repoRoot.path}/doc/arch/chapters');
  final template = File('${chaptersDir.path}/_viewer.html').readAsStringSync();
  final diagrams = File('${chaptersDir.path}/_diagrams.js').readAsStringSync();

  final pages = <Map<String, Object?>>[];
  final files =
      chaptersDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) throw StateError('No chapters in ${chaptersDir.path}');

  for (final file in files) {
    final (meta, sections) = _parseDoc(file, requireKeys: const [
      'component',
      'title',
      'kicker',
      'zone',
    ]);
    final first = sections.isNotEmpty && sections.first['lede'] == true
        ? (sections.first['ps'] as List).first
        : null;
    final lede = first is String ? first : '';
    pages.add({
      'id': meta['component'],
      'section': meta['section'] ?? 'architecture',
      'zone': meta['zone'],
      'kicker': meta['kicker'],
      'name': meta['title'],
      'summary': _firstSentences(
        lede.replaceAll(RegExp(r'\[\[[\d.]+\]\]'), ''),
        2,
      ),
      'dirs': meta['directions'] ?? const [],
      'feeds': meta['feeds'] ?? const [],
      if (meta['diagram'] != null) 'diagram': meta['diagram'],
      if (meta['extraClaims'] != null) 'claims': meta['extraClaims'],
      'sections': sections,
    });
  }

  final homeFile = File('${repoRoot.path}/doc/arch/home.md');
  final (homeMeta, homeSections) = _parseDoc(
    homeFile,
    requireKeys: const ['title', 'tagline'],
  );

  final graph = kg.buildKnowledgeGraph(
    experimentsDir: Directory('${repoRoot.path}/experiments'),
  );
  return template
      .replaceFirst('__DIAGRAMS__', diagrams)
      .replaceFirst('__KG__', json.encode(graph))
      .replaceFirst('__PAGES__', json.encode(pages))
      .replaceFirst(
        '__HOME__',
        json.encode({
          'title': homeMeta['title'],
          'tagline': homeMeta['tagline'],
          'sections': homeSections,
        }),
      )
      .replaceFirst('__STATS__', json.encode(_experimentStats(repoRoot)));
}

/// Accepted/rejected counts, read straight from the experiment index. The
/// rejected count is the headline number on the landing page: a method that
/// only records what worked is a marketing document, not a record.
Map<String, Object?> _experimentStats(Directory repoRoot) {
  final dir = Directory('${repoRoot.path}/experiments/index');
  var accepted = 0, rejected = 0, total = 0;
  if (dir.existsSync()) {
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final decoded = json.decode(f.readAsStringSync());
      for (final e in decoded is List ? decoded : [decoded]) {
        if (e is! Map) continue;
        total++;
        if (e['status'] == 'accepted') accepted++;
        if (e['status'] == 'rejected') rejected++;
      }
    }
  }
  return {'total': total, 'accepted': accepted, 'rejected': rejected};
}

/// Parses front-matter plus a small block subset of markdown: `##` headings,
/// blank-line-separated paragraphs, and fenced code.
(Map<String, Object?>, List<Map<String, Object?>>) _parseDoc(
  File file, {
  required List<String> requireKeys,
}) {
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
    final value = line.substring(i + 1).trim();
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
  for (final key in requireKeys) {
    if (meta[key] == null) throw StateError('${file.path}: missing $key');
  }

  final sections = <Map<String, Object?>>[];
  var current = <String, Object?>{'lede': true, 'ps': <Object>[]};
  final para = StringBuffer();
  final code = StringBuffer();
  var inCode = false;
  var codeLang = '';

  void flushPara() {
    final text = para.toString().trim();
    if (text.isNotEmpty) (current['ps'] as List).add(text);
    para.clear();
  }

  void flushSection() {
    flushPara();
    // A heading with no body still names a slot the viewer fills (the card
    // grid), so keep sections that carry a heading even when empty.
    if ((current['ps'] as List).isNotEmpty || current['h'] != null) {
      sections.add(current);
    }
  }

  for (final line in lines.sublist(end + 1)) {
    if (line.trimLeft().startsWith('```')) {
      if (inCode) {
        (current['ps'] as List).add({
          'code': code.toString().trimRight(),
          'lang': codeLang,
        });
        code.clear();
        inCode = false;
      } else {
        flushPara();
        codeLang = line.trim().substring(3).trim();
        inCode = true;
      }
      continue;
    }
    if (inCode) {
      code.writeln(line);
    } else if (line.startsWith('## ')) {
      flushSection();
      current = <String, Object?>{
        'h': line.substring(3).trim(),
        'ps': <Object>[],
      };
    } else if (line.trim().isEmpty) {
      flushPara();
    } else {
      if (para.isNotEmpty) para.write(' ');
      para.write(line.trim());
    }
  }
  flushSection();
  // A heading with no body still names a slot the viewer fills (the card grid,
  // the method panel), so keep empty sections that carry a heading.
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
