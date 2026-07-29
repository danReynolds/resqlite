/// Tests for the knowledge-pin system — the checker that keeps documentation
/// from drifting away from the code, benchmarks, tests and claims it describes.
///
/// The thing under test is a *detector*, so the cases that matter are the
/// negative ones. A pin system that reports `current` when reality has moved is
/// worse than having no pins at all, because a green check reads as coverage.
/// Every resolver here is therefore exercised in both directions: it must pass
/// when the fixture agrees with the pin, and it must fail when it does not.
///
/// The `unknown` cases are the reason this file exists. When a resolver cannot
/// reach its source of truth it must say so rather than pass, and CI must treat
/// that as a failure — otherwise a broken test run silently disables the
/// strongest evidence class in the system while the build stays green.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/knowledge/pin.dart';
import '../tool/knowledge/resolvers.dart';

/// Parses [text] as a document and returns its single pin.
Pin onePin(String text) {
  final pins = parsePins('doc.md', text);
  expect(pins, hasLength(1), reason: 'fixture should contain exactly one pin');
  return pins.first;
}

late Directory tmp;

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('pins-test-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('pin grammar', () {
    test('a bare id is sugar for the claim namespace', () {
      final pin = onePin('slots, not bytes [[246.1]].');
      expect(pin.namespace, 'claim');
      expect(pin.target, '246.1');
      expect(pin.expected, isNull);
    });

    test('an explicit namespace and value are split apart', () {
      final pin = onePin('the trigger [[code:sacrificeSlotThreshold=32768]].');
      expect(pin.namespace, 'code');
      expect(pin.target, 'sacrificeSlotThreshold');
      expect(pin.expected, '32768');
    });

    test('a hash expectation is taken from the last @', () {
      final pin = onePin('[[code:lib/src/a@b.dart#thing@a3f2]]');
      expect(pin.target, 'lib/src/a@b.dart#thing');
      expect(pin.expected, 'a3f2');
    });

    test('tolerance is parsed and converted to a fraction', () {
      final pin = onePin('[[bench:Large read ~ 0.323 +-20%]]');
      expect(pin.target, 'Large read');
      expect(pin.expected, '0.323');
      expect(pin.tolerance, closeTo(0.20, 1e-9));
    });

    // Regression: metric names in this repo contain `~` ("Large payload
    // (~650KB)"). A non-greedy target match split on the *first* tilde and
    // silently mangled both the metric name and the expected value.
    test('a target containing ~ splits on the last tilde', () {
      final pin = onePin('[[bench:Select / Large payload (~650KB) ~ 0.32 +-15%]]');
      expect(pin.target, 'Select / Large payload (~650KB)');
      expect(pin.expected, '0.32');
      expect(pin.tolerance, closeTo(0.15, 1e-9));
    });

    test('the site records the line the pin was found on', () {
      final pins = parsePins('doc.md', 'one\ntwo [[246.1]]\nthree');
      expect(pins.single.site.line, 2);
      expect(pins.single.site.file, 'doc.md');
      expect(pins.single.raw, '[[246.1]]');
    });

    test('prose with no pins yields none', () {
      expect(parsePins('doc.md', 'nothing to see; a[[b'), isEmpty);
    });
  });

  group('contentHash', () {
    test('is stable for equal input and differs for changed input', () {
      expect(contentHash('alpha'), contentHash('alpha'));
      expect(contentHash('alpha'), isNot(contentHash('alpha ')));
      expect(contentHash('alpha').length, 4);
    });

    // Regression: the digest was rendered from a signed 64-bit int, so about
    // half of all inputs produced a leading '-' — reading as damage inline and
    // spending one of four characters on a sign.
    test('is always four base36 characters with no sign', () {
      for (var i = 0; i < 400; i++) {
        final h = contentHash('sample input number $i');
        expect(h, matches(RegExp(r'^[0-9a-z]{4}$')), reason: 'input $i -> $h');
      }
    });
  });

  group('normalizeSource', () {
    test('ignores comments and reflowing but not semantic edits', () {
      const a = 'if (x > 3) {\n  // explain\n  return 1;\n}';
      const b = 'if (x > 3) {\n\n    return 1;\n}   // moved';
      const c = 'if (x > 4) {\n  return 1;\n}';
      expect(normalizeSource(a), normalizeSource(b));
      expect(normalizeSource(a), isNot(normalizeSource(c)));
    });
  });

  group('ClaimResolver', () {
    /// Writes one signal entry holding [claims].
    Directory entries(List<Map<String, Object?>> claims) {
      final dir = Directory('${tmp.path}/entries')..createSync();
      File('${dir.path}/001.json').writeAsStringSync(json.encode({
        'claims': claims,
      }));
      return dir;
    }

    Future<PinResult> check(Directory dir, String text, {String ns = 'claim'}) =>
        ClaimResolver(dir, namespace: ns).resolve(onePin(text));

    test('a live claim is current', () async {
      final dir = entries([
        {'id': '246.1', 'text': 'slots, not bytes'},
      ]);
      expect((await check(dir, '[[246.1]]')).status, PinStatus.current);
    });

    test('citing a superseded claim is broken, and says how to fix it', () async {
      final dir = entries([
        {'id': '236.2', 'text': 'bytes'},
        {
          'id': '246.1',
          'text': 'slots',
          'edges': [
            {'type': 'supersedes', 'target': '236.2'},
          ],
        },
      ]);
      final r = await check(dir, '[[236.2]]');
      expect(r.status, PinStatus.broken);
      expect(r.detail, contains('superseded by 246.1'));
      expect(r.detail, contains('[[was:236.2]]'));
    });

    test('a was: citation of a superseded claim is current', () async {
      final dir = entries([
        {'id': '236.2', 'text': 'bytes'},
        {
          'id': '246.1',
          'text': 'slots',
          'edges': [
            {'type': 'refutes', 'target': '236.2'},
          ],
        },
      ]);
      final r = await check(dir, '[[was:236.2]]', ns: 'was');
      expect(r.status, PinStatus.current);
    });

    // The inverse must fail too, or `was:` becomes a way to silence the linter.
    test('a was: citation of a still-live claim is broken', () async {
      final dir = entries([
        {'id': '246.1', 'text': 'slots'},
      ]);
      final r = await check(dir, '[[was:246.1]]', ns: 'was');
      expect(r.status, PinStatus.broken);
      expect(r.detail, contains('still live'));
    });

    test('an unknown claim id is broken', () async {
      final r = await check(entries([]), '[[999.9]]');
      expect(r.status, PinStatus.broken);
    });

    test('a reworded claim drifts when the citation pins its hash', () async {
      final dir = entries([
        {'id': '246.1', 'text': 'reworded since the passage was written'},
      ]);
      final r = await check(dir, '[[claim:246.1@zzzz]]');
      expect(r.status, PinStatus.drifted);
      expect(r.actual, isNotNull);
    });
  });

  group('CodeResolver', () {
    Directory repoWith(String dartSource) {
      Directory('${tmp.path}/lib/src').createSync(recursive: true);
      File('${tmp.path}/lib/src/thing.dart').writeAsStringSync(dartSource);
      return tmp;
    }

    Future<PinResult> check(Directory root, String text) =>
        CodeResolver(root).resolve(onePin(text));

    test('a constant matching the pinned value is current', () async {
      final root = repoWith('const threshold = 32768;');
      final r = await check(root, '[[code:threshold=32768]]');
      expect(r.status, PinStatus.current);
    });

    test('arithmetic is evaluated so prose can pin the meaningful number',
        () async {
      final root = repoWith('const threshold = 32 * 1024;');
      expect((await check(root, '[[code:threshold=32768]]')).status,
          PinStatus.current);
    });

    test('int.fromEnvironment defaults are read through', () async {
      final root = repoWith(
        "const threshold = int.fromEnvironment('X', defaultValue: 32 * 1024);",
      );
      expect((await check(root, '[[code:threshold=32768]]')).status,
          PinStatus.current);
    });

    test('a changed constant drifts and reports the new value', () async {
      final root = repoWith('const threshold = 65536;');
      final r = await check(root, '[[code:threshold=32768]]');
      expect(r.status, PinStatus.drifted);
      expect(r.actual, '65536');
      expect(r.detail, contains('65536'));
      expect(r.detail, contains('32768'));
    });

    test('a constant that no longer exists is broken', () async {
      final root = repoWith('const other = 1;');
      expect((await check(root, '[[code:threshold=32768]]')).status,
          PinStatus.broken);
    });

    test('an unchanged symbol body is current', () async {
      final root = repoWith('int f(int a) {\n  return a + 1;\n}');
      final probe = await check(root, '[[code:lib/src/thing.dart#f]]');
      final hash = RegExp(r'@(\w{4})').firstMatch(probe.detail)!.group(1);
      expect((await check(root, '[[code:lib/src/thing.dart#f@$hash]]')).status,
          PinStatus.current);
    });

    test('an edited symbol body drifts', () async {
      final root = repoWith('int f(int a) {\n  return a + 2;\n}');
      final r = await check(root, '[[code:lib/src/thing.dart#f@0000]]');
      expect(r.status, PinStatus.drifted);
    });

    test('comment-only edits to a symbol do not drift', () async {
      var root = repoWith('int f(int a) {\n  return a + 1;\n}');
      final probe = await check(root, '[[code:lib/src/thing.dart#f]]');
      final hash = RegExp(r'@(\w{4})').firstMatch(probe.detail)!.group(1);
      root = repoWith('int f(int a) {\n  // a new remark\n  return a + 1;\n}');
      expect((await check(root, '[[code:lib/src/thing.dart#f@$hash]]')).status,
          PinStatus.current);
    });

    test('a missing file or symbol is broken', () async {
      final root = repoWith('int f() {\n  return 0;\n}');
      expect((await check(root, '[[code:lib/src/gone.dart#f@0000]]')).status,
          PinStatus.broken);
      expect((await check(root, '[[code:lib/src/thing.dart#nope@0000]]')).status,
          PinStatus.broken);
    });
  });

  group('TestResolver', () {
    Directory repoWithTest(String body) {
      Directory('${tmp.path}/test').createSync(recursive: true);
      File('${tmp.path}/test/stream_test.dart').writeAsStringSync(body);
      return tmp;
    }

    File results(List<String> passing) {
      final f = File('${tmp.path}/build/passing-tests.txt')
        ..createSync(recursive: true);
      f.writeAsStringSync('${passing.join('\n')}\n');
      return f;
    }

    const pin = '[[test:test/stream_test.dart#always emits]]';

    test('an existing, passing test is current', () async {
      final root = repoWithTest("test('always emits', () {});");
      final r = await TestResolver(root, results(['always emits']))
          .resolve(onePin(pin));
      expect(r.status, PinStatus.current);
    });

    test('a documented guarantee whose test was deleted is broken', () async {
      final root = repoWithTest("test('something else', () {});");
      final r = await TestResolver(root, results(['something else']))
          .resolve(onePin(pin));
      expect(r.status, PinStatus.broken);
      expect(r.detail, contains('lost'));
    });

    test('a missing test file is broken', () async {
      final r = await TestResolver(tmp, results([])).resolve(onePin(pin));
      expect(r.status, PinStatus.broken);
    });

    test('a test that exists but is not in the passing set is broken', () async {
      final root = repoWithTest("test('always emits', () {});");
      final r = await TestResolver(root, results(['unrelated']))
          .resolve(onePin(pin));
      expect(r.status, PinStatus.broken);
    });

    // The load-bearing case: when the results file is absent the resolver must
    // NOT report current. CI turns this into a failure so a broken test run
    // cannot quietly retire every test pin.
    test('no results file yields unknown, never current', () async {
      final root = repoWithTest("test('always emits', () {});");
      final r = await TestResolver(root, File('${tmp.path}/absent.txt'))
          .resolve(onePin(pin));
      expect(r.status, PinStatus.unknown);
      expect(r.status, isNot(PinStatus.current));
    });

    // A test name is a label, not evidence. Without a body binding, the whole
    // assertion can be replaced and the pin still resolves — at the highest
    // strength in the system, for a guarantee nothing guards any more.
    group('body binding', () {
      const real = "test('always emits', () {\n  expect(rows, isNotEmpty);\n});";
      const gutted = "test('always emits', () {\n  expect(1, 1);\n});";

      Future<PinResult> check(Directory root, String hash) =>
          TestResolver(root, results(['always emits']))
              .resolve(onePin('[[test:test/stream_test.dart#always emits@$hash]]'));

      /// The body hash the resolver currently computes for [body].
      Future<String> hashOf(String body) async {
        final r = await check(repoWithTest(body), '0000');
        return r.status == PinStatus.current
            ? '0000'
            : RegExp(r'@(\w{4})').firstMatch(r.detail)!.group(1)!;
      }

      test('an unchanged body is current', () async {
        final h = await hashOf(real);
        expect((await check(repoWithTest(real), h)).status, PinStatus.current);
      });

      test('a gutted assertion drifts even though the name still passes',
          () async {
        final h = await hashOf(real);
        final r = await check(repoWithTest(gutted), h);
        expect(r.status, PinStatus.drifted,
            reason: 'expect(1, 1) asserts nothing but keeps the name');
        expect(r.detail, contains('still asserts'));
      });

      test('a comment-only edit does not drift', () async {
        final h = await hashOf(real);
        const recommented =
            "test('always emits', () {\n  // why this matters\n  expect(rows, isNotEmpty);\n});";
        expect((await check(repoWithTest(recommented), h)).status,
            PinStatus.current);
      });

      test('a name with no surrounding body is broken', () async {
        final root = repoWithTest("const label = 'always emits';");
        final r = await check(root, 'abcd');
        expect(r.status, PinStatus.broken);
      });

      test('a name-only pin still resolves, for back-compatibility', () async {
        final root = repoWithTest(real);
        final r = await TestResolver(root, results(['always emits']))
            .resolve(onePin(pin));
        expect(r.status, PinStatus.current);
      });
    });
  });

  group('BenchResolver', () {
    File history(List<Map<String, Object?>> runs) {
      final f = File('${tmp.path}/history.json');
      f.writeAsStringSync(json.encode({'runs': runs}));
      return f;
    }

    Map<String, Object?> run(double value, {bool dirty = false, bool noisy = false}) => {
          'date': '2026-07-01',
          'gitDirty': dirty,
          'noisy': noisy,
          'metrics': {'Large read': value},
        };

    Future<PinResult> check(File h, String text) =>
        BenchResolver(h).resolve(onePin(text));

    test('a number inside the tolerance band is current', () async {
      final r = await check(history([run(0.34)]), '[[bench:Large read ~ 0.32 +-15%]]');
      expect(r.status, PinStatus.current);
    });

    test('a number outside the band drifts and quantifies the gap', () async {
      final r = await check(history([run(0.90)]), '[[bench:Large read ~ 0.32 +-15%]]');
      expect(r.status, PinStatus.drifted);
      expect(r.actual, '0.9');
      expect(r.detail, contains('%'));
    });

    test('an untracked metric is broken', () async {
      final r = await check(history([run(0.32)]), '[[bench:No Such Metric ~ 1 +-10%]]');
      expect(r.status, PinStatus.broken);
    });

    // Dirty and noisy runs are hidden from the charts, so pinning against them
    // would compare prose to a number the project already distrusts.
    test('dirty and noisy runs are skipped in favour of the last clean one',
        () async {
      final h = history([
        run(0.32),
        run(9.99, dirty: true),
        run(8.88, noisy: true),
      ]);
      final r = await check(h, '[[bench:Large read ~ 0.32 +-15%]]');
      expect(r.status, PinStatus.current);
    });

    test('no history at all yields unknown, never current', () async {
      final r = await check(File('${tmp.path}/absent.json'),
          '[[bench:Large read ~ 0.32 +-15%]]');
      expect(r.status, PinStatus.unknown);
    });
  });
}
