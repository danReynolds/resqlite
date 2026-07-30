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
  _enrichExperiments(repoRoot, graph);
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

/// Adds what the evidence drawer needs but `knowledge-graph.json` does not
/// carry: the index's `impact` prose, and the signal entry's class, changed
/// beliefs and follow-on signals.
///
/// Only experiments that actually back a claim are enriched — the drawer never
/// shows the others, and embedding all 211 would triple the page for nothing.
/// The long-form writeup (problem / hypothesis / results / reasoning) is *not*
/// embedded: it already ships as `docs/experiments/history.json` for the
/// experiments dashboard, and the drawer fetches it on first open.
///
/// Enriching here rather than in the graph builder keeps `knowledge-graph.json`
/// stable — agents and CI consume it, and it should not grow fields that exist
/// only to render a panel.
void _enrichExperiments(Directory repoRoot, Map<String, Object?> graph) {
  final cited = <String>{
    for (final c in (graph['claims'] as List).cast<Map<String, Object?>>())
      if (c['source'] != null) c['source'] as String,
  };
  final experiments = (graph['experiments'] as List).cast<Map<String, Object?>>();
  for (final e in experiments) {
    final id = e['id'] as String?;
    if (id == null || !cited.contains(id)) continue;

    final index = File('${repoRoot.path}/experiments/index/$id.json');
    if (index.existsSync()) {
      final decoded = json.decode(index.readAsStringSync());
      final entry = decoded is List
          ? (decoded.whereType<Map>().isEmpty
                ? const {}
                : decoded.whereType<Map>().first)
          : decoded as Map;
      if (entry['impact'] != null) e['impact'] = entry['impact'];
    }

    final signal = File('${repoRoot.path}/experiments/signals/entries/$id.json');
    if (signal.existsSync()) {
      final s = json.decode(signal.readAsStringSync());
      if (s is Map) {
        if (s['experimentClass'] != null) e['class'] = s['experimentClass'];
        if (s['changedBeliefs'] != null) e['changed'] = s['changedBeliefs'];
        if (s['nextSignals'] != null) e['next'] = s['nextSignals'];
      }
    }
  }
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
  (String, String)? codeRef;

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
          'code': switch (codeRef) {
            (final path, final region) => _docRegion(
              File('${file.parent.parent.parent.path}/$path'),
              region,
            ),
            null => code.toString().trimRight(),
          },
          'lang': codeLang,
        });
        code.clear();
        codeRef = null;
        inCode = false;
      } else {
        flushPara();
        // ```dart file=test/samples/x_test.dart#region  — transcluded, so the
        // markdown holds a reference and the rendered page holds the code.
        final info = line.trim().substring(3).trim();
        final ref = RegExp(r'file=(\S+?)#(\S+)').firstMatch(info);
        codeLang = info.split(RegExp(r'\s+')).first;
        codeRef = ref == null ? null : (ref.group(1)!, ref.group(2)!);
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

/// Pulls a `#docregion` out of a source file.
///
/// This is the strongest binding the docs have. A hash pin detects that a code
/// sample drifted; transclusion makes drifting impossible, because the sample
/// and the tested source are the same text. Use it wherever documented code can
/// actually be run, and fall back to hashes only where it cannot.
///
/// A region may open and close more than once — the fragments concatenate, so a
/// sample can skip over test scaffolding (fixture setup, assertions) without
/// showing it to a reader. Same convention dart.dev uses.
String _docRegion(File file, String region) {
  if (!file.existsSync()) {
    throw StateError('Code sample references a missing file: ${file.path}');
  }
  final open = RegExp(r'^\s*//\s*#docregion\s+' + RegExp.escape(region) + r'\s*$');
  final close = RegExp(r'^\s*//\s*#enddocregion\s+' + RegExp.escape(region) + r'\s*$');
  final out = <String>[];
  var inside = false;
  for (final line in file.readAsStringSync().split('\n')) {
    if (open.hasMatch(line)) {
      inside = true;
      continue;
    }
    if (close.hasMatch(line)) {
      inside = false;
      continue;
    }
    if (inside) out.add(line);
  }
  if (out.isEmpty) {
    throw StateError(
      'No #docregion "$region" in ${file.path} — the sample it backs would '
      'render empty.',
    );
  }
  // Regions are nested inside a test body, so strip the shared indent.
  final indents = out
      .where((l) => l.trim().isNotEmpty)
      .map((l) => l.length - l.trimLeft().length);
  final strip = indents.isEmpty ? 0 : indents.reduce((a, b) => a < b ? a : b);
  return out
      .map((l) => l.length >= strip ? l.substring(strip) : l)
      .join('\n')
      .trim();
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

Future<void> main(List<String> args) async {
  // `--check` builds the page without writing it, so CI can prove every
  // transcluded code sample still resolves on a PR. The page itself is a
  // bot-owned aggregate that branches must not commit, so validating it and
  // writing it have to be separable.
  final checkOnly = args.contains('--check');
  final String page;
  try {
    page = buildKnowledgePage(repoRoot: Directory('.'));
  } on StateError catch (e) {
    print('::error::${e.message}');
    exitCode = 1;
    return;
  }
  if (checkOnly) {
    print('Knowledge page builds (${page.length} bytes); all code samples resolve.');
    return;
  }
  final out = File('docs/knowledge/index.html');
  out.createSync(recursive: true);
  out.writeAsStringSync(page);
  print('Wrote ${out.path} (${page.length} bytes)');
}
