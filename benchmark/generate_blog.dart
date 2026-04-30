// ignore_for_file: avoid_print
import 'dart:io';

/// Converts project writing into styled HTML pages in `docs/blog/`.
///
/// The architecture post is rendered into `docs/blog/architecture.html`.
/// Project stories are rendered into `docs/blog/stories/*.html` and listed on
/// the blog home.
/// Experiment markdown files are rendered into `docs/blog/experiments/*.html`,
/// while the existing interactive experiment dashboard remains at
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
  ].whereType<BlogPost>().toList();

  final stories = _loadStories(Directory('doc/stories'));
  final experiments = _loadExperiments(Directory('experiments'));

  final outDir = Directory('docs/blog')..createSync(recursive: true);
  final storyOutDir = Directory('${outDir.path}/stories')
    ..createSync(recursive: true);
  final experimentOutDir = Directory('${outDir.path}/experiments')
    ..createSync(recursive: true);

  // Remove generated story HTML that may no longer correspond to a source file.
  for (final file in storyOutDir.listSync().whereType<File>()) {
    if (file.path.endsWith('.html')) file.deleteSync();
  }

  // Remove generated experiment article pages.
  for (final file in experimentOutDir.listSync().whereType<File>()) {
    if (file.path.endsWith('.html')) file.deleteSync();
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
  for (final entry in _legacyArchitectureRedirects.entries) {
    File('${outDir.path}/${entry.key}.html').writeAsStringSync(
      _renderRedirect(entry.value, 'resqlite Architecture'),
    );
    print('  ${entry.key}.html - redirect to ${entry.value}');
  }

  for (final story in stories) {
    File(
      '${storyOutDir.path}/${story.slug}.html',
    ).writeAsStringSync(_renderPost(story, PostKind.story));
    print('  stories/${story.slug}.html - ${story.title}');
  }
  File(
    '${storyOutDir.path}/index.html',
  ).writeAsStringSync(_renderRedirect('../index.html', 'resqlite Blog'));
  print('  stories/index.html - redirect to ../index.html');

  for (final experiment in experiments) {
    File(
      '${experimentOutDir.path}/${experiment.slug}.html',
    ).writeAsStringSync(
      _compactGeneratedHtml(_renderPost(experiment, PostKind.experiment)),
    );
    print('  blog/experiments/${experiment.slug}.html - ${experiment.title}');
  }

  File(
    '${experimentOutDir.path}/index.html',
  ).writeAsStringSync(
    _compactGeneratedHtml(_renderExperimentBlogIndex(experiments)),
  );
  print('  blog/experiments/index.html - Experiment posts');

  File(
    '${outDir.path}/index.html',
  ).writeAsStringSync(_renderBlogIndex(posts, stories, experiments));
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

String _experimentLabel(String slug) {
  final match = RegExp(r'^(\d+[a-z]?)').firstMatch(slug);
  return match == null ? 'Exp' : 'Exp ${match.group(1)!}';
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

  final paragraph = <String>[];
  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) {
      if (paragraph.isNotEmpty) break;
      continue;
    }
    if (line.startsWith('#')) break;
    if (line.startsWith('**') && paragraph.isEmpty) continue;
    if (line.startsWith('|')) break;
    paragraph.add(line);
    if (paragraph.join(' ').length >= 200) break;
  }
  if (paragraph.isNotEmpty) {
    final description = paragraph.join(' ');
    return description.length > 200
        ? '${description.substring(0, 197)}...'
        : description;
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

String _renderBlogIndex(
  List<BlogPost> posts,
  List<BlogPost> stories,
  List<BlogPost> experiments,
) {
  final allPosts = [
    ...stories.reversed.map(
      (post) => _renderBlogHomePostItem(
        post,
        href: 'stories/${post.slug}.html',
      ),
    ),
    ...posts.map(
        (post) => _renderBlogHomePostItem(post, href: '${post.slug}.html')),
  ].join('\n');
  final recentExperiments = experiments.reversed
      .take(3)
      .map((post) => _renderSidebarExperiment(post))
      .join('\n');

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>resqlite Blog - Engineering Notes</title>
<style>
${_sharedCss()}
${_blogIndexCss()}
</style>
</head>
<body>
<div class="page-wrap blog-wrap">
  <nav class="top-nav">
    <a href="../index.html">&larr; Home</a>
    <a href="../benchmarks/index.html">Benchmarks</a>
    <a href="../experiments/index.html">Experiment Dashboard</a>
    <a href="../api/resqlite/resqlite-library.html">API Docs</a>
  </nav>
  <header class="blog-hero">
    <span class="post-category">resqlite Blog</span>
    <h1>Engineering notes from the project.</h1>
    <p class="subtitle">A single index for the project narrative and architecture writing. Experiments live here too, with the dashboard kept as the interactive benchmark view.</p>
  </header>

  <div class="blog-layout">
    <main class="primary-column" aria-labelledby="all-posts-title">
      <div class="section-heading">
        <h2 id="all-posts-title">All Posts</h2>
        <span class="section-note">Stories and architecture notes, newest stories first.</span>
      </div>
      <div class="post-ledger">
$allPosts
      </div>
    </main>

    <aside class="blog-sidebar" aria-label="Blog context">
      <section class="sidebar-card">
        <div class="section-heading compact">
          <h2>Reference</h2>
        </div>
        <div class="sidebar-list">
${_renderProjectLinks()}
        </div>
      </section>

      <section class="sidebar-card">
        <div class="section-heading compact">
          <h2>Recent Experiments</h2>
          <a href="experiments/index.html">All &rarr;</a>
        </div>
        <div class="sidebar-list">
$recentExperiments
        </div>
      </section>
    </aside>
  </div>
</div>
</body>
</html>''';
}

String _renderBlogHomePostItem(BlogPost post, {required String href}) {
  final date =
      post.date == null ? '' : '<time>${_esc(_longDate(post.date))}</time>';
  return '''
        <a class="post-row" href="$href">
          <span class="post-row-meta">${date.isEmpty ? _esc(post.category) : '$date · ${_esc(post.category)}'}</span>
          <strong>${_esc(post.title)}</strong>
          <span>${_summaryInline(post.description)}</span>
        </a>''';
}

String _renderSidebarExperiment(BlogPost post) {
  final date =
      post.date == null ? '' : '<time>${_esc(_longDate(post.date))}</time>';
  return '''
          <a class="sidebar-item" href="experiments/${post.slug}.html">
            <span>${date.isEmpty ? _esc(post.category) : '$date · ${_esc(post.category)}'}</span>
            <strong>${_esc(post.title)}</strong>
          </a>''';
}

String _renderProjectLinks() => '''
          <a class="sidebar-item" href="architecture.html">
            <span>Architecture</span>
            <strong>Architecture Breakdown</strong>
            <em>The full system view: reader pool, writer isolate, reactive streams, native state, and data flow.</em>
          </a>
          <a class="sidebar-item" href="../benchmarks/index.html">
            <span>Benchmarks</span>
            <strong>Benchmark Dashboard</strong>
            <em>Interactive charts for current performance, history, devices, and workload comparisons.</em>
          </a>
          <a class="sidebar-item" href="../api/resqlite/resqlite-library.html">
            <span>Reference</span>
            <strong>API Documentation</strong>
            <em>Generated Dart API docs for the public resqlite package surface.</em>
          </a>''';

const _legacyArchitectureRedirects = {
  'reading': 'architecture.html',
  'writing': 'architecture.html',
  'streaming': 'architecture.html',
};

String _renderExperimentBlogIndex(List<BlogPost> experiments) {
  final entries = experiments.reversed
      .map((post) => _renderExperimentIndexItem(post))
      .join('\n');
  final acceptedCount = experiments
      .where((post) => post.category.toLowerCase().contains('accepted'))
      .length;
  final rejectedCount = experiments
      .where((post) => post.category.toLowerCase().contains('rejected'))
      .length;

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>resqlite Experiment Posts</title>
<style>
${_sharedCss()}
${_blogIndexCss()}
</style>
</head>
<body>
<div class="page-wrap blog-wrap">
  <nav class="top-nav">
    <a href="../index.html">&larr; Blog</a>
    <a href="../../index.html">Home</a>
    <a href="../../benchmarks/index.html">Benchmarks</a>
    <a href="../../experiments/index.html">Experiment Dashboard</a>
    <a href="../../api/resqlite/resqlite-library.html">API Docs</a>
  </nav>
  <header class="blog-hero">
    <span class="post-category">Experiment Posts</span>
    <h1>The resqlite research log.</h1>
    <p class="subtitle">Generated from the experiment markdown files. Each post keeps the engineering record close to the benchmark evidence: problem, hypothesis, implementation, result, and decision.</p>
  </header>

  <section class="stats-row" aria-label="Experiment post counts">
    <div><strong>${experiments.length}</strong><span>experiment posts</span></div>
    <div><strong>$acceptedCount</strong><span>accepted records</span></div>
    <div><strong>$rejectedCount</strong><span>rejected records</span></div>
  </section>

  <section class="blog-section" aria-labelledby="all-experiments-title">
    <div class="section-heading">
      <h2 id="all-experiments-title">All Experiments</h2>
      <a href="../../experiments/index.html">Open dashboard &rarr;</a>
    </div>
    <div class="experiment-ledger">
$entries
    </div>
  </section>
</div>
</body>
</html>''';
}

String _renderExperimentIndexItem(BlogPost post) {
  final fields = [
    if (post.date != null) _longDate(post.date),
    post.category,
    if (post.meta['Direction'] case final direction?) direction,
  ].where((field) => field.trim().isNotEmpty).map(_esc).join(' · ');

  return '''
      <a class="experiment-row" href="${post.slug}.html" data-tone="${_escAttr(post.tone)}">
        <span class="experiment-number">${_esc(_experimentLabel(post.slug))}</span>
        <span>
          <strong>${_esc(post.title)}</strong>
          <small>$fields</small>
          <em>${_summaryInline(post.description)}</em>
        </span>
      </a>''';
}

String _renderRedirect(String href, String title) {
  final escapedHref = _escAttr(href);
  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="refresh" content="0; url=$escapedHref">
<link rel="canonical" href="$escapedHref">
<title>${_esc(title)} — resqlite</title>
</head>
<body>
<p>This page moved to <a href="$escapedHref">$escapedHref</a>.</p>
</body>
</html>''';
}

String _renderPost(BlogPost post, PostKind kind) {
  final htmlBody = _markdownToHtml(post.content, kind);
  final isStory = kind == PostKind.story;
  final isExperiment = kind == PostKind.experiment;
  final tableOfContents = kind == PostKind.blog && post.slug == 'architecture'
      ? _renderTableOfContents(post.content)
      : '';
  final nav = switch (kind) {
    PostKind.story => '''
  <nav class="top-nav">
    <a href="../index.html">&larr; Blog</a>
    <a href="../../index.html">Home</a>
    <a href="../../benchmarks/index.html">Benchmarks</a>
    <a href="../experiments/index.html">Experiment Posts</a>
  </nav>''',
    PostKind.experiment => '''
  <nav class="top-nav">
    <a href="index.html">&larr; All Experiments</a>
    <a href="../index.html">Blog</a>
    <a href="../../index.html">Home</a>
    <a href="../../benchmarks/index.html">Benchmarks</a>
    <a href="../../experiments/index.html">Experiment Dashboard</a>
  </nav>''',
    PostKind.blog => '''
  <nav class="top-nav">
    <a href="index.html">&larr; All Posts</a>
    <a href="../index.html">Home</a>
    <a href="../benchmarks/index.html">Benchmarks</a>
    <a href="experiments/index.html">Experiment Posts</a>
  </nav>''',
  };
  final meta = isStory
      ? '    <p class="story-byline">${_esc(_longDate(post.date))}${post.tags.isEmpty ? '' : ' · ${post.tags.map(_esc).join(' · ')}'}</p>\n'
      : isExperiment
          ? _renderExperimentMeta(post)
          : '';
  final body = isStory || isExperiment
      ? '$meta$htmlBody'
      : '    $tableOfContents$htmlBody';
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

String _compactGeneratedHtml(String html) {
  final protectedBlocks = <String>[];
  final withTokens = html.replaceAllMapped(
    RegExp(r'<pre><code>.*?</code></pre>', dotAll: true),
    (match) {
      final token = '___RESQLITE_PRE_${protectedBlocks.length}___';
      protectedBlocks.add(match.group(0)!);
      return token;
    },
  );

  final compact = withTokens
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join(' ')
      .replaceAll(RegExp(r'>\s+<'), '><');

  return compact.replaceAllMapped(RegExp(r'___RESQLITE_PRE_(\d+)___'), (
    match,
  ) {
    return protectedBlocks[int.parse(match.group(1)!)];
  });
}

String _renderExperimentMeta(BlogPost post) {
  final fields = <String>[
    if (post.date != null) _longDate(post.date),
    if (post.meta['Status'] case final status?) status,
    if (post.meta['Direction'] case final direction?) direction,
  ].where((field) => field.trim().isNotEmpty).toList();

  if (fields.isEmpty) return '';
  return '    <p class="story-byline">${fields.map((field) => _inline(field, PostKind.experiment)).join(' · ')}</p>\n';
}

String _renderTableOfContents(String md) {
  final items = <({String id, String title})>[];
  final usedIds = <String>{};
  var inCodeBlock = false;

  for (final line in md.split('\n')) {
    if (line.startsWith('```')) {
      inCodeBlock = !inCodeBlock;
      continue;
    }
    if (inCodeBlock) continue;

    final trimmed = line.trim();
    final match = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(trimmed);
    if (match == null) continue;

    final level = match.group(1)!.length;
    final title = match.group(2)!.trim();
    final id = _headingAnchor(title, usedIds);
    if (level == 2) items.add((id: id, title: title));
  }

  if (items.isEmpty) return '';

  final links = items
      .map(
        (item) => '<a href="#${_escAttr(item.id)}">${_inline(item.title)}</a>',
      )
      .join('\n      ');

  return '''
    <nav class="article-toc" aria-labelledby="architecture-toc-title">
      <strong id="architecture-toc-title">On this page</strong>
      <div>
      $links
      </div>
    </nav>
''';
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
  final usedHeadingIds = <String>{};

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
      buf.writeln(
          _renderHeading(6, trimmed.substring(6).trim(), kind, usedHeadingIds));
    } else if (trimmed.startsWith('#####')) {
      buf.writeln(
          _renderHeading(5, trimmed.substring(5).trim(), kind, usedHeadingIds));
    } else if (trimmed.startsWith('####')) {
      buf.writeln(
          _renderHeading(4, trimmed.substring(4).trim(), kind, usedHeadingIds));
    } else if (trimmed.startsWith('###')) {
      buf.writeln(
          _renderHeading(3, trimmed.substring(3).trim(), kind, usedHeadingIds));
    } else if (trimmed.startsWith('##')) {
      buf.writeln(
          _renderHeading(2, trimmed.substring(2).trim(), kind, usedHeadingIds));
    } else if (trimmed.startsWith('# ')) {
      buf.writeln(
          _renderHeading(1, trimmed.substring(2).trim(), kind, usedHeadingIds));
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

String _renderHeading(
  int level,
  String title,
  PostKind kind,
  Set<String> usedIds,
) {
  final id = _headingAnchor(title, usedIds);
  return '<h$level id="${_escAttr(id)}">${_inline(title, kind)}</h$level>';
}

String _headingAnchor(String title, Set<String> usedIds) {
  final plain = _headingPlainText(title);
  var base = plain
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.isEmpty) base = 'section';

  var id = base;
  var suffix = 2;
  while (!usedIds.add(id)) {
    id = '$base-${suffix++}';
  }
  return id;
}

String _headingPlainText(String title) {
  var out = title.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (match) => match.group(1)!,
  );
  out = out.replaceAll(RegExp(r'[`*_~]'), '');
  out = out.replaceAll('&', ' and ');
  return out;
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
        header.contains('/sec') ||
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
  out = out.replaceAll('**', '');
  return out;
}

String _summaryInline(String s, {int? maxLength}) {
  final source = maxLength != null && s.length > maxLength
      ? '${s.substring(0, maxLength - 3)}...'
      : s;
  var out = _esc(source);
  out = out.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
    (m) => m.group(1)!,
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
  out = out.replaceAll('**', '');
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
    PostKind.story => '../experiments/',
    PostKind.blog => 'experiments/',
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
  .top-nav {
    display: flex;
    flex-wrap: wrap;
    gap: 0.45rem 1.5rem;
    margin-bottom: 2rem;
    font-size: 0.85rem;
  }
  .top-nav a {
    white-space: nowrap;
  }
  h1 { font-size: 1.8rem; margin-bottom: 0.5rem; }
  .subtitle { color: var(--muted); font-size: 0.95rem; margin-bottom: 2rem; }
  .post-category {
    display: inline-block; font-size: 0.7rem; font-weight: 600; text-transform: uppercase;
    letter-spacing: 0.04em; color: var(--accent); margin-bottom: 0.5rem;
  }
''';

String _blogIndexCss() => '''
  .blog-wrap { max-width: 1060px; }
  .blog-hero {
    padding: 1.5rem 0 2rem;
    margin-bottom: 2rem;
    border-bottom: 1px solid var(--border);
  }
  .blog-hero h1 {
    max-width: 760px;
    font-size: 3rem;
    line-height: 1.05;
    margin-bottom: 1rem;
  }
  .blog-layout {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 19rem;
    gap: 2.5rem;
    align-items: start;
  }
  .primary-column {
    min-width: 0;
  }
  .post-ledger {
    border-top: 1px solid var(--border);
  }
  .post-row {
    display: grid;
    gap: 0.25rem;
    padding: 1.15rem 0;
    color: var(--text);
    border-bottom: 1px solid var(--border);
  }
  .post-row:hover {
    text-decoration: none;
  }
  .post-row:hover strong {
    color: var(--accent);
  }
  .post-row strong {
    font-size: 1.08rem;
    line-height: 1.35;
  }
  .post-row span {
    color: var(--muted);
    font-size: 0.9rem;
    line-height: 1.5;
  }
  .post-row-meta,
  .post-row-meta time {
    color: var(--muted);
    font-size: 0.76rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
  .blog-sidebar {
    position: sticky;
    top: 1.5rem;
    display: grid;
    gap: 1rem;
  }
  .sidebar-card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1rem;
  }
  .sidebar-card h2 {
    margin-bottom: 0.8rem;
    font-size: 0.88rem;
    letter-spacing: 0.08em;
    line-height: 1.3;
    text-transform: uppercase;
  }
  .sidebar-list {
    display: grid;
    gap: 0;
    border-top: 1px solid var(--border);
  }
  .sidebar-item {
    display: grid;
    gap: 0.15rem;
    padding: 0.75rem 0;
    color: var(--text);
    border-bottom: 1px solid var(--border);
  }
  .sidebar-item:hover {
    text-decoration: none;
  }
  .sidebar-item:hover strong {
    color: var(--accent);
  }
  .sidebar-item span {
    color: var(--muted);
    font-size: 0.72rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
  .sidebar-item strong {
    font-size: 0.84rem;
    line-height: 1.4;
  }
  .sidebar-item em {
    color: var(--muted);
    font-size: 0.78rem;
    font-style: normal;
    line-height: 1.4;
  }
  .post-row code,
  .sidebar-item code,
  .experiment-row em code {
    color: var(--text);
    font-family: 'SF Mono', 'Fira Code', monospace;
    font-size: 0.9em;
  }
  .post-row span strong,
  .experiment-row em strong {
    color: var(--text);
    font-size: inherit;
    line-height: inherit;
  }
  .blog-section {
    margin-top: 2rem;
    padding-top: 1.5rem;
    border-top: 1px solid var(--border);
  }
  .section-heading {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 1rem;
    margin-bottom: 1rem;
  }
  .section-heading.compact {
    margin-bottom: 0.6rem;
  }
  .section-heading h2 {
    font-size: 0.95rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  .section-heading a,
  .section-note,
  .section-footnote {
    color: var(--muted);
    font-size: 0.84rem;
  }
  .section-heading a { color: var(--accent); }
  .section-footnote {
    margin-top: 1rem;
  }
  .stats-row {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    margin: 1.5rem 0 2rem;
    border-top: 1px solid var(--border);
    border-bottom: 1px solid var(--border);
  }
  .stats-row div {
    padding: 1rem;
    border-right: 1px solid var(--border);
  }
  .stats-row div:last-child {
    border-right: none;
  }
  .stats-row strong {
    display: block;
    font-size: 1.35rem;
    line-height: 1;
  }
  .stats-row span {
    color: var(--muted);
    font-size: 0.8rem;
  }
  .experiment-ledger {
    border-top: 1px solid var(--border);
  }
  .experiment-row {
    display: grid;
    grid-template-columns: 5.5rem minmax(0, 1fr);
    gap: 1rem;
    padding: 1rem 0;
    color: var(--text);
    border-bottom: 1px solid var(--border);
  }
  .experiment-row:hover {
    text-decoration: none;
  }
  .experiment-row:hover strong {
    color: var(--accent);
  }
  .experiment-number {
    color: var(--accent);
    font-family: 'SF Mono', 'Fira Code', monospace;
    font-size: 0.82rem;
    padding-top: 0.1rem;
  }
  .experiment-row strong {
    display: block;
    margin-bottom: 0.2rem;
    font-size: 0.96rem;
    line-height: 1.35;
  }
  .experiment-row small {
    display: block;
    color: var(--muted);
    font-size: 0.76rem;
    margin-bottom: 0.3rem;
  }
  .experiment-row em {
    display: block;
    color: var(--muted);
    font-size: 0.86rem;
    font-style: normal;
    line-height: 1.45;
  }
  @media (max-width: 840px) {
    .blog-hero h1 { font-size: 2.4rem; }
    .blog-layout {
      grid-template-columns: 1fr;
      gap: 2rem;
    }
    .blog-sidebar {
      position: static;
    }
    .stats-row {
      grid-template-columns: 1fr;
    }
    .stats-row div,
    .stats-row div:last-child {
      border-right: none;
      border-bottom: 1px solid var(--border);
    }
    .stats-row div:last-child {
      border-bottom: none;
    }
  }
  @media (max-width: 520px) {
    .blog-hero h1 { font-size: 2rem; }
    .section-heading {
      display: grid;
      gap: 0.35rem;
    }
    .experiment-row {
      grid-template-columns: 1fr;
      gap: 0.35rem;
    }
  }
''';

String _articleCss() => '''
  .post h1 { font-size: 1.8rem; margin-bottom: 1.5rem; line-height: 1.3; }
  .post h2 { font-size: 1.3rem; margin: 2rem 0 0.75rem; padding-bottom: 0.4rem; border-bottom: 1px solid var(--border); }
  .post h3 { font-size: 1.1rem; margin: 1.5rem 0 0.5rem; }
  .post h4 { font-size: 0.95rem; margin: 1.25rem 0 0.4rem; color: var(--muted); }
  .post h1[id],
  .post h2[id],
  .post h3[id],
  .post h4[id] {
    scroll-margin-top: 1.5rem;
  }
  .article-toc {
    margin: -0.3rem 0 1.6rem;
    padding: 0.85rem 1rem;
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 8px;
  }
  .article-toc strong {
    display: block;
    margin-bottom: 0.55rem;
    color: var(--muted);
    font-size: 0.75rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  .article-toc div {
    display: flex;
    flex-wrap: wrap;
    gap: 0.45rem 0.85rem;
  }
  .article-toc a {
    font-size: 0.84rem;
    line-height: 1.35;
  }
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
  @media (max-width: 520px) {
    .page-wrap { padding: 1.5rem; }
    .bench-table { font-size: 0.78rem; }
    .bench-table th,
    .bench-table td {
      padding: 0.45rem 0.55rem;
    }
  }
''';

String _storyBylineCss() => '''
  .story-byline {
    color: var(--muted);
    font-size: 0.82rem;
    margin: -0.75rem 0 1.5rem;
  }
''';
