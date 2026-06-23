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

  // Append in the canonical position (after the synthesis), preserving the
  // base key order.
  return <String, Object?>{...base, 'experiments': experiments};
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
