// ignore_for_file: avoid_print
import 'dart:io';

/// Converts markdown files from `doc/` into styled HTML pages in `docs/blog/`.
///
/// Architecture/deep-dive posts are rendered into `docs/blog/*.html`.
/// Project stories are rendered into `docs/blog/stories/*.html`, with a
/// chronological timeline at `docs/blog/stories/index.html`.
/// Experiment markdown files are rendered into `docs/experiments/*.html`, while
/// the existing interactive experiment dashboard remains at
/// `docs/experiments/index.html`.
///
/// Usage:
///   dart run benchmark/generate_blog.dart
void main() {
  final posts = [
    _loadPost(
      path: 'doc/arch/architecture.md',
      slug: 'architecture',
      category: 'Architecture',
    ),
    _loadPost(
      path: 'doc/arch/reading.md',
      slug: 'reading',
      category: 'Deep Dive',
    ),
    _loadPost(
      path: 'doc/arch/writing.md',
      slug: 'writing',
      category: 'Deep Dive',
    ),
    _loadPost(
      path: 'doc/arch/streaming.md',
      slug: 'streaming',
      category: 'Deep Dive',
    ),
  ].whereType<BlogPost>().toList();

  final stories = _loadStories(Directory('doc/stories'));
  final experiments = _loadExperiments(Directory('experiments'));

  final outDir = Directory('docs/blog')..createSync(recursive: true);
  final storyOutDir = Directory('${outDir.path}/stories')
    ..createSync(recursive: true);
  final experimentOutDir = Directory('docs/experiments')
    ..createSync(recursive: true);

  // Remove generated story HTML that may no longer correspond to a source file.
  for (final file in storyOutDir.listSync().whereType<File>()) {
    if (file.path.endsWith('.html')) file.deleteSync();
  }

  // Remove generated experiment article pages. Keep the hand-authored
  // interactive dashboard at index.html.
  for (final file in experimentOutDir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.endsWith('.html') && name != 'index.html') file.deleteSync();
  }

  // Remove the old milestone page. Stories are the canonical narrative surface.
  final oldMilestones = File('${outDir.path}/milestones.html');
  if (oldMilestones.existsSync()) oldMilestones.deleteSync();

  for (final post in posts) {
    File(
      '${outDir.path}/${post.slug}.html',
    ).writeAsStringSync(_renderPost(post, PostKind.blog));
    print('  ${post.slug}.html - ${post.title}');
  }

  for (final story in stories) {
    File(
      '${storyOutDir.path}/${story.slug}.html',
    ).writeAsStringSync(_renderPost(story, PostKind.story));
    print('  stories/${story.slug}.html - ${story.title}');
  }

  for (final experiment in experiments) {
    File(
      '${experimentOutDir.path}/${experiment.slug}.html',
    ).writeAsStringSync(_renderPost(experiment, PostKind.experiment));
    print('  experiments/${experiment.slug}.html - ${experiment.title}');
  }

  File(
    '${storyOutDir.path}/index.html',
  ).writeAsStringSync(_renderStoryIndex(stories));
  print('  stories/index.html - Stories timeline');

  File('${outDir.path}/index.html').writeAsStringSync(_renderBlogIndex(posts));
  print('  index.html - Blog index');

  print(
    'Wrote ${posts.length} posts + ${stories.length} stories + '
    '${experiments.length} experiments to docs/',
  );
}

enum PostKind { blog, story, experiment }

class BlogPost {
  BlogPost({
    required this.slug,
    required this.title,
    required this.category,
    required this.description,
    required this.content,
    this.date,
    this.tags = const [],
    this.tone = 'green',
    this.meta = const {},
  });

  final String slug;
  final String title;
  final String category;
  final String description;
  final String content;
  final DateTime? date;
  final List<String> tags;
  final String tone;
  final Map<String, String> meta;
}

BlogPost? _loadPost({
  required String path,
  required String slug,
  required String category,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    print('  Skipping $path (not found)');
    return null;
  }

  final content = file.readAsStringSync();
  return BlogPost(
    slug: slug,
    title: _extractTitle(content),
    category: category,
    description: _extractDescription(content),
    content: content,
  );
}

List<BlogPost> _loadStories(Directory dir) {
  if (!dir.existsSync()) return const [];

  final stories = <BlogPost>[];
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.md')) continue;
    final raw = file.readAsStringSync();
    final parsed = _splitFrontMatter(raw);
    final meta = parsed.meta;
    final content = parsed.content;
    final filename = file.uri.pathSegments.last;
    final fallbackSlug = filename.substring(0, filename.length - 3);
    final slug = meta['slug']?.trim().isNotEmpty == true
        ? meta['slug']!.trim()
        : fallbackSlug;
    final dateText = meta['date']?.trim();
    final date =
        dateText == null || dateText.isEmpty ? null : DateTime.parse(dateText);

    stories.add(
      BlogPost(
        slug: slug,
        title: meta['title']?.trim().isNotEmpty == true
            ? meta['title']!.trim()
            : _extractTitle(content),
        category: 'Project Story',
        description: meta['summary']?.trim().isNotEmpty == true
            ? meta['summary']!.trim()
            : _extractDescription(content),
        content: content,
        date: date,
        tags: _parseTags(meta['tags']),
        tone: meta['tone']?.trim().isNotEmpty == true
            ? meta['tone']!.trim()
            : 'green',
      ),
    );
  }

  stories.sort((a, b) {
    final ad = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bd = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byDate = ad.compareTo(bd);
    if (byDate != 0) return byDate;
    return a.slug.compareTo(b.slug);
  });
  return stories;
}

List<BlogPost> _loadExperiments(Directory dir) {
  if (!dir.existsSync()) return const [];

  final experiments = <BlogPost>[];
  for (final file in dir.listSync().whereType<File>()) {
    final filename = file.uri.pathSegments.last;
    if (!_isExperimentMarkdown(filename)) continue;

    final content = file.readAsStringSync();
    final meta = _extractExperimentMeta(content);
    final status = meta['Status'] ?? 'Experiment';
    experiments.add(
      BlogPost(
        slug: filename.substring(0, filename.length - 3),
        title: _extractTitle(content),
        category: status,
        description: _extractExperimentDescription(content),
        content: content,
        date: _parseExperimentDate(meta['Date']),
        tags: status == 'Experiment' ? const [] : [status],
        tone: _experimentTone(status),
        meta: meta,
      ),
    );
  }

  experiments.sort((a, b) {
    final an = _experimentNumber(a.slug);
    final bn = _experimentNumber(b.slug);
    if (an != bn) return an.compareTo(bn);
    return a.slug.compareTo(b.slug);
  });
  return experiments;
}

bool _isExperimentMarkdown(String filename) =>
    RegExp(r'^\d{3}[a-z]?-.+\.md$').hasMatch(filename);

int _experimentNumber(String slug) {
  final match = RegExp(r'^(\d+)').firstMatch(slug);
  return match == null ? 999999 : int.parse(match.group(1)!);
}

Map<String, String> _extractExperimentMeta(String content) {
  final meta = <String, String>{};
  for (final line in content.split('\n')) {
    final match = RegExp(r'^\*\*([^:*]+):\*\*\s*(.+)$').firstMatch(line.trim());
    if (match != null) {
      meta[match.group(1)!.trim()] = match.group(2)!.trim();
    }
  }
  return meta;
}

DateTime? _parseExperimentDate(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

String _experimentTone(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('accepted')) return 'green';
  if (normalized.contains('rejected')) return 'rose';
  if (normalized.contains('review')) return 'amber';
  if (normalized.contains('deferred')) return 'violet';
  return 'amber';
}

String _extractExperimentDescription(String content) {
  final lines = content.split('\n');
  final start = lines.indexWhere(
    (line) => RegExp(r'^##\s+(Problem|Hypothesis|Background)').hasMatch(line),
  );
  if (start == -1) return _extractDescription(content);

  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('**')) continue;
    if (line.startsWith('#')) break;
    return line.length > 200 ? '${line.substring(0, 197)}...' : line;
  }
  return _extractDescription(content);
}

({Map<String, String> meta, String content}) _splitFrontMatter(String raw) {
  final lines = raw.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') {
    return (meta: const {}, content: raw);
  }

  final meta = <String, String>{};
  var end = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      end = i;
      break;
    }
    final match = RegExp(r'^([A-Za-z0-9_-]+):\s*(.*)$').firstMatch(lines[i]);
    if (match != null) {
      meta[match.group(1)!] = match.group(2)!.trim();
    }
  }

  if (end == -1) return (meta: const {}, content: raw);
  return (meta: meta, content: lines.skip(end + 1).join('\n').trimLeft());
}

List<String> _parseTags(String? tags) {
  if (tags == null || tags.trim().isEmpty) return const [];
  return tags
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList();
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
      for (var j = i + 1; j < lines.length; j++) {
        final line = lines[j].trim();
        if (line.isEmpty) continue;
        if (line.startsWith('#')) break;
        return line.length > 200 ? '${line.substring(0, 197)}...' : line;
      }
    }
  }
  return '';
}

String _renderBlogIndex(List<BlogPost> posts) {
  final cards = [
    '''
    <a class="post-card" href="stories/index.html">
      <span class="post-category">Project Stories</span>
      <h2>The Chronological History of resqlite</h2>
      <p>An annotated timeline of the design decisions behind resqlite: object graphs, flat-list rows, reader-pool tradeoffs, stream invalidation, write serialization, and a Dart VM hang.</p>
    </a>''',
    ...posts.map(
      (p) => '''
    <a class="post-card" href="${p.slug}.html">
      <span class="post-category">${_esc(p.category)}</span>
      <h2>${_esc(p.title)}</h2>
      <p>${_esc(p.description)}</p>
    </a>''',
    ),
  ].join('\n');

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>resqlite Blog - Stories &amp; Architecture</title>
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
    <a href="../index.html">&larr; Home</a>
    <a href="../benchmarks/index.html">Benchmarks</a>
    <a href="../experiments/index.html">Experiments</a>
    <a href="../api/resqlite/resqlite-library.html">API Docs</a>
  </nav>
  <h1>Stories &amp; Architecture</h1>
  <p class="subtitle">The chronological engineering history of resqlite, plus technical deep-dives into how the library works.</p>
  <div class="post-list">
$cards
  </div>
</div>
</body>
</html>''';
}

String _renderStoryIndex(List<BlogPost> stories) {
  final entries = stories.map(_renderStoryTimelineEntry).join('\n');
  final leadTitle = stories.isEmpty ? 'Stories' : _esc(stories.first.title);
  final leadDescription = stories.isEmpty
      ? 'Project stories will appear here as markdown posts are added.'
      : _inline(stories.first.description);

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>resqlite Stories - Project Timeline</title>
<style>
${_storyIndexCss()}
</style>
</head>
<body>
<div class="page-wrap">
  <nav class="top-nav">
    <a href="../index.html">&larr; Blog</a>
    <a href="../../index.html">Home</a>
    <a href="../../benchmarks/index.html">Benchmarks</a>
    <a href="../../experiments/index.html">Experiments</a>
    <a href="../../api/resqlite/resqlite-library.html">API Docs</a>
  </nav>

  <header class="hero">
    <div>
      <span class="eyebrow">Project Stories</span>
      <h1>The chronological history of resqlite.</h1>
      <p class="subtitle">The public docs explain what the library does. The experiment log records every measurement. These stories explain the design decisions that changed the project, with enough context to read any entry on its own.</p>
    </div>
    <a class="lead-card" href="${stories.isEmpty ? '../index.html' : '${stories.first.slug}.html'}">
      <span class="label">Start here</span>
      <h2>$leadTitle</h2>
      <p>$leadDescription</p>
    </a>
  </header>

  <section class="stats" aria-label="Project story highlights">
    <div class="stat">
      <strong>${stories.length}</strong>
      <span>chronological stories split from the original project narrative</span>
    </div>
    <div class="stat">
      <strong>0.47 ms</strong>
      <span>main-isolate time for 5,000-row map reads in the early benchmark set</span>
    </div>
    <div class="stat">
      <strong>116K</strong>
      <span>point queries per second measured after the reader event-port cleanup</span>
    </div>
    <div class="stat">
      <strong>6 days</strong>
      <span>from filing the Flutter hang to the Dart VM fix landing upstream</span>
    </div>
  </section>

  <section aria-labelledby="timeline-title">
    <div class="section-heading">
      <h2 id="timeline-title">Timeline</h2>
      <a href="../../experiments/index.html">Open the experiment log &rarr;</a>
    </div>

    <div class="timeline">
$entries
    </div>
  </section>

  <section class="lower-links" aria-label="Related documentation">
    <a class="link-card" href="../../experiments/index.html">
      <h3>Experiment Log</h3>
      <p>The complete lab notebook: accepted ideas, rejected ideas, benchmark links, and reasoning.</p>
    </a>
    <a class="link-card" href="../../benchmarks/index.html">
      <h3>Benchmark Dashboard</h3>
      <p>Interactive charts for peer comparisons, run history, devices, and scenario workloads.</p>
    </a>
    <a class="link-card" href="../architecture.html">
      <h3>Architecture</h3>
      <p>The system-level view of readers, writers, native handles, and streaming behavior.</p>
    </a>
  </section>
</div>
</body>
</html>''';
}

String _renderStoryTimelineEntry(BlogPost story) {
  final tags = story.tags
      .map((tag) => '<span class="tag">${_esc(tag)}</span>')
      .join('\n              ');
  return '''
      <article class="story-entry" data-tone="${_escAttr(story.tone)}">
        <div class="story-date">
          <strong>${_storyMonthDay(story.date)}</strong>
          ${story.date?.year ?? ''}
        </div>
        <a class="story-card" href="${story.slug}.html">
          <div>
            <h3>${_esc(story.title)}</h3>
            <p>${_inline(story.description)}</p>
            <div class="story-meta">
              $tags
            </div>
          </div>
          <span class="story-action">Read story &rarr;</span>
        </a>
      </article>''';
}

String _renderPost(BlogPost post, PostKind kind) {
  final htmlBody = _markdownToHtml(post.content, kind);
  final isStory = kind == PostKind.story;
  final isExperiment = kind == PostKind.experiment;
  final nav = switch (kind) {
    PostKind.story => '''
  <nav class="top-nav">
    <a href="index.html">&larr; All Stories</a>
    <a href="../index.html">Blog</a>
    <a href="../../index.html">Home</a>
    <a href="../../benchmarks/index.html">Benchmarks</a>
    <a href="../../experiments/index.html">Experiments</a>
  </nav>''',
    PostKind.experiment => '''
  <nav class="top-nav">
    <a href="index.html">&larr; Experiment Dashboard</a>
    <a href="../blog/stories/index.html">Stories</a>
    <a href="../blog/index.html">Blog</a>
    <a href="../index.html">Home</a>
    <a href="../benchmarks/index.html">Benchmarks</a>
  </nav>''',
    PostKind.blog => '''
  <nav class="top-nav">
    <a href="index.html">&larr; All Posts</a>
    <a href="../index.html">Home</a>
    <a href="../benchmarks/index.html">Benchmarks</a>
    <a href="../experiments/index.html">Experiments</a>
  </nav>''',
  };
  final meta = isStory
      ? '    <p class="story-byline">${_esc(_longDate(post.date))}${post.tags.isEmpty ? '' : ' · ${post.tags.map(_esc).join(' · ')}'}</p>\n'
      : isExperiment
          ? _renderExperimentMeta(post)
          : '';
  final body = isStory || isExperiment ? '$meta$htmlBody' : '    $htmlBody';
  final extraCss = isStory || isExperiment ? _storyBylineCss() : '';

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${_esc(post.title)} — resqlite</title>
<style>
${_sharedCss()}
${_articleCss()}$extraCss
</style>
</head>
<body>
<div class="page-wrap">
$nav
  <article class="post">
    <span class="post-category">${_esc(post.category)}</span>
$body
  </article>
</div>
</body>
</html>''';
}

String _renderExperimentMeta(BlogPost post) {
  final fields = <String>[
    if (post.date != null) _longDate(post.date),
    if (post.meta['Status'] case final status?) status,
    if (post.meta['Direction'] case final direction?) direction,
  ].where((field) => field.trim().isNotEmpty).toList();

  if (fields.isEmpty) return '';
  return '    <p class="story-byline">${fields.map(_inline).join(' · ')}</p>\n';
}

String _storyMonthDay(DateTime? date) {
  if (date == null) return '';
  return '${_month(date.month)} ${date.day.toString().padLeft(2, '0')}';
}

String _longDate(DateTime? date) {
  if (date == null) return '';
  return '${_month(date.month)} ${date.day}, ${date.year}';
}

String _month(int month) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[month - 1];
}

/// Convert markdown to HTML. Handles headings, paragraphs, code blocks,
/// inline code, bold, lists, tables, and horizontal rules.
String _markdownToHtml(String md, PostKind kind) {
  final lines = md.split('\n');
  final buf = StringBuffer();
  var inCodeBlock = false;
  var inList = false;
  var listType = '';
  final tableRows = <String>[];

  void flushTable() {
    if (tableRows.isEmpty) return;
    buf.writeln(_renderTable(tableRows, kind));
    tableRows.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    if (line.startsWith('```')) {
      flushTable();
      if (inCodeBlock) {
        buf.writeln('</code></pre>');
        inCodeBlock = false;
      } else {
        if (inList) {
          buf.writeln(listType == 'ol' ? '</ol>' : '</ul>');
          inList = false;
        }
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

    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      if (inList) {
        buf.writeln(listType == 'ol' ? '</ol>' : '</ul>');
        inList = false;
      }
      tableRows.add(trimmed);
      continue;
    }
    flushTable();

    if (trimmed.isEmpty) {
      if (inList) {
        buf.writeln(listType == 'ol' ? '</ol>' : '</ul>');
        inList = false;
      }
      continue;
    }

    if (trimmed.startsWith('######')) {
      buf.writeln('<h6>${_inline(trimmed.substring(6).trim(), kind)}</h6>');
    } else if (trimmed.startsWith('#####')) {
      buf.writeln('<h5>${_inline(trimmed.substring(5).trim(), kind)}</h5>');
    } else if (trimmed.startsWith('####')) {
      buf.writeln('<h4>${_inline(trimmed.substring(4).trim(), kind)}</h4>');
    } else if (trimmed.startsWith('###')) {
      buf.writeln('<h3>${_inline(trimmed.substring(3).trim(), kind)}</h3>');
    } else if (trimmed.startsWith('##')) {
      buf.writeln('<h2>${_inline(trimmed.substring(2).trim(), kind)}</h2>');
    } else if (trimmed.startsWith('# ')) {
      buf.writeln('<h1>${_inline(trimmed.substring(2).trim(), kind)}</h1>');
    } else if (RegExp(r'^-{3,}$').hasMatch(trimmed)) {
      buf.writeln('<hr>');
    } else if (RegExp(r'^[-*]\s').hasMatch(trimmed)) {
      if (!inList) {
        buf.writeln('<ul>');
        inList = true;
        listType = 'ul';
      }
      buf.writeln(
        '<li>${_inline(trimmed.replaceFirst(RegExp(r'^[-*]\s+'), ''), kind)}</li>',
      );
    } else if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
      if (!inList) {
        buf.writeln('<ol>');
        inList = true;
        listType = 'ol';
      }
      buf.writeln(
        '<li>${_inline(trimmed.replaceFirst(RegExp(r'^\d+\.\s+'), ''), kind)}</li>',
      );
    } else {
      if (inList) {
        buf.writeln(listType == 'ol' ? '</ol>' : '</ul>');
        inList = false;
      }
      buf.writeln('<p>${_inline(trimmed, kind)}</p>');
    }
  }
  flushTable();
  if (inList) buf.writeln(listType == 'ol' ? '</ol>' : '</ul>');
  if (inCodeBlock) buf.writeln('</code></pre>');

  return buf.toString();
}

String _renderTable(List<String> rows, PostKind kind) {
  if (rows.isEmpty) return '';

  List<String> parseCells(String row) =>
      row.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  final dataRows =
      rows.where((r) => !RegExp(r'^\|[\s\-:|]+\|$').hasMatch(r)).toList();
  if (dataRows.isEmpty) return '';

  final headerCells = parseCells(dataRows[0]);
  final bodyRows = dataRows.skip(1).map(parseCells).toList();

  final numericCols = <int>{};
  for (final row in bodyRows) {
    for (var c = 0; c < row.length; c++) {
      final header = c < headerCells.length ? headerCells[c].toLowerCase() : '';
      if (_isDimensionColumn(header)) continue;
      final val = row[c].replaceAll(RegExp(r'[*`]'), '');
      if (double.tryParse(val) != null) numericCols.add(c);
    }
  }

  final colBest = <int, double>{};
  for (final c in numericCols) {
    final header = c < headerCells.length ? headerCells[c].toLowerCase() : '';
    final higherIsBetter = header.contains('qps') ||
        header.contains('ops') ||
        header.contains('throughput');
    double? best;
    for (final row in bodyRows) {
      if (c >= row.length) continue;
      final val = double.tryParse(row[c].replaceAll(RegExp(r'[*`]'), ''));
      if (val == null) continue;
      if (best == null || (higherIsBetter ? val > best : val < best)) {
        best = val;
      }
    }
    if (best != null) colBest[c] = best;
  }

  final buf = StringBuffer();
  buf.writeln('<div class="table-wrap"><table class="bench-table">');
  buf.writeln('<thead><tr>');
  for (final cell in headerCells) {
    buf.writeln('<th>${_inline(cell, kind)}</th>');
  }
  buf.writeln('</tr></thead>');

  buf.writeln('<tbody>');
  for (final row in bodyRows) {
    buf.writeln('<tr>');
    for (var c = 0; c < row.length; c++) {
      final raw = row[c];
      final clean = raw.replaceAll(RegExp(r'[*`]'), '');
      final val = double.tryParse(clean);
      final isBest = val != null && colBest[c] == val && bodyRows.length > 1;
      final cls = isBest ? ' class="winner"' : '';
      buf.writeln('<td$cls>${_inline(raw, kind)}</td>');
    }
    buf.writeln('</tr>');
  }
  buf.writeln('</tbody></table></div>');

  return buf.toString();
}

bool _isDimensionColumn(String header) {
  final normalized = header.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  return normalized == 'row' ||
      normalized == 'rows' ||
      normalized == 'size' ||
      normalized == 'scenario' ||
      normalized == 'workload' ||
      normalized == 'path' ||
      normalized == 'phase' ||
      normalized == 'metric' ||
      normalized == 'implementation';
}

String _inline(String s, [PostKind kind = PostKind.blog]) {
  var out = _esc(s);
  out = out.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
    (m) => '<a href="${_htmlHref(m.group(2)!, kind)}">${m.group(1)}</a>',
  );
  out = out.replaceAllMapped(
    RegExp(r'\*\*([^*]+)\*\*'),
    (m) => '<strong>${m.group(1)}</strong>',
  );
  out = out.replaceAllMapped(
    RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)'),
    (m) => '<em>${m.group(1)}</em>',
  );
  out = out.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (m) => '<code>${m.group(1)}</code>',
  );
  return out;
}

String _htmlHref(String href, PostKind kind) {
  if (href.startsWith('http:') ||
      href.startsWith('https:') ||
      href.startsWith('mailto:') ||
      href.startsWith('#')) {
    return _escAttr(href);
  }

  final hashIndex = href.indexOf('#');
  final path = hashIndex == -1 ? href : href.substring(0, hashIndex);
  final anchor = hashIndex == -1 ? '' : href.substring(hashIndex);

  if (path == '../../experiments/' || path == '../../../experiments/') {
    return _escAttr('${_experimentsPrefix(kind)}index.html$anchor');
  }

  if (path.endsWith('.md')) {
    final filename = path.split('/').last;
    final slug = filename.substring(0, filename.length - 3);
    if (_isExperimentMarkdown(filename)) {
      return _escAttr('${_experimentsPrefix(kind)}$slug.html$anchor');
    }
    if (kind == PostKind.blog && path.startsWith('./')) {
      return _escAttr('${path.substring(2, path.length - 3)}.html$anchor');
    }
    return _escAttr(_githubSourceHref(path, kind, anchor));
  }
  if (path.endsWith('.json')) {
    return _escAttr(_githubSourceHref(path, kind, anchor));
  }

  if (kind == PostKind.experiment && _looksLikeRepoFile(path)) {
    return _escAttr(_githubSourceHref(path, kind, anchor));
  }

  if (path.endsWith('/')) return _escAttr('${path}index.html$anchor');
  return _escAttr(href);
}

bool _looksLikeRepoFile(String path) {
  if (path.startsWith('/')) return true;
  if (path.startsWith('../') || path.startsWith('./')) return true;
  return RegExp(r'^[A-Za-z0-9_.-]+\.[A-Za-z0-9]+$').hasMatch(path);
}

String _experimentsPrefix(PostKind kind) {
  return switch (kind) {
    PostKind.story => '../../experiments/',
    PostKind.blog => '../experiments/',
    PostKind.experiment => '',
  };
}

String _githubSourceHref(String path, PostKind kind, String anchor) {
  const base = 'https://github.com/danReynolds/resqlite/blob/main/';
  final repoPath = _repoRelativePath(path, kind);
  return '$base$repoPath$anchor';
}

String _repoRelativePath(String path, PostKind kind) {
  if (path.startsWith('/')) {
    const markers = ['/packages/resqlite/', '/resqlite/'];
    for (final marker in markers) {
      final index = path.indexOf(marker);
      if (index != -1) return path.substring(index + marker.length);
    }
    return path.split('/').last;
  }

  final parts = <String>[
    ...switch (kind) {
      PostKind.story => ['doc', 'stories'],
      PostKind.blog => ['doc', 'arch'],
      PostKind.experiment => ['experiments'],
    },
  ];

  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}

String _esc(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String _escAttr(String s) => _esc(s).replaceAll("'", '&#39;');

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

String _storyBylineCss() => '''
  .story-byline {
    color: var(--muted);
    font-size: 0.82rem;
    margin: -0.75rem 0 1.5rem;
  }
''';

String _storyIndexCss() => '''
  :root {
    --bg: #0d1117;
    --panel: #131821;
    --panel-2: #10151d;
    --border: #30363d;
    --text: #e6edf3;
    --muted: #8b949e;
    --accent: #58a6ff;
    --green: #3fb950;
    --amber: #d29922;
    --rose: #ff7b72;
    --violet: #bc8cff;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
    line-height: 1.6;
  }
  a { color: inherit; text-decoration: none; }
  a:hover { text-decoration: none; }
  .page-wrap {
    width: min(1120px, 100%);
    margin: 0 auto;
    padding: 2rem;
  }
  .top-nav {
    display: flex;
    flex-wrap: wrap;
    gap: 1rem 1.5rem;
    margin-bottom: 3rem;
    font-size: 0.85rem;
    color: var(--muted);
  }
  .top-nav a { color: var(--accent); }
  .top-nav a:hover { text-decoration: underline; }
  .hero {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 320px;
    gap: 3rem;
    align-items: end;
    padding-bottom: 3rem;
    border-bottom: 1px solid var(--border);
  }
  .eyebrow {
    display: inline-block;
    margin-bottom: 0.75rem;
    color: var(--green);
    font-size: 0.72rem;
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  h1 {
    max-width: 760px;
    margin-bottom: 1rem;
    font-size: clamp(2.4rem, 7vw, 5.25rem);
    line-height: 0.95;
    letter-spacing: 0;
  }
  .subtitle {
    max-width: 680px;
    color: var(--muted);
    font-size: 1.05rem;
  }
  .lead-card {
    display: block;
    padding: 1.25rem;
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 8px;
    transition: border-color 0.15s, transform 0.15s;
  }
  .lead-card:hover {
    border-color: var(--accent);
    transform: translateY(-2px);
  }
  .lead-card .label {
    display: block;
    margin-bottom: 0.45rem;
    color: var(--amber);
    font-size: 0.72rem;
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  .lead-card h2 {
    margin-bottom: 0.5rem;
    font-size: 1.1rem;
    line-height: 1.3;
  }
  .lead-card p {
    color: var(--muted);
    font-size: 0.88rem;
    line-height: 1.5;
  }
  .stats {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 1rem;
    margin: 2rem 0 3rem;
  }
  .stat {
    padding: 1rem;
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 8px;
  }
  .stat strong {
    display: block;
    margin-bottom: 0.25rem;
    color: var(--text);
    font-size: 1.35rem;
    line-height: 1;
  }
  .stat span {
    color: var(--muted);
    font-size: 0.78rem;
    line-height: 1.35;
  }
  .section-heading {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 1rem;
    margin-bottom: 1.5rem;
  }
  .section-heading h2 {
    font-size: 1rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  .section-heading a {
    color: var(--accent);
    font-size: 0.85rem;
  }
  .section-heading a:hover { text-decoration: underline; }
  .timeline {
    position: relative;
    display: grid;
    gap: 1.25rem;
    padding-bottom: 2rem;
  }
  .timeline::before {
    content: "";
    position: absolute;
    top: 0.6rem;
    bottom: 0;
    left: 8.75rem;
    width: 1px;
    background: var(--border);
  }
  .story-entry {
    position: relative;
    display: grid;
    grid-template-columns: 7.5rem minmax(0, 1fr);
    gap: 2.5rem;
    align-items: stretch;
  }
  .story-date {
    padding-top: 1rem;
    color: var(--muted);
    font-size: 0.82rem;
    text-align: right;
  }
  .story-date strong {
    display: block;
    color: var(--text);
    font-size: 0.95rem;
  }
  .story-card {
    position: relative;
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 1.5rem;
    padding: 1.25rem 1.35rem;
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 8px;
    transition: border-color 0.15s, transform 0.15s;
  }
  .story-card::before {
    content: "";
    position: absolute;
    top: 1.35rem;
    left: -1.82rem;
    width: 0.78rem;
    height: 0.78rem;
    background: var(--accent);
    border: 3px solid var(--bg);
    border-radius: 999px;
  }
  .story-card:hover {
    border-color: var(--accent);
    transform: translateX(3px);
  }
  .story-card h3 {
    margin-bottom: 0.45rem;
    font-size: 1.15rem;
    line-height: 1.3;
  }
  .story-card p {
    max-width: 760px;
    color: var(--muted);
    font-size: 0.92rem;
    line-height: 1.6;
  }
  .story-card code {
    color: var(--text);
    font-family: 'SF Mono', 'Fira Code', monospace;
    font-size: 0.88em;
  }
  .story-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 0.45rem;
    margin-top: 0.85rem;
  }
  .tag {
    display: inline-flex;
    align-items: center;
    min-height: 1.55rem;
    padding: 0 0.5rem;
    color: var(--muted);
    background: rgba(139, 148, 158, 0.08);
    border: 1px solid rgba(139, 148, 158, 0.2);
    border-radius: 999px;
    font-size: 0.72rem;
  }
  .story-action {
    align-self: center;
    color: var(--accent);
    font-size: 0.85rem;
    white-space: nowrap;
  }
  .story-entry[data-tone="green"] .story-card::before { background: var(--green); }
  .story-entry[data-tone="amber"] .story-card::before { background: var(--amber); }
  .story-entry[data-tone="rose"] .story-card::before { background: var(--rose); }
  .story-entry[data-tone="violet"] .story-card::before { background: var(--violet); }
  .lower-links {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 1rem;
    margin-top: 2rem;
    padding-top: 2rem;
    border-top: 1px solid var(--border);
  }
  .link-card {
    display: block;
    padding: 1.1rem;
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 8px;
    transition: border-color 0.15s, transform 0.15s;
  }
  .link-card:hover {
    border-color: var(--accent);
    transform: translateY(-2px);
  }
  .link-card h3 {
    margin-bottom: 0.35rem;
    font-size: 0.95rem;
  }
  .link-card p {
    color: var(--muted);
    font-size: 0.82rem;
    line-height: 1.45;
  }
  @media (max-width: 840px) {
    .page-wrap { padding: 1.25rem; }
    .hero { grid-template-columns: 1fr; gap: 1.5rem; }
    .stats { grid-template-columns: repeat(2, 1fr); }
    .timeline::before { left: 0.4rem; }
    .story-entry {
      grid-template-columns: 1fr;
      gap: 0.55rem;
      padding-left: 1.85rem;
    }
    .story-date {
      padding-top: 0;
      text-align: left;
    }
    .story-card { grid-template-columns: 1fr; gap: 1rem; }
    .story-card::before {
      top: 1.35rem;
      left: -1.84rem;
    }
    .story-action { justify-self: start; }
    .lower-links { grid-template-columns: 1fr; }
  }
  @media (max-width: 520px) {
    .stats { grid-template-columns: 1fr; }
    h1 { font-size: 2.55rem; }
  }
''';
