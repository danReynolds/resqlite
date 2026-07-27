// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// Assembles `experiments/signals.json` from its hand-edited sources:
///
///   experiments/signals/base.json        — schema metadata + the per-direction
///                                           research synthesis (`directions[]`)
///   experiments/signals/entries/NNN.json  — one file per experiment, holding
///                                           that experiment's
///                                           {directions, outcomeClass,
///                                            changedBeliefs, nextSignals}
///
/// `signals.json` is a *generated* aggregate owned by the post-merge "Update
/// Docs Data" bot — see experiments/RUNNER_INSTRUCTIONS.md. Experiments add an
/// entry fragment (their own file, so two concurrent experiments never touch
/// the same one) and, when a direction's synthesis changes, edit `base.json`.
/// They never hand-edit `signals.json`.
Map<String, Object?> buildSignalsData({
  required Directory signalsSourceDir,
  String? generatedAt,
}) {
  final baseFile = File('${signalsSourceDir.path}/base.json');
  if (!baseFile.existsSync()) {
    throw StateError('Missing signals source: ${baseFile.path}');
  }
  final base = json.decode(baseFile.readAsStringSync());
  if (base is! Map<String, Object?>) {
    throw StateError('${baseFile.path} must be a top-level JSON object.');
  }
  if (base.containsKey('experiments')) {
    throw StateError(
      '${baseFile.path} must not contain "experiments"; per-experiment entries '
      'live in ${signalsSourceDir.path}/entries/NNN.json.',
    );
  }

  final entriesDir = Directory('${signalsSourceDir.path}/entries');
  final entryFiles = entriesDir.existsSync()
      ? entriesDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
      : <File>[];

  final ids = <String>[];
  final byId = <String, Object?>{};
  for (final file in entryFiles) {
    final id = file.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), '');
    final decoded = json.decode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw StateError('${file.path} must be a JSON object.');
    }
    if (byId.containsKey(id)) {
      throw StateError('Duplicate signals entry for experiment $id.');
    }
    byId[id] = decoded;
    ids.add(id);
  }
  ids.sort(_compareExperimentIds);

  final experiments = <String, Object?>{for (final id in ids) id: byId[id]};

  _injectBeliefs(base, experiments);

  // Append in the canonical position (after the synthesis), preserving the
  // base key order.
  return <String, Object?>{...base, 'experiments': experiments};
}

/// Derives each direction's generated `beliefs` block from the entries'
/// typed `claims`.
///
/// A claim's state is *derived from edges*, never stored: it is `superseded`
/// or `refuted` when another claim targets it with that edge type, else
/// `live`. Runners record claims in their own entry file; nobody hand-edits a
/// direction's belief set — which is what keeps concurrent runs from
/// conflicting on the synthesis the way hand-edited `currentRead` prose does.
void _injectBeliefs(
  Map<String, Object?> base,
  Map<String, Object?> experiments,
) {
  // claim id -> (claim, source exp id, that entry's directions)
  final all = <String, (Map<String, Object?>, String, List<String>)>{};
  for (final entry in experiments.entries) {
    final note = entry.value;
    if (note is! Map<String, Object?>) continue;
    final claims = note['claims'];
    if (claims is! List) continue;
    final dirs = [
      for (final d in (note['directions'] as List? ?? const []))
        d.toString(),
    ];
    for (final c in claims) {
      if (c is Map<String, Object?> && c['id'] is String) {
        all[c['id'] as String] = (c, entry.key, dirs);
      }
    }
  }
  if (all.isEmpty) return;

  final supersededBy = <String, List<String>>{};
  final refutedBy = <String, List<String>>{};
  for (final e in all.entries) {
    for (final edge in (e.value.$1['edges'] as List? ?? const [])) {
      if (edge is! Map || edge['target'] is! String) continue;
      final target = edge['target'] as String;
      if (edge['type'] == 'supersedes') {
        (supersededBy[target] ??= []).add(e.key);
      } else if (edge['type'] == 'refutes') {
        (refutedBy[target] ??= []).add(e.key);
      }
    }
  }

  final directions = base['directions'];
  if (directions is! List) return;
  for (final dir in directions) {
    if (dir is! Map<String, Object?> || dir['id'] is! String) continue;
    final dirId = dir['id'] as String;
    var entriesInDirection = 0;
    var entriesWithClaims = 0;
    for (final note in experiments.values) {
      if (note is! Map<String, Object?>) continue;
      final dirs = (note['directions'] as List? ?? const []);
      if (!dirs.map((d) => d.toString()).contains(dirId)) continue;
      entriesInDirection++;
      if ((note['claims'] as List? ?? const []).isNotEmpty) {
        entriesWithClaims++;
      }
    }
    final live = <Map<String, Object?>>[];
    final superseded = <Map<String, Object?>>[];
    final refuted = <Map<String, Object?>>[];
    final ids = all.keys.toList()..sort(_compareClaimIds);
    for (final id in ids) {
      final (claim, source, dirs) = all[id]!;
      if (!dirs.contains(dirId)) continue;
      final item = <String, Object?>{
        'id': id,
        'source': source,
        'text': claim['text'],
        if (claim['conditions'] != null) 'conditions': claim['conditions'],
      };
      if (refutedBy.containsKey(id)) {
        refuted.add({...item, 'by': refutedBy[id]});
      } else if (supersededBy.containsKey(id)) {
        superseded.add({...item, 'by': supersededBy[id]});
      } else {
        live.add(item);
      }
    }
    if (live.isEmpty && superseded.isEmpty && refuted.isEmpty) continue;
    dir['beliefs'] = <String, Object?>{
      'note':
          'Generated from entries[].claims — record new claims in your own '
          'signals/entries/NNN.json; never edit this block.',
      // PARTIAL until this direction's entries all carry claims: coverage
      // says how much of the direction's history has been distilled, so a
      // reader knows whether currentRead still holds beliefs not listed here.
      'coverage': {
        'entriesWithClaims': entriesWithClaims,
        'entriesInDirection': entriesInDirection,
      },
      'live': live,
      if (superseded.isNotEmpty) 'superseded': superseded,
      if (refuted.isNotEmpty) 'refuted': refuted,
    };
  }
}

int _compareClaimIds(String a, String b) {
  List<int> parts(String s) =>
      [for (final p in s.split('.')) int.tryParse(p) ?? 0];
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 2; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return a.compareTo(b);
}

int _compareExperimentIds(String a, String b) {
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
  final data = buildSignalsData(
    signalsSourceDir: Directory('experiments/signals'),
  );
  const encoder = JsonEncoder.withIndent('  ');
  File('experiments/signals.json').writeAsStringSync('${encoder.convert(data)}\n');
  final experiments = data['experiments'] as Map<String, Object?>;
  final directions = data['directions'] as List<Object?>;
  print(
    'Wrote experiments/signals.json '
    '(${experiments.length} experiment entries, ${directions.length} directions).',
  );
}
