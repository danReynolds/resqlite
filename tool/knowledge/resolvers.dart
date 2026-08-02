/// resqlite's resolvers — the project-specific half of the pin system.
///
/// Each binds one namespace to whatever this repo treats as ground truth.
/// Porting the system to another codebase means rewriting this file (and
/// `knowledge.yaml`) and nothing else.
library;

import 'dart:convert';
import 'dart:io';

import 'pin.dart';

/// `[[claim:246.1]]` — the belief is recorded and not superseded.
///
/// Weakest of the four: it proves the project still *believes* something, not
/// that the something is true. A superseded claim is `broken`, because prose
/// resting on a retracted belief is wrong until rewritten.
class ClaimResolver implements PinResolver {
  ClaimResolver(this.entriesDir, {this.namespace = 'claim'});

  final Directory entriesDir;

  @override
  final String namespace;
  Map<String, ({String text, String? state, List<String> by})>? _claims;

  @override
  String get proves => namespace == 'was'
      ? 'the belief is recorded and has since been superseded'
      : 'the belief is recorded and not superseded';

  @override
  int get strength => 40;

  void _load() {
    if (_claims != null) return;
    final byId = <String, ({String text, String? state, List<String> by})>{};
    final supersededBy = <String, List<String>>{};
    final restsOn = <String, List<String>>{};
    if (entriesDir.existsSync()) {
      for (final f in entriesDir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        final note = json.decode(f.readAsStringSync());
        if (note is! Map) continue;
        for (final c in (note['claims'] as List? ?? const [])) {
          if (c is! Map || c['id'] is! String) continue;
          byId[c['id'] as String] = (
            text: (c['text'] ?? '').toString(),
            state: null,
            by: const [],
          );
          for (final e in (c['edges'] as List? ?? const [])) {
            if (e is! Map || e['target'] is! String) continue;
            if (e['type'] == 'supersedes' || e['type'] == 'refutes') {
              (supersededBy[e['target'] as String] ??= []).add(
                c['id'] as String,
              );
            } else if (e['type'] == 'dependsOn') {
              (restsOn[c['id'] as String] ??= []).add(e['target'] as String);
            }
          }
        }
      }
    }

    // Same fixpoint the graph builder runs: a claim whose foundation died is
    // unsupported, and so is anything resting on it in turn.
    final unsupportedBy = <String, List<String>>{};
    for (var changed = true; changed;) {
      changed = false;
      for (final entry in restsOn.entries) {
        if (supersededBy.containsKey(entry.key) ||
            unsupportedBy.containsKey(entry.key)) {
          continue;
        }
        final lost = entry.value
            .where(
              (t) =>
                  supersededBy.containsKey(t) || unsupportedBy.containsKey(t),
            )
            .toList();
        if (lost.isNotEmpty) {
          unsupportedBy[entry.key] = lost;
          changed = true;
        }
      }
    }

    _claims = {
      for (final e in byId.entries)
        e.key: (
          text: e.value.text,
          state: supersededBy.containsKey(e.key)
              ? 'superseded'
              : unsupportedBy.containsKey(e.key)
              ? 'unsupported'
              : 'live',
          by: supersededBy[e.key] ?? unsupportedBy[e.key] ?? const [],
        ),
    };
  }

  @override
  Future<PinResult> resolve(Pin pin) async {
    _load();
    final claim = _claims![pin.target];
    if (claim == null) {
      return PinResult(pin, PinStatus.broken, 'no claim ${pin.target} exists');
    }

    // `[[was:236.2]]` marks a deliberately historical citation — prose that
    // narrates a belief we have since abandoned ("the original trigger did
    // X"). That is some of the most valuable writing in the corpus, so it must
    // not read as rot. The two forms assert opposite things about the same
    // claim, and both are checkable: a live citation of a superseded claim is
    // an error, and a historical citation of a still-live claim is one too,
    // because the prose is calling something former that never stopped being
    // true.
    final historical = pin.namespace == 'was';
    if (claim.state == 'superseded' && !historical) {
      return PinResult(
        pin,
        PinStatus.broken,
        'claim ${pin.target} is superseded by ${claim.by.join(', ')} — if this '
        'passage is narrating history, cite it as [[was:${pin.target}]]',
      );
    }
    if (claim.state != 'superseded' && historical) {
      return PinResult(
        pin,
        PinStatus.broken,
        'claim ${pin.target} is still live, so [[was:]] misdescribes it',
      );
    }

    // The belief was not replaced — the finding it rested on was. It may well
    // still hold, but not for the reason this passage gives, so the passage
    // needs a human. Failing rather than warning is deliberate: supersession is
    // rare, and a warning nobody is forced to read is how a documented
    // rationale quietly outlives its evidence.
    if (claim.state == 'unsupported') {
      return PinResult(
        pin,
        PinStatus.broken,
        'claim ${pin.target} rests on ${claim.by.join(', ')}, which has since '
        'been superseded — it may still be true, but no longer for the recorded '
        'reason. Re-justify it, rewrite this passage, or drop the dependsOn '
        'edge if it was never load-bearing',
      );
    }
    if (historical) {
      return PinResult(
        pin,
        PinStatus.current,
        'historical (superseded by ${claim.by.join(', ')})',
      );
    }
    // A pinned hash additionally detects the claim being reworded in place —
    // a revision that leaves no supersession edge behind.
    if (pin.expected != null) {
      final actual = contentHash(claim.text);
      if (actual != pin.expected) {
        return PinResult(
          pin,
          PinStatus.drifted,
          'claim ${pin.target} was reworded since this passage was written',
          actual: actual,
        );
      }
    }
    return PinResult(pin, PinStatus.current, 'live');
  }
}

/// `[[code:sacrificeSlotThreshold=32768]]` — a named constant still holds the
/// value the prose quotes.
///
/// `[[code:lib/src/x.dart#symbolName@a3f2]]` — a symbol's body, comments
/// stripped, still hashes to what it did when the passage was written.
///
/// The value form has no false positives, so it fails the build. The body form
/// is heuristic (it only sees textual change, not semantic change) and is
/// reported as drift for a human to judge.
class CodeResolver implements PinResolver {
  CodeResolver(this.root);

  final Directory root;

  @override
  String get namespace => 'code';

  @override
  String get proves => 'the mechanism in the source is unchanged';

  @override
  int get strength => 70;

  @override
  Future<PinResult> resolve(Pin pin) async {
    if (pin.target.contains('#')) return _resolveSymbol(pin);
    return _resolveConstant(pin);
  }

  /// Finds `const|final|var <name> = <value>;` anywhere under the search roots.
  Future<PinResult> _resolveConstant(Pin pin) async {
    final name = pin.target;
    final pattern = RegExp(
      r'(?:const|final|var)\s+(?:[\w<>?, ]+\s+)?' +
          RegExp.escape(name) +
          r'\s*=\s*([^;]+);',
    );
    for (final file in _dartFiles()) {
      final m = pattern.firstMatch(file.readAsStringSync());
      if (m == null) continue;
      final actual = _evalNumeric(m.group(1)!.trim());
      if (pin.expected == null) {
        return PinResult(pin, PinStatus.current, 'exists (= $actual)');
      }
      if (actual != pin.expected) {
        return PinResult(
          pin,
          PinStatus.drifted,
          '$name is now $actual, prose pins ${pin.expected}',
          actual: actual,
        );
      }
      return PinResult(pin, PinStatus.current, '$name == $actual');
    }
    return PinResult(pin, PinStatus.broken, 'no declaration of $name found');
  }

  /// `path/to/file.dart#symbolName` — hashes the symbol's brace-balanced body.
  Future<PinResult> _resolveSymbol(Pin pin) async {
    final parts = pin.target.split('#');
    final file = File('${root.path}/${parts[0]}');
    if (!file.existsSync()) {
      return PinResult(pin, PinStatus.broken, 'no file ${parts[0]}');
    }
    final source = file.readAsStringSync();
    final body = _extractBody(source, parts[1]);
    if (body == null) {
      return PinResult(
        pin,
        PinStatus.broken,
        'no symbol ${parts[1]} in ${parts[0]}',
      );
    }
    final actual = contentHash(normalizeSource(body));
    if (pin.expected == null) {
      return PinResult(pin, PinStatus.current, 'exists (@$actual)');
    }
    if (actual != pin.expected) {
      return PinResult(
        pin,
        PinStatus.drifted,
        '${parts[1]} changed (@$actual, prose pins @${pin.expected})',
        actual: actual,
      );
    }
    return PinResult(pin, PinStatus.current, 'unchanged');
  }

  /// Brace-matched body starting at the symbol's declaration.
  String? _extractBody(String source, String symbol) => braceBlockAfter(
    source,
    RegExp(
      r'(?:^|\s)' + RegExp.escape(symbol) + r'\s*(?:<[^>]*>)?\s*\(',
      multiLine: true,
    ),
  );

  /// Normalizes simple arithmetic so prose can pin the meaningful number
  /// (`32768`) rather than the source spelling (`32 * 1024`).
  String _evalNumeric(String expr) {
    final cleaned = expr.replaceAll(RegExp(r'//.*'), '').trim();
    final mul = RegExp(r'^(\d+)\s*\*\s*(\d+)$').firstMatch(cleaned);
    if (mul != null) {
      return (int.parse(mul.group(1)!) * int.parse(mul.group(2)!)).toString();
    }
    final env = RegExp(
      r'defaultValue:\s*(\d+)\s*\*\s*(\d+)',
    ).firstMatch(cleaned);
    if (env != null) {
      return (int.parse(env.group(1)!) * int.parse(env.group(2)!)).toString();
    }
    final envPlain = RegExp(r'defaultValue:\s*(\d+)').firstMatch(cleaned);
    if (envPlain != null) return envPlain.group(1)!;
    return cleaned;
  }

  Iterable<File> _dartFiles() sync* {
    for (final dir in ['lib', 'tool']) {
      final d = Directory('${root.path}/$dir');
      if (!d.existsSync()) continue;
      for (final f in d.listSync(recursive: true).whereType<File>()) {
        if (f.path.endsWith('.dart')) yield f;
      }
    }
  }
}

/// `[[test:test/stream_test.dart#always emits its initial result]]` — the named
/// test exists and is in the passing set.
///
/// `[[test:test/stream_test.dart#always emits its initial result@a3f2]]` — and
/// its body still asserts what it asserted when the passage was written.
///
/// The strongest binding available: a green pinned test does not merely guard a
/// statement, it *proves* it on every CI run. Unchanged code can still be
/// wrong; a passing assertion cannot be, for the property it asserts.
///
/// That last clause is the catch, and it is why the hash form exists. A test
/// name is a label, not evidence. Keep the name and gut the body to
/// `expect(1, 1)` and a name-only pin still reports `current` — at the highest
/// strength in the system, for a guarantee nothing now guards. Pinning the body
/// closes that: a rewritten assertion reads as `drifted`, which asks a human
/// whether the documented guarantee survived. A hash cannot tell a strengthened
/// assertion from a gutted one, so drift here is a prompt to re-read, never a
/// verdict — the same contract as `code:` body hashes.
///
/// Existence and shape are checked statically. Whether it *passed* is read from
/// a results file produced by the test run, so this resolver never shells out.
class TestResolver implements PinResolver {
  TestResolver(this.root, this.resultsFile);

  final Directory root;

  /// Newline-delimited names of tests that passed in the last run, written by
  /// CI. Absent locally, which yields `unknown` rather than a false pass.
  final File resultsFile;

  Set<String>? _passed;

  @override
  String get namespace => 'test';

  @override
  String get proves => 'a passing assertion demonstrates the statement';

  @override
  int get strength => 100;

  @override
  Future<PinResult> resolve(Pin pin) async {
    final parts = pin.target.split('#');
    final file = File('${root.path}/${parts[0]}');
    if (!file.existsSync()) {
      return PinResult(pin, PinStatus.broken, 'no test file ${parts[0]}');
    }
    final name = parts.length > 1 ? parts[1].trim() : '';
    final source = file.readAsStringSync();
    if (name.isNotEmpty && !source.contains(name)) {
      return PinResult(
        pin,
        PinStatus.broken,
        'no test named "$name" in ${parts[0]} — a documented guarantee lost '
        'its guard',
      );
    }

    // Body check before the pass check, so a rewritten assertion is caught on a
    // developer's machine too — the results file is a CI artifact, and waiting
    // for CI to notice a gutted test is waiting too long.
    if (pin.expected != null) {
      // Anchor on a *quoted string containing* the name, matching the substring
      // semantics of the existence check above — pins routinely cite a readable
      // fragment of a longer test name. Requiring the quotes keeps a passing
      // mention of the same words in a comment from anchoring the walk.
      final body = braceBlockAfter(
        source,
        RegExp('[\'"][^\'"]*${RegExp.escape(name)}[^\'"]*[\'"]'),
      );
      if (body == null) {
        return PinResult(
          pin,
          PinStatus.broken,
          'found the name "$name" but not a body to hash — is it still a test?',
        );
      }
      final actual = contentHash(normalizeSource(body));
      if (actual != pin.expected) {
        return PinResult(
          pin,
          PinStatus.drifted,
          'the body of "$name" changed (@$actual, prose pins '
          '@${pin.expected}) — confirm it still asserts the documented '
          'guarantee, then re-pin',
          actual: actual,
        );
      }
    }

    if (_passed == null && resultsFile.existsSync()) {
      _passed = resultsFile.readAsLinesSync().map((l) => l.trim()).toSet();
    }
    if (_passed == null) {
      return PinResult(
        pin,
        PinStatus.unknown,
        'test exists; pass/fail unknown (no results file)',
      );
    }
    final green = _passed!.any((t) => t.contains(name));
    return green
        ? PinResult(pin, PinStatus.current, 'passing')
        : PinResult(pin, PinStatus.broken, 'test "$name" is not passing');
  }
}

/// `[[bench:Select -> JSON Bytes / 1000 rows / resqlite selectBytes() ~ 0.32 +-15%]]`
/// — a tracked metric still measures near the number the prose quotes.
///
/// Reads the newest clean run in the published history. Tolerance is required
/// for these: benchmark noise would make exact matching fire constantly.
class BenchResolver implements PinResolver {
  BenchResolver(this.historyFile);

  final File historyFile;
  Map<String, double>? _latest;
  String? _runLabel;

  /// Date of the run these numbers come from, and how old it is.
  ///
  /// A `bench:` pin reads the newest clean run, so it keeps passing happily
  /// while nothing is measured at all — the number stops being checked without
  /// ever failing. Surfacing the age is what turns "quietly unverified" back
  /// into something a reader can see.
  String? runDate;
  int? runAgeDays;

  @override
  String get namespace => 'bench';

  @override
  String get proves => 'the measured number is still current';

  @override
  int get strength => 90;

  void _load() {
    if (_latest != null || !historyFile.existsSync()) return;
    final data = json.decode(historyFile.readAsStringSync());
    final runs = (data['runs'] as List?) ?? const [];
    for (final run in runs.reversed) {
      if (run is! Map) continue;
      // Skip runs the charts already treat as untrustworthy. `gitDirty` lives
      // under `environment`, not at the top level — reading it from the wrong
      // place silently accepted every dirty run, which is the opposite of what
      // this filter is for.
      final env = run['environment'];
      final dirty = env is Map && env['gitDirty'] == true;
      if (dirty || run['noisy'] == true) continue;
      final metrics = run['metrics'];
      if (metrics is Map && metrics.isNotEmpty) {
        _latest = {
          for (final e in metrics.entries)
            e.key.toString(): (e.value as num).toDouble(),
        };
        _runLabel = '${run['date']} ${run['label'] ?? ''}'.trim();
        runDate = run['date']?.toString();
        final parsed = DateTime.tryParse(runDate ?? '');
        if (parsed != null) {
          runAgeDays = DateTime.now().toUtc().difference(parsed).inDays;
        }
        return;
      }
    }
  }

  @override
  Future<PinResult> resolve(Pin pin) async {
    _load();
    if (_latest == null) {
      return PinResult(
        pin,
        PinStatus.unknown,
        'no benchmark history available',
      );
    }
    final actual = _latest![pin.target];
    if (actual == null) {
      return PinResult(
        pin,
        PinStatus.broken,
        'metric "${pin.target}" is not in the tracked suite',
      );
    }
    if (pin.expected == null) {
      return PinResult(pin, PinStatus.current, 'tracked (= $actual)');
    }
    final expected = double.tryParse(pin.expected!);
    if (expected == null) {
      return PinResult(pin, PinStatus.broken, 'unparseable value in pin');
    }
    final tol = pin.tolerance ?? 0.15;
    final delta = (actual - expected).abs() / (expected == 0 ? 1 : expected);
    if (delta > tol) {
      return PinResult(
        pin,
        PinStatus.drifted,
        'now $actual, prose pins $expected '
        '(${(delta * 100).toStringAsFixed(0)}% off, tolerance '
        '${(tol * 100).toStringAsFixed(0)}%) — measured $_runLabel',
        actual: actual.toString(),
      );
    }
    return PinResult(pin, PinStatus.current, 'within tolerance ($actual)');
  }
}
