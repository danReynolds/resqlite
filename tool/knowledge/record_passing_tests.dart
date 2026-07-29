// ignore_for_file: avoid_print
/// Records the names of passing tests so `test:` pins can be proven rather
/// than merely resolved.
///
///   dart test --file-reporter=json:build/test-results.json
///   dart run tool/knowledge/record_passing_tests.dart build/test-results.json
///
/// Prefer the file form. Piping `--reporter=json` also works, but it replaces
/// the human-readable test output in CI logs, and the pipeline then masks
/// `dart test`'s exit code unless the caller remembers `pipefail`. A file
/// reporter avoids both: the test step fails on its own when tests fail, and
/// the log still reads normally.
///
/// Writes one test name per line to `build/passing-tests.txt`. Without that
/// file a `test:` pin reports `unknown` — deliberately, because an unavailable
/// checker must never read as a pass.
library;

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final names = <int, String>{};
  final passing = <String>{};

  final source = args.isNotEmpty
      ? File(args.first).openRead().transform(utf8.decoder).transform(
          const LineSplitter(),
        )
      : stdin.transform(utf8.decoder).transform(const LineSplitter());

  if (args.isNotEmpty && !File(args.first).existsSync()) {
    stderr.writeln('::error::No test report at ${args.first}');
    exitCode = 1;
    return;
  }

  await for (final line in source) {
    Object? decoded;
    try {
      decoded = json.decode(line);
    } on FormatException {
      continue; // the reporter interleaves non-JSON chatter
    }
    if (decoded is! Map) continue;
    switch (decoded['type']) {
      case 'testStart':
        final test = decoded['test'];
        if (test is Map && test['id'] is int && test['name'] is String) {
          names[test['id'] as int] = test['name'] as String;
        }
      case 'testDone':
        if (decoded['result'] == 'success' && decoded['hidden'] != true) {
          final name = names[decoded['testID']];
          if (name != null) passing.add(name);
        }
    }
  }

  final out = File('build/passing-tests.txt');
  out.createSync(recursive: true);
  out.writeAsStringSync('${passing.join('\n')}\n');
  print('Recorded ${passing.length} passing tests to ${out.path}');

  // An empty record is the dangerous outcome, not a harmless one: it means the
  // test run died before reporting, and every `test:` pin would silently fall
  // back to `unknown`. Fail here so the cause is visible at its source rather
  // than as a wave of warnings two steps later.
  if (passing.isEmpty) {
    stderr.writeln(
      '::error::No passing tests were recorded. The test run produced no '
      'successful results, so `test:` pins have nothing to verify against.',
    );
    exitCode = 1;
  }
}
