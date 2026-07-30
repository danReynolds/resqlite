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
const _indexDir = 'experiments/index';
const _docGlobs = ['doc/arch/chapters', 'doc/arch'];

/// Base for blob links, e.g. `https://github.com/owner/repo/blob/<sha>`.
///
/// A bare `246.1` tells a reader nothing and cannot be clicked. Every id and
/// every passage here is rendered as a link to the file at the reviewed commit,
/// so the report is navigable from a PR comment rather than being a list of
/// numbers to go look up by hand.
///
/// CI passes the PR's head sha via `IMPACT_BLOB_BASE`, because `HEAD` there is
/// the ephemeral merge commit and would 404. Falls back to plain text when
/// there is no GitHub remote to point at.
final String? _blobBase = () {
  final override = Platform.environment['IMPACT_BLOB_BASE'];
  if (override != null && override.isNotEmpty) return override;
  final remote = Process.runSync('git', ['remote', 'get-url', 'origin']);
  if (remote.exitCode != 0) return null;
  final m = RegExp(
    r'github\.com[:/]([^/]+)/([^/\s.]+)',
  ).firstMatch((remote.stdout as String).trim());
  if (m == null) return null;
  final sha = Process.runSync('git', ['rev-parse', 'HEAD']);
  if (sha.exitCode != 0) return null;
  return 'https://github.com/${m.group(1)}/${m.group(2)}/blob/'
      '${(sha.stdout as String).trim()}';
}();

String _link(String label, String path, {int? line}) {
  final base = _blobBase;
  if (base == null) return line == null ? '`$path`' : '`$path:$line`';
  return '[$label]($base/$path${line == null ? '' : '#L$line'})';
}

/// `file` and `title` from an experiment's index row, so a claim id can carry
/// the name of the experiment that established it.
({String file, String title})? _experiment(String id) {
  final f = File('$_indexDir/$id.json');
  if (!f.existsSync()) return null;
  final decoded = json.decode(f.readAsStringSync());
  final row = decoded is List
      ? decoded.whereType<Map>().firstOrNull
      : decoded is Map
      ? decoded
      : null;
  if (row == null || row['file'] is! String) return null;
  return (file: row['file'] as String, title: (row['title'] ?? '').toString());
}

/// `246.1 · Slot-count sacrifice trigger`, linked to its writeup. Used where a
/// claim is the subject of a bullet and the reader has met it for the first
/// time.
String _claimRef(String claimId, String expId) {
  final exp = _experiment(expId);
  if (exp == null) return '`$claimId`';
  final title = exp.title.isEmpty ? 'exp $expId' : exp.title;
  return '${_claimLink(claimId, expId)} · $title';
}

/// Just the linked id, for cross-references — those claims carry their titles
/// where they appear as bullets, and repeating them inline buries the sentence.
String _claimLink(String claimId, String expId) {
  final exp = _experiment(expId);
  if (exp == null) return '`$claimId`';
  return _link('`$claimId`', 'experiments/${exp.file}');
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// A claim as it existed in one revision.
///
/// [retires] and [restsOn] are both captured when the entry is parsed, from
/// that revision's bytes. Re-reading either from disk would mix the working
/// tree into the "before" snapshot, and the two states would then agree by
/// construction — silently hiding exactly the retirement this tool exists to
/// report.
typedef Claim = ({
  String id,
  String source,
  String text,
  List<String> restsOn,
  List<({String type, String target})> retires,
});

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
  final beforeState = deriveStates(before);
  final afterState = deriveStates(after);

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
      buf.writeln('- ${_claimRef(id, after[id]!.source)}');
      buf.writeln('  ${_oneLine(after[id]!.text)}');
    }
  }

  if (retired.isNotEmpty) {
    buf.writeln('\n**Retired**\n');
    for (final id in retired) {
      final killers = _killersOf(id, after);
      final by = killers
          .map((k) => _claimLink(k, after[k]?.source ?? k.split('.').first))
          .join(', ');
      buf.writeln('- ${_claimRef(id, before[id]!.source)}');
      buf.writeln('  ${_oneLine(before[id]!.text)}');
      buf.writeln(
        '  _now ${afterState[id]}${by.isEmpty ? ' by this change' : ' by $by'}_',
      );
    }
  }

  // The transitive fallout `dependsOn` exists to surface: these were not
  // replaced, they lost the finding they rested on. They may still be true.
  if (unsupported.isNotEmpty) {
    buf.writeln('\n**Lost their justification**\n');
    for (final id in unsupported) {
      final on = after[id]!.restsOn
          .map((t) => _claimLink(t, after[t]?.source ?? t.split('.').first))
          .join(', ');
      buf.writeln('- ${_claimRef(id, after[id]!.source)}');
      buf.writeln('  ${_oneLine(after[id]!.text)}');
      buf.writeln(
        '  _rests on $on, which moved. Still possibly true, but no longer for '
        'the recorded reason._',
      );
    }
  }

  final touched = {...retired, ...unsupported};
  final passages = _citationsOf(touched);
  if (passages.isNotEmpty) {
    buf.writeln('\n**Passages standing on it**\n');
    for (final p in passages) {
      buf.writeln(
        '- ${_link('${p.$1}:${p.$2}', p.$1, line: p.$2)} — cites `${p.$3}`',
      );
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
    Process.runSync('git', [
      'rev-parse',
      '--verify',
      '--quiet',
      rev,
    ]).exitCode ==
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
    collectClaims(f.readAsStringSync(), _expIdOf(f.path), out);
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
    collectClaims(show.stdout as String, _expIdOf(path), out);
  }
  return out;
}

String _expIdOf(String path) => path.split('/').last.replaceAll('.json', '');

void collectClaims(String source, String expId, Map<String, Claim> into) {
  final note = json.decode(source);
  if (note is! Map) return;
  for (final c in (note['claims'] as List? ?? const [])) {
    if (c is! Map || c['id'] is! String) continue;
    final edges = (c['edges'] as List? ?? const []).whereType<Map>().where(
      (e) => e['target'] is String,
    );
    into[c['id'] as String] = (
      id: c['id'] as String,
      source: expId,
      text: (c['text'] ?? '').toString(),
      restsOn: [
        for (final e in edges)
          if (e['type'] == 'dependsOn') e['target'] as String,
      ],
      retires: [
        for (final e in edges)
          if (e['type'] == 'supersedes' || e['type'] == 'refutes')
            (type: e['type'] as String, target: e['target'] as String),
      ],
    );
  }
}

/// Same derivation the graph builder and the pin resolver run: retired first,
/// then the transitive loss of justification.
Map<String, String> deriveStates(Map<String, Claim> claims) {
  final dead = <String, String>{};
  for (final c in claims.values) {
    for (final e in c.retires) {
      dead[e.target] = e.type == 'refutes' ? 'refuted' : 'superseded';
    }
  }
  final unsupported = <String>{};
  for (var changed = true; changed;) {
    changed = false;
    for (final c in claims.values) {
      if (dead.containsKey(c.id) || unsupported.contains(c.id)) continue;
      if (c.restsOn.any(
        (t) => dead.containsKey(t) || unsupported.contains(t),
      )) {
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

List<String> _killersOf(String id, Map<String, Claim> claims) => [
  for (final c in claims.values)
    if (c.retires.any((e) => e.target == id)) c.id,
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
