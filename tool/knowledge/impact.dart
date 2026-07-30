// ignore_for_file: avoid_print
/// Reports how a change moved the project's understanding, not just its code.
///
///   dart run tool/knowledge/impact.dart            # against origin/main
///   dart run tool/knowledge/impact.dart <base>     # against any revision
///
/// A diff already says what code changed. What no tool said was which *beliefs*
/// changed — what was learned, what was retired, and which documented passages
/// are now standing on something that moved. That is computable, because claims
/// carry ids, dates, and typed edges.
///
/// The mechanical half lives here: the affected set. The half that matters to a
/// reader — what it *means* — is prose a human writes into the experiment's
/// `changedBeliefs`, and this tool prints the two together so a reviewer sees
/// the claim and its explanation side by side. Deliberately silent when nothing
/// moved: a report that appears on every PR stops being read by the third one.
library;

import 'dart:convert';
import 'dart:io';

import 'pin.dart';

const _entriesDir = 'experiments/signals/entries';
const _docGlobs = ['doc/arch/chapters', 'doc/arch'];

typedef Claim = ({String id, String source, String text, List<String> restsOn});

void main(List<String> args) {
  final base = args.isEmpty
      ? 'origin/main'
      : args.first.replaceAll(RegExp(r'\.\.\.?.*$'), '');
  if (!_revExists(base)) {
    print('::warning::No revision "$base" to compare against; skipping.');
    return;
  }

  final before = _claimsAt(base);
  final after = _claimsHere();
  final beforeState = _states(before);
  final afterState = _states(after);

  final born = after.keys.where((id) => !before.containsKey(id)).toList()
    ..sort();
  final retired = <String>[];
  final unsupported = <String>[];
  for (final id in after.keys) {
    if (!before.containsKey(id)) continue;
    final was = beforeState[id], now = afterState[id];
    if (was == now) continue;
    if (now == 'superseded' || now == 'refuted') retired.add(id);
    if (now == 'unsupported') unsupported.add(id);
  }
  retired.sort();
  unsupported.sort();

  if (born.isEmpty && retired.isEmpty && unsupported.isEmpty) {
    print('No recorded beliefs changed in this range.');
    return;
  }

  final buf = StringBuffer('### Belief impact\n');

  if (born.isNotEmpty) {
    buf.writeln('\n**Learned**\n');
    for (final id in born) {
      buf.writeln('- `$id` — ${_oneLine(after[id]!.text)}  _(exp ${after[id]!.source})_');
    }
  }

  if (retired.isNotEmpty) {
    buf.writeln('\n**Retired**\n');
    for (final id in retired) {
      final by = _killersOf(id, after).join(', ');
      buf.writeln('- `$id` — ${_oneLine(before[id]!.text)}\n  _now ${afterState[id]} by ${by.isEmpty ? 'this change' : '`$by`'}_');
    }
  }

  // The transitive fallout `dependsOn` exists to surface: these were not
  // replaced, they lost the finding they rested on. They may still be true.
  if (unsupported.isNotEmpty) {
    buf.writeln('\n**Lost their justification**\n');
    for (final id in unsupported) {
      final on = after[id]!.restsOn.join(', ');
      buf.writeln('- `$id` — ${_oneLine(after[id]!.text)}\n  _rests on `$on`, which moved. Still possibly true, but no longer for the recorded reason._');
    }
  }

  final touched = {...retired, ...unsupported};
  final passages = _citationsOf(touched);
  if (passages.isNotEmpty) {
    buf.writeln('\n**Passages standing on it**\n');
    for (final p in passages) {
      buf.writeln('- `${p.$1}:${p.$2}` cites `${p.$3}`');
    }
  }

  // The authored explanation, from the experiments this range introduced.
  final notes = <String, List<String>>{};
  for (final id in born) {
    final beliefs = _changedBeliefs(after[id]!.source);
    if (beliefs.isNotEmpty) notes[after[id]!.source] = beliefs;
  }
  if (notes.isNotEmpty) {
    buf.writeln('\n**What this changed**\n');
    for (final entry in notes.entries) {
      for (final line in entry.value) {
        buf.writeln('> ${line.replaceAll('\n', '\n> ')}\n');
      }
    }
  } else if (born.isNotEmpty) {
    buf.writeln(
      '\n_No `changedBeliefs` recorded for the new claims. Write one: the '
      'affected set above says what moved, not what it means._',
    );
  }

  print(buf.toString());
}

bool _revExists(String rev) =>
    Process.runSync('git', ['rev-parse', '--verify', '--quiet', rev]).exitCode ==
    0;

String _oneLine(String s) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= 150 ? t : '${t.substring(0, 149)}…';
}

Map<String, Claim> _claimsHere() {
  final dir = Directory(_entriesDir);
  if (!dir.existsSync()) return {};
  final out = <String, Claim>{};
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    _collect(f.readAsStringSync(), _expIdOf(f.path), out);
  }
  return out;
}

Map<String, Claim> _claimsAt(String rev) {
  final ls = Process.runSync('git', [
    'ls-tree',
    '-r',
    '--name-only',
    rev,
    _entriesDir,
  ]);
  final out = <String, Claim>{};
  for (final path in const LineSplitter().convert(ls.stdout as String)) {
    if (!path.endsWith('.json')) continue;
    final show = Process.runSync('git', ['show', '$rev:$path']);
    if (show.exitCode != 0) continue;
    _collect(show.stdout as String, _expIdOf(path), out);
  }
  return out;
}

String _expIdOf(String path) =>
    path.split('/').last.replaceAll('.json', '');

void _collect(String source, String expId, Map<String, Claim> into) {
  final note = json.decode(source);
  if (note is! Map) return;
  for (final c in (note['claims'] as List? ?? const [])) {
    if (c is! Map || c['id'] is! String) continue;
    into[c['id'] as String] = (
      id: c['id'] as String,
      source: expId,
      text: (c['text'] ?? '').toString(),
      restsOn: [
        for (final e in (c['edges'] as List? ?? const []))
          if (e is Map && e['type'] == 'dependsOn' && e['target'] is String)
            e['target'] as String,
      ],
    );
  }
}

/// Same derivation the graph builder and the pin resolver run: retired first,
/// then the transitive loss of justification.
Map<String, String> _states(Map<String, Claim> claims) {
  final dead = <String, String>{};
  for (final entry in claims.entries) {
    final raw = entry.value;
    for (final target in _edgesOf(raw)) {
      dead[target.$2] = target.$1 == 'refutes' ? 'refuted' : 'superseded';
    }
  }
  final unsupported = <String>{};
  for (var changed = true; changed;) {
    changed = false;
    for (final c in claims.values) {
      if (dead.containsKey(c.id) || unsupported.contains(c.id)) continue;
      if (c.restsOn.any((t) => dead.containsKey(t) || unsupported.contains(t))) {
        unsupported.add(c.id);
        changed = true;
      }
    }
  }
  return {
    for (final c in claims.values)
      c.id: dead[c.id] ?? (unsupported.contains(c.id) ? 'unsupported' : 'live'),
  };
}

/// Raw (type, target) pairs for the retiring edge types, re-read from disk
/// because [Claim] only keeps `dependsOn`.
List<(String, String)> _edgesOf(Claim c) {
  final f = File('$_entriesDir/${c.source}.json');
  if (!f.existsSync()) return const [];
  final note = json.decode(f.readAsStringSync());
  if (note is! Map) return const [];
  for (final raw in (note['claims'] as List? ?? const [])) {
    if (raw is! Map || raw['id'] != c.id) continue;
    return [
      for (final e in (raw['edges'] as List? ?? const []))
        if (e is Map &&
            (e['type'] == 'supersedes' || e['type'] == 'refutes') &&
            e['target'] is String)
          (e['type'] as String, e['target'] as String),
    ];
  }
  return const [];
}

List<String> _killersOf(String id, Map<String, Claim> claims) => [
  for (final c in claims.values)
    if (_edgesOf(c).any((e) => e.$2 == id)) c.id,
];

/// Every documented passage citing one of [ids], as (file, line, claim).
List<(String, int, String)> _citationsOf(Set<String> ids) {
  final out = <(String, int, String)>[];
  if (ids.isEmpty) return out;
  for (final glob in _docGlobs) {
    final dir = Directory(glob);
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.md')) continue;
      for (final pin in parsePins(f.path, f.readAsStringSync())) {
        if (pin.namespace == 'claim' && ids.contains(pin.target)) {
          out.add((pin.site.file, pin.site.line, pin.target));
        }
      }
    }
  }
  return out;
}

List<String> _changedBeliefs(String expId) {
  final f = File('$_entriesDir/$expId.json');
  if (!f.existsSync()) return const [];
  final note = json.decode(f.readAsStringSync());
  if (note is! Map) return const [];
  return [
    for (final b in (note['changedBeliefs'] as List? ?? const []))
      if (b is String && b.trim().isNotEmpty) b.trim(),
  ];
}
