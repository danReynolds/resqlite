// ignore_for_file: avoid_print
/// Verifies every knowledge pin in the documentation, reports groundedness,
/// and can re-pin drifted expectations.
///
///   dart run tool/knowledge/verify.dart            check (CI)
///   dart run tool/knowledge/verify.dart --report   + groundedness table
///   dart run tool/knowledge/verify.dart --fix      rewrite drifted pins
///
/// `--fix` is what keeps this maintainable: when a constant or metric
/// legitimately moves, it updates the pins in place and leaves a diff for a
/// human to review — "this number moved 15%, does the sentence still hold?" —
/// instead of asking anyone to hand-edit hashes. It never touches `broken`
/// pins, because those mean the prose is describing something that no longer
/// exists, which is a writing problem rather than a bookkeeping one.
library;

import 'dart:io';

import 'pin.dart';
import 'resolvers.dart';

/// Project wiring. Everything above this line is portable; everything in here
/// is what a different repo would change.
const _docGlobs = ['doc/arch/chapters', 'doc/arch'];
const _claimEntries = 'experiments/signals/entries';
const _history = 'docs/experiments/history.json';
const _testResults = 'build/passing-tests.txt';

Future<void> main(List<String> args) async {
  final fix = args.contains('--fix');
  final report = args.contains('--report') || fix;
  // `unknown` means a resolver could not reach its source of truth. Locally
  // that is routine — the test-results file is a CI artifact — so it warns. In
  // CI it must fail: a checker that cannot check has stopped guarding anything,
  // and a green build would advertise coverage that is not there.
  final strict = args.contains('--strict');
  final root = Directory.current;

  final resolvers = <String, PinResolver>{
    for (final r in [
      ClaimResolver(Directory('${root.path}/$_claimEntries')),
      ClaimResolver(Directory('${root.path}/$_claimEntries'), namespace: 'was'),
      CodeResolver(root),
      TestResolver(root, File('${root.path}/$_testResults')),
      BenchResolver(File('${root.path}/$_history')),
    ])
      r.namespace: r,
  };

  final docs = <File>[];
  for (final g in _docGlobs) {
    final d = Directory('${root.path}/$g');
    if (!d.existsSync()) continue;
    for (final f in d.listSync().whereType<File>()) {
      if (f.path.endsWith('.md')) docs.add(f);
    }
  }

  final results = <PinResult>[];
  final byDoc = <String, List<PinResult>>{};
  for (final doc in docs) {
    final rel = doc.path.replaceFirst('${root.path}/', '');
    final pins = parsePins(rel, doc.readAsStringSync());
    for (final pin in pins) {
      final resolver = resolvers[pin.namespace];
      final result = resolver == null
          ? PinResult(pin, PinStatus.broken, 'unknown namespace')
          : await resolver.resolve(pin);
      results.add(result);
      (byDoc[rel] ??= []).add(result);
    }
  }

  if (fix) {
    await _applyFixes(root, byDoc);
    return;
  }

  var failures = 0;
  for (final r in results) {
    switch (r.status) {
      case PinStatus.broken:
        print(
          '::error file=${r.pin.site.file},line=${r.pin.site.line}::'
          '${r.pin.raw} — ${r.detail}',
        );
        failures++;
      case PinStatus.drifted:
        print(
          '::error file=${r.pin.site.file},line=${r.pin.site.line}::'
          '${r.pin.raw} — ${r.detail}. Re-read this passage, then '
          '`dart run tool/knowledge/verify.dart --fix` to re-pin.',
        );
        failures++;
      case PinStatus.unknown:
        print(
          '::${strict ? 'error' : 'warning'} file=${r.pin.site.file},'
          'line=${r.pin.site.line}::${r.pin.raw} — ${r.detail}'
          '${strict ? '. Its dataset is missing, so this pin is checking '
                    'nothing. Produce the dataset (see tool/knowledge/README.md) '
                    'or drop the pin.' : ''}',
        );
        if (strict) failures++;
      case PinStatus.current:
        break;
    }
  }

  if (report) _printGroundedness(byDoc, resolvers);

  if (failures > 0) {
    print('$failures pin(s) need attention.');
    exitCode = 1;
    return;
  }
  print('All ${results.length} knowledge pins verify.');
}

/// Groundedness: how much of each chapter's argument rests on something
/// checkable, and on how strong a footing.
///
/// This is deliberately not a score to maximize. Prose that explains *why*
/// should stay unpinned; the number matters for spotting chapters that assert
/// load-bearing facts with nothing behind them.
void _printGroundedness(
  Map<String, List<PinResult>> byDoc,
  Map<String, PinResolver> resolvers,
) {
  print('\nGroundedness by chapter');
  print('| chapter | pins | test | bench | code | claim | weakest |');
  print('|---|---:|---:|---:|---:|---:|---|');
  final docs = byDoc.keys.toList()..sort();
  for (final doc in docs) {
    final rs = byDoc[doc]!;
    final counts = <String, int>{};
    for (final r in rs) {
      counts[r.pin.namespace] = (counts[r.pin.namespace] ?? 0) + 1;
    }
    var weakest = 'none';
    var weakestStrength = 1000;
    for (final ns in counts.keys) {
      final s = resolvers[ns]?.strength ?? 0;
      if (s < weakestStrength) {
        weakestStrength = s;
        weakest = ns;
      }
    }
    print(
      '| ${doc.split('/').last} | ${rs.length} '
      '| ${counts['test'] ?? 0} | ${counts['bench'] ?? 0} '
      '| ${counts['code'] ?? 0} | ${counts['claim'] ?? 0} | $weakest |',
    );
  }
  print(
    '\ntest = a passing assertion proves it · bench = the number is current · '
    'code = the mechanism is unchanged · claim = the belief stands',
  );

  // Every `bench:` number is only as current as the newest clean run behind it,
  // and that run can be arbitrarily old while the pins all pass. Say which run
  // they came from and how old it is, so "verified" is never mistaken for
  // "recently measured".
  final bench = resolvers['bench'];
  if (bench is BenchResolver && bench.runDate != null) {
    final age = bench.runAgeDays;
    print(
      '\nbenchmark numbers come from the run of ${bench.runDate}'
      '${age == null ? '' : ' ($age days ago)'}'
      '${age != null && age > 30 ? ' — stale; nothing since has been measured' : ''}',
    );
  }

  // A `test:` pin without a body hash binds a label, not an assertion: the test
  // could be rewritten to assert something else and still resolve. Since `test`
  // is the highest-strength namespace, leaving that unsaid would overstate the
  // corpus — so name the count rather than quietly averaging it in.
  final unbound = byDoc.values
      .expand((rs) => rs)
      .where((r) => r.pin.namespace == 'test' && r.pin.expected == null)
      .toList();
  if (unbound.isNotEmpty) {
    print(
      '\n${unbound.length} test pin(s) bind a name but not a body, so a '
      'rewritten assertion would still pass. Add a body hash to close that:',
    );
    for (final r in unbound) {
      print('  ${r.pin.site.file}:${r.pin.site.line}  ${r.pin.raw}');
    }
  }
}

Future<void> _applyFixes(
  Directory root,
  Map<String, List<PinResult>> byDoc,
) async {
  var fixed = 0;
  var skipped = 0;
  for (final entry in byDoc.entries) {
    final drifted = entry.value
        .where((r) => r.status == PinStatus.drifted)
        .toList();
    if (drifted.isEmpty) continue;
    final file = File('${root.path}/${entry.key}');
    var content = file.readAsStringSync();
    for (final r in drifted) {
      final actual = r.actual;
      if (actual == null) {
        skipped++;
        continue;
      }
      final old = r.pin.raw;
      // Replace only the expectation, preserving the target and any tolerance.
      final updated = old.contains('~')
          ? old.replaceFirst(RegExp(r'~\s*[^+]+\s*\+-'), '~ $actual +-')
          : old.contains('@')
          ? '${old.substring(0, old.lastIndexOf('@'))}@$actual]]'
          : '${old.substring(0, old.indexOf('='))}=$actual]]';
      content = content.replaceFirst(old, updated);
      print('  ${entry.key}:${r.pin.site.line}  $old -> $updated');
      fixed++;
    }
    file.writeAsStringSync(content);
  }
  print(
    '\nRe-pinned $fixed expectation(s)'
    '${skipped > 0 ? ', skipped $skipped with no current value' : ''}. '
    'Review the diff: a moved number may mean the surrounding prose is now '
    'wrong, which no tool can tell you.',
  );
}
