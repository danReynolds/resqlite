// ignore_for_file: avoid_print
//
// Generates `docs/releases/releases.json` for the GitHub Pages "Releases"
// page (`docs/releases/index.html`). One entry per published version, tying
// together three sources:
//
//   1. CHANGELOG.md       — the per-version changelog body (kept as markdown,
//                           rendered client-side).
//   2. docs/experiments/history.json — the experiments run during each
//                           version's development, mapped by date window
//                           (an experiment dated after release N-1 and on/
//                           before release N shipped in N). Accepted and
//                           rejected both appear; the rejections show the
//                           exploration behind the version.
//   3. benchmark/version_benchmarks.json — curated release-suite medians per
//                           version (populated by the same-machine backfill),
//                           from which consecutive-version deltas are computed.
//
// Re-run after any CHANGELOG edit, new experiment, or refreshed backfill:
//   dart run benchmark/generate_releases.dart
import 'dart:convert';
import 'dart:io';

void main() {
  final changelog = _parseChangelog(File('CHANGELOG.md').readAsStringSync());
  final experiments = _loadExperiments('docs/experiments/history.json');
  final bench =
      jsonDecode(File('benchmark/version_benchmarks.json').readAsStringSync())
          as Map<String, dynamic>;

  final curated = (bench['metricsCurated'] as List)
      .cast<Map<String, dynamic>>();
  final versionRows = (bench['versions'] as List).cast<Map<String, dynamic>>();
  final dateByVersion = <String, String>{
    for (final v in versionRows) v['version'] as String: v['date'] as String,
  };
  final metricsByVersion = <String, Map<String, dynamic>>{
    for (final v in versionRows)
      v['version'] as String:
          ((v['metrics'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{}),
  };
  final crossDriftByVersion = <String, num>{
    for (final v in versionRows)
      if (v['crossDriftPct'] != null)
        v['version'] as String: v['crossDriftPct'] as num,
  };

  // Versions in descending semver order, as they appear in the changelog.
  final versions = changelog.map((e) => e.version).toList();
  final latestVersion = versions.isEmpty ? null : versions.first;
  final latestDate = latestVersion == null
      ? null
      : dateByVersion[latestVersion];

  final releases = <Map<String, dynamic>>[];
  for (var i = 0; i < versions.length; i++) {
    final version = versions[i];
    final date = dateByVersion[version];
    final prevVersion = i + 1 < versions.length ? versions[i + 1] : null;
    final prevDate = prevVersion == null ? null : dateByVersion[prevVersion];

    releases.add({
      'version': version,
      'date': date,
      'bodyMarkdown': changelog[i].body,
      // The latest release uses a strict upper bound: an experiment dated on
      // the release date landed *after* the release was cut (you publish, then
      // keep working that day), so it belongs to "Unreleased", not the release.
      'experiments': _experimentsInWindow(
        experiments,
        prevDate,
        date,
        strictUpper: i == 0,
      ),
      'deltas': _deltas(
        curated,
        metricsByVersion[version] ?? const {},
        prevVersion == null
            ? const {}
            : (metricsByVersion[prevVersion] ?? const {}),
        prevVersion,
        crossDriftByVersion[version] ?? 0,
      ),
    });
  }

  // Experiments dated on or after the latest release are post-release work,
  // not yet in a published version. Surface them in an "Unreleased" card.
  final unreleased = latestDate == null
      ? const <Map<String, dynamic>>[]
      : (experiments
            .where((e) => (e['date'] as String).compareTo(latestDate) >= 0)
            .toList()
          ..sort((a, b) => (b['id'] as String).compareTo(a['id'] as String)));
  if (unreleased.isNotEmpty) {
    releases.insert(0, {
      'version': 'Unreleased',
      'date': null,
      'sinceVersion': latestVersion,
      'bodyMarkdown': '',
      'experiments': unreleased,
      'deltas': const [],
    });
  }

  final out = {
    'generated': DateTime.now().toIso8601String(),
    'metricGroups': _groups(curated),
    'releases': releases,
  };

  final outFile = File('docs/releases/releases.json');
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(out)}\n',
  );
  print(
    'Wrote ${outFile.path} (${releases.length} releases, '
    '${experiments.length} experiments mapped by date).',
  );
  for (final r in releases) {
    final exps = (r['experiments'] as List).length;
    final deltas = (r['deltas'] as List).length;
    print(
      '  ${r['version']}  ${r['date'] ?? '?'}  '
      '$exps experiments, $deltas benchmark deltas',
    );
  }
}

class _ChangelogEntry {
  _ChangelogEntry(this.version, this.body);
  final String version;
  final String body;
}

/// Splits CHANGELOG.md into `## X.Y.Z` sections, preserving each body as
/// markdown. Order is as-written (newest first).
List<_ChangelogEntry> _parseChangelog(String md) {
  final entries = <_ChangelogEntry>[];
  final lines = md.split('\n');
  final header = RegExp(r'^##\s+(\d+\.\d+\.\d+)\s*$');
  String? cur;
  final body = <String>[];
  void flush() {
    final v = cur;
    if (v != null) {
      entries.add(_ChangelogEntry(v, body.join('\n').trim()));
      body.clear();
    }
  }

  for (final line in lines) {
    final m = header.firstMatch(line);
    if (m != null) {
      flush();
      cur = m.group(1);
    } else if (cur != null) {
      body.add(line);
    }
  }
  flush();
  return entries;
}

List<Map<String, dynamic>> _loadExperiments(String path) {
  final data =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final raw = (data['experiments'] as List).cast<Map<String, dynamic>>();
  final urls = _experimentUrls();
  return raw
      .where((e) => e['date'] != null)
      .map(
        (e) => {
          'id': e['id'],
          'title': e['title'],
          'date': e['date'],
          'status': e['status'],
          'summary': e['summary'] ?? '',
          if (urls[e['id']] != null) 'url': urls[e['id']],
        },
      )
      .toList();
}

/// Maps experiment id → GitHub writeup URL by resolving `experiments/NNN-*.md`.
Map<String, String> _experimentUrls() {
  const base = 'https://github.com/danReynolds/resqlite/blob/main/experiments';
  final dir = Directory('experiments');
  final out = <String, String>{};
  if (!dir.existsSync()) return out;
  final re = RegExp(r'^(\d{3})-.*\.md$');
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    final m = re.firstMatch(name);
    if (m != null) out[m.group(1)!] = '$base/$name';
  }
  return out;
}

/// Experiments dated in `(prevDate, date]` — i.e. run between the previous
/// release and this one. For the first release prevDate is null (open start).
List<Map<String, dynamic>> _experimentsInWindow(
  List<Map<String, dynamic>> experiments,
  String? prevDate,
  String? date, {
  bool strictUpper = false,
}) {
  if (date == null) return const [];
  final inWindow = experiments.where((e) {
    final d = e['date'] as String;
    final afterPrev = prevDate == null || d.compareTo(prevDate) > 0;
    final cmp = d.compareTo(date);
    final beforeUpper = strictUpper ? cmp < 0 : cmp <= 0;
    return afterPrev && beforeUpper;
  }).toList()..sort((a, b) => (b['id'] as String).compareTo(a['id'] as String));
  return inWindow;
}

/// Per-metric delta vs the previous version, for the curated metric set.
/// Only emits a metric when both versions measured it. Each delta carries a
/// `confidence` against an effective threshold = max(within-run comparison
/// threshold, cross-version machine-drift floor). The drift floor is measured
/// from the peer libraries (drift/sqlite3/sqlite_async), which run identical
/// code in every version's suite, so their delta between two version runs IS
/// the machine drift between those runs — the part a within-run MAD can't see.
///   - "noise": |delta| within the effective threshold → not real signal.
///   - "low":   exceeds it but the metric is flagged `noisy` → unreliable.
///   - "high":  exceeds it on a non-noisy metric → trustworthy.
List<Map<String, dynamic>> _deltas(
  List<Map<String, dynamic>> curated,
  Map<String, dynamic> cur,
  Map<String, dynamic> prev,
  String? prevVersion,
  num crossDriftFloor,
) {
  if (prevVersion == null) return const [];
  final out = <Map<String, dynamic>>[];
  for (final m in curated) {
    final key = m['key'] as String;
    final c = cur[key] as Map<String, dynamic>?;
    final p = prev[key] as Map<String, dynamic>?;
    if (c == null || p == null) continue;
    final cm = c['m'] as num;
    final pm = p['m'] as num;
    if (pm == 0) continue;
    final deltaPct = (cm - pm) / pm * 100;
    // Effective significance bar = the strictest of: the metric's within-run
    // comparison threshold, the pair's measured peer-library drift floor
    // (p90), and a conservative absolute minimum. The absolute minimum exists
    // because single-pass cross-version measurement on a shared machine can't
    // resolve sub-~30% shifts — resqlite's own paths sometimes drift more than
    // the peer libraries between two runs, so a delta must be dramatic before
    // we call it real rather than measurement artifact.
    const minRealDeltaPct = 30;
    final effThr = [
      (c['thr'] as num?) ?? 10,
      (p['thr'] as num?) ?? 10,
      crossDriftFloor,
      minRealDeltaPct,
    ].reduce((a, b) => a > b ? a : b);
    final noisy = c['stab'] == 'noisy' || p['stab'] == 'noisy';
    final confidence = deltaPct.abs() <= effThr
        ? 'noise'
        : noisy
        ? 'low'
        : 'high';
    out.add({
      'key': key,
      'label': m['label'],
      'group': m['group'],
      'higherIsBetter': m['higherIsBetter'] ?? false,
      'prev': pm,
      'cur': cm,
      'deltaPct': deltaPct,
      'thresholdPct': effThr,
      'confidence': confidence,
    });
  }
  return out;
}

List<String> _groups(List<Map<String, dynamic>> curated) {
  final seen = <String>[];
  for (final m in curated) {
    final g = m['group'] as String;
    if (!seen.contains(g)) seen.add(g);
  }
  return seen;
}
