// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// Converts markdown files from `doc/` into styled HTML pages
/// in `docs/blog/`, plus an index page.
///
/// Usage:
///   dart run benchmark/generate_blog.dart
void main() {
  final posts = <Map<String, String>>[];

  // Define post order and metadata.
  final sources = [
    (
      path: 'doc/story.md',
      slug: 'story',
      category: 'Engineering Story',
    ),
    (
      path: 'doc/arch/architecture.md',
      slug: 'architecture',
      category: 'Architecture',
    ),
    (
      path: 'doc/arch/reading.md',
      slug: 'reading',
      category: 'Deep Dive',
    ),
    (
      path: 'doc/arch/writing.md',
      slug: 'writing',
      category: 'Deep Dive',
    ),
    (
      path: 'doc/arch/streaming.md',
      slug: 'streaming',
      category: 'Deep Dive',
    ),
  ];

  for (final source in sources) {
    final file = File(source.path);
    if (!file.existsSync()) {
      print('  Skipping ${source.path} (not found)');
      continue;
    }
    final content = file.readAsStringSync();
    final title = _extractTitle(content);
    final description = _extractDescription(content);

    posts.add({
      'slug': source.slug,
      'title': title,
      'category': source.category,
      'description': description,
      'content': content,
    });
  }

  // Write individual post pages.
  final outDir = Directory('docs/blog');
  outDir.createSync(recursive: true);

  for (final post in posts) {
    final html = _renderPost(post, posts);
    File('${outDir.path}/${post['slug']}.html')
        .writeAsStringSync(html);
    print('  ${post['slug']}.html — ${post['title']}');
  }

  // Write index page.
  File('${outDir.path}/index.html')
      .writeAsStringSync(_renderIndex(posts));
  print('  index.html — Blog index');

  print('Wrote ${posts.length} posts + index to docs/blog/');
}

String _extractTitle(String content) {
  for (final line in content.split('\n')) {
    if (line.startsWith('# ')) return line.substring(2).trim();
  }
  return 'Untitled';
}

String _extractDescription(String content) {
  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('# ')) {
      // Take the first non-empty paragraph after the title.
      for (var j = i + 1; j < lines.length; j++) {
        final line = lines[j].trim();
        if (line.isEmpty) continue;
        if (line.startsWith('#')) break;
        // Truncate long descriptions.
        return line.length > 200 ? '${line.substring(0, 197)}...' : line;
      }
    }
  }
  return '';
}

String _renderIndex(List<Map<String, String>> posts) {
  final cards = posts.map((p) => '''
    <a class="post-card" href="${p['slug']}.html">
      <span class="post-category">${_esc(p['category']!)}</span>
      <h2>${_esc(p['title']!)}</h2>
      <p>${_esc(p['description']!)}</p>
    </a>''').join('\n');

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>resqlite Blog — Architecture &amp; Engineering</title>
<style>
${_sharedCss()}
  .post-list { display: flex; flex-direction: column; gap: 1rem; max-width: 720px; margin: 0 auto; }
  .post-card {
    display: block; text-decoration: none; color: var(--text);
    background: var(--card); border: 1px solid var(--border); border-radius: 10px;
    padding: 1.5rem; transition: border-color 0.15s, transform 0.15s;
  }
  .post-card:hover { border-color: var(--accent); transform: translateY(-2px); text-decoration: none; }
  .post-card h2 { font-size: 1.15rem; margin-bottom: 0.4rem; }
  .post-card p { font-size: 0.88rem; color: var(--muted); line-height: 1.5; }
  .post-category {
    display: inline-block; font-size: 0.7rem; font-weight: 600; text-transform: uppercase;
    letter-spacing: 0.04em; color: var(--accent); margin-bottom: 0.5rem;
  }
</style>
</head>
<body>
<div class="page-wrap">
  <nav class="top-nav">
    <a href="../">&larr; Home</a>
    <a href="../benchmarks/">Benchmarks</a>
    <a href="../experiments/">Experiments</a>
    <a href="../api/resqlite/resqlite-library.html">API Docs</a>
  </nav>
  <h1>Architecture &amp; Engineering</h1>
  <p class="subtitle">Technical deep-dives into how resqlite works and why it's fast.</p>
  <div class="post-list">
$cards
  </div>
</div>
</body>
</html>''';
}

String _renderPost(
  Map<String, String> post,
  List<Map<String, String>> allPosts,
) {
  final content = post['content']!;
  final htmlBody = _markdownToHtml(content);

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${_esc(post['title']!)} — resqlite</title>
<style>
${_sharedCss()}
${_articleCss()}
</style>
</head>
<body>
<div class="page-wrap">
  <nav class="top-nav">
    <a href="./">&larr; All Posts</a>
    <a href="../">Home</a>
    <a href="../benchmarks/">Benchmarks</a>
    <a href="../experiments/">Experiments</a>
  </nav>
  <article class="post">
    <span class="post-category">${_esc(post['category']!)}</span>
    $htmlBody
  </article>
</div>
</body>
</html>''';
}

/// Convert markdown to HTML. Handles headings, paragraphs, code blocks,
/// inline code, bold, lists, tables, and horizontal rules.
String _markdownToHtml(String md) {
  final lines = md.split('\n');
  final buf = StringBuffer();
  var inCodeBlock = false;
  var inList = false;
  var listType = '';
  final tableRows = <String>[];

  void _flushTable() {
    if (tableRows.isEmpty) return;
    buf.writeln(_renderTable(tableRows));
    tableRows.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    // Code blocks.
    if (line.startsWith('```')) {
      _flushTable();
      if (inCodeBlock) {
        buf.writeln('</code></pre>');
        inCodeBlock = false;
      } else {
        if (inList) { buf.writeln(listType == 'ol' ? '</ol>' : '</ul>'); inList = false; }
        final lang = line.substring(3).trim();
        buf.writeln('<pre><code class="lang-$lang">');
        inCodeBlock = true;
      }
      continue;
    }
    if (inCodeBlock) {
      buf.writeln(_esc(line));
      continue;
    }

    final trimmed = line.trim();

    // Table rows: collect and render as a batch.
    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      if (inList) { buf.writeln(listType == 'ol' ? '</ol>' : '</ul>'); inList = false; }
      tableRows.add(trimmed);
      continue;
    }
    _flushTable();

    // Blank line — close list if open.
    if (trimmed.isEmpty) {
      if (inList) { buf.writeln(listType == 'ol' ? '</ol>' : '</ul>'); inList = false; }
      continue;
    }

    // Headings.
    if (trimmed.startsWith('######')) {
      buf.writeln('<h6>${_inline(trimmed.substring(6).trim())}</h6>');
    } else if (trimmed.startsWith('#####')) {
      buf.writeln('<h5>${_inline(trimmed.substring(5).trim())}</h5>');
    } else if (trimmed.startsWith('####')) {
      buf.writeln('<h4>${_inline(trimmed.substring(4).trim())}</h4>');
    } else if (trimmed.startsWith('###')) {
      buf.writeln('<h3>${_inline(trimmed.substring(3).trim())}</h3>');
    } else if (trimmed.startsWith('##')) {
      buf.writeln('<h2>${_inline(trimmed.substring(2).trim())}</h2>');
    } else if (trimmed.startsWith('# ')) {
      buf.writeln('<h1>${_inline(trimmed.substring(2).trim())}</h1>');
    }
    // Horizontal rule.
    else if (RegExp(r'^-{3,}$').hasMatch(trimmed)) {
      buf.writeln('<hr>');
    }
    // Unordered list.
    else if (RegExp(r'^[-*]\s').hasMatch(trimmed)) {
      if (!inList) { buf.writeln('<ul>'); inList = true; listType = 'ul'; }
      buf.writeln('<li>${_inline(trimmed.replaceFirst(RegExp(r'^[-*]\s+'), ''))}</li>');
    }
    // Ordered list.
    else if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
      if (!inList) { buf.writeln('<ol>'); inList = true; listType = 'ol'; }
      buf.writeln('<li>${_inline(trimmed.replaceFirst(RegExp(r'^\d+\.\s+'), ''))}</li>');
    }
    // Paragraph.
    else {
      if (inList) { buf.writeln(listType == 'ol' ? '</ol>' : '</ul>'); inList = false; }
      buf.writeln('<p>${_inline(trimmed)}</p>');
    }
  }
  _flushTable();
  if (inList) buf.writeln(listType == 'ol' ? '</ol>' : '</ul>');
  if (inCodeBlock) buf.writeln('</code></pre>');

  return buf.toString();
}

/// Render a markdown table as a styled HTML table with winner highlighting.
/// For numeric columns, the best value (lowest, or highest for qps/ops) gets
/// a green highlight.
String _renderTable(List<String> rows) {
  if (rows.isEmpty) return '';

  // Parse cells from each row.
  List<String> parseCells(String row) =>
      row.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  // Skip separator rows (|---|---|).
  final dataRows = rows
      .where((r) => !RegExp(r'^\|[\s\-:|]+\|$').hasMatch(r))
      .toList();
  if (dataRows.isEmpty) return '';

  final headerCells = parseCells(dataRows[0]);
  final bodyRows = dataRows.skip(1).map(parseCells).toList();

  // Detect which columns are numeric (for winner highlighting).
  final numericCols = <int>{};
  for (final row in bodyRows) {
    for (var c = 0; c < row.length; c++) {
      final val = row[c].replaceAll(RegExp(r'[*`]'), '');
      if (double.tryParse(val) != null) numericCols.add(c);
    }
  }

  // For each numeric column, find the best value.
  // "Best" = lowest, unless column header contains qps/ops/throughput.
  final colBest = <int, double>{};
  for (final c in numericCols) {
    final header = c < headerCells.length ? headerCells[c].toLowerCase() : '';
    final higherIsBetter = header.contains('qps') || header.contains('ops') ||
        header.contains('throughput');
    double? best;
    for (final row in bodyRows) {
      if (c >= row.length) continue;
      final val = double.tryParse(row[c].replaceAll(RegExp(r'[*`]'), ''));
      if (val == null) continue;
      if (best == null ||
          (higherIsBetter ? val > best : val < best)) {
        best = val;
      }
    }
    if (best != null) colBest[c] = best;
  }

  final buf = StringBuffer();
  buf.writeln('<div class="table-wrap"><table class="bench-table">');

  // Header.
  buf.writeln('<thead><tr>');
  for (final cell in headerCells) {
    buf.writeln('<th>${_inline(cell)}</th>');
  }
  buf.writeln('</tr></thead>');

  // Body rows.
  buf.writeln('<tbody>');
  for (final row in bodyRows) {
    buf.writeln('<tr>');
    for (var c = 0; c < row.length; c++) {
      final raw = row[c];
      final clean = raw.replaceAll(RegExp(r'[*`]'), '');
      final val = double.tryParse(clean);
      final isBest = val != null && colBest[c] == val && bodyRows.length > 1;
      final cls = isBest ? ' class="winner"' : '';
      buf.writeln('<td$cls>${_inline(raw)}</td>');
    }
    buf.writeln('</tr>');
  }
  buf.writeln('</tbody></table></div>');

  return buf.toString();
}

/// Inline formatting: bold, italic, code, links.
String _inline(String s) {
  var out = _esc(s);
  // Links: [text](url)
  out = out.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
    (m) => '<a href="${m.group(2)}">${m.group(1)}</a>',
  );
  // Bold: **text**
  out = out.replaceAllMapped(
    RegExp(r'\*\*([^*]+)\*\*'),
    (m) => '<strong>${m.group(1)}</strong>',
  );
  // Italic: *text* (but not inside bold)
  out = out.replaceAllMapped(
    RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)'),
    (m) => '<em>${m.group(1)}</em>',
  );
  // Inline code: `text`
  out = out.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (m) => '<code>${m.group(1)}</code>',
  );
  return out;
}

String _esc(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String _sharedCss() => '''
  :root {
    --bg: #0d1117; --card: #161b22; --border: #30363d;
    --text: #e6edf3; --muted: #8b949e; --accent: #58a6ff;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: var(--bg); color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
    line-height: 1.6;
  }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  .page-wrap { max-width: 720px; margin: 0 auto; padding: 2rem; }
  .top-nav { margin-bottom: 2rem; font-size: 0.85rem; }
  .top-nav a { margin-right: 1.5rem; }
  h1 { font-size: 1.8rem; margin-bottom: 0.5rem; }
  .subtitle { color: var(--muted); font-size: 0.95rem; margin-bottom: 2rem; }
  .post-category {
    display: inline-block; font-size: 0.7rem; font-weight: 600; text-transform: uppercase;
    letter-spacing: 0.04em; color: var(--accent); margin-bottom: 0.5rem;
  }
''';

String _articleCss() => '''
  .post h1 { font-size: 1.8rem; margin-bottom: 1.5rem; line-height: 1.3; }
  .post h2 { font-size: 1.3rem; margin: 2rem 0 0.75rem; padding-bottom: 0.4rem; border-bottom: 1px solid var(--border); }
  .post h3 { font-size: 1.1rem; margin: 1.5rem 0 0.5rem; }
  .post h4 { font-size: 0.95rem; margin: 1.25rem 0 0.4rem; color: var(--muted); }
  .post p { margin-bottom: 1rem; font-size: 0.95rem; line-height: 1.7; }
  .post ul, .post ol { padding-left: 1.5rem; margin-bottom: 1rem; }
  .post li { margin-bottom: 0.3rem; font-size: 0.95rem; line-height: 1.6; }
  .post code {
    background: rgba(88,166,255,0.08); padding: 0.15rem 0.4rem;
    border-radius: 4px; font-size: 0.85em;
    font-family: 'SF Mono', 'Fira Code', monospace;
  }
  .post pre {
    background: var(--card); border: 1px solid var(--border); border-radius: 8px;
    padding: 1rem 1.25rem; overflow-x: auto; margin-bottom: 1.25rem;
    font-size: 0.85rem; line-height: 1.6;
  }
  .post pre code {
    background: none; padding: 0; border-radius: 0; font-size: inherit;
  }
  .post hr {
    border: none; border-top: 1px solid var(--border); margin: 2rem 0;
  }
  .post strong { color: var(--text); }
  .post a { color: var(--accent); }
  .table-wrap { overflow-x: auto; margin-bottom: 1.25rem; }
  .bench-table {
    width: 100%; border-collapse: collapse; font-size: 0.85rem;
    background: var(--card); border: 1px solid var(--border); border-radius: 8px;
    overflow: hidden;
  }
  .bench-table th {
    text-align: left; padding: 0.6rem 0.75rem; font-weight: 600;
    color: var(--muted); border-bottom: 1px solid var(--border);
    font-size: 0.8rem;
  }
  .bench-table td {
    padding: 0.5rem 0.75rem; border-bottom: 1px solid var(--border);
  }
  .bench-table th:not(:first-child),
  .bench-table td:not(:first-child) { text-align: right; }
  .bench-table tr:last-child td { border-bottom: none; }
  .bench-table tr:hover td { background: rgba(88,166,255,0.04); }
  .bench-table .winner { color: #3fb950; font-weight: 600; }
''';
