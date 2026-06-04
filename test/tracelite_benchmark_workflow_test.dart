import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('tracelite decision workflow dry-run prints release lane plan', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_decision_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final baseline = File(p.join(temp.path, 'baseline-manifest.json'))
      ..writeAsStringSync('{}');
    final candidate = File(p.join(temp.path, 'candidate-manifest.json'))
      ..writeAsStringSync('{}');
    final policy = File(p.join(temp.path, 'policy-calibration.json'))
      ..writeAsStringSync('{}');

    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/decide_tracelite.dart',
      '--tracelite-root=${p.join(root, 'test', 'fixtures', 'tracelite_root')}',
      '--baseline=${baseline.path}',
      '--candidate=${candidate.path}',
      '--policy=${policy.path}',
      '--label=unit-decision',
      '--out-dir=${p.join(temp.path, 'decision')}',
      '--graph-data-dir=${p.join(temp.path, 'pages', 'tracelite-decision')}',
      '--dry-run',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final stdoutText = result.stdout.toString();
    expect(stdoutText, contains('resqlite tracelite decision plan'));
    expect(stdoutText, contains('decision'));
    expect(stdoutText, contains('--policy=${policy.absolute.path}'));
    expect(stdoutText, contains('--expect=no_regression'));
    expect(stdoutText, contains('--primary-peer=resqlite'));
    expect(stdoutText, contains('--primary-metric=measured_elapsed_ns'));
    expect(
      stdoutText,
      contains(
        '--primary-scenarios=high-cardinality-fanout,'
        'many-streams-writer-throughput',
      ),
    );
    expect(stdoutText, contains('--guardrail-peers=resqlite'));
    expect(
      stdoutText,
      contains(
        '--guardrail-scenarios=high-cardinality-fanout,'
        'many-streams-writer-throughput',
      ),
    );
    expect(stdoutText, contains('--guardrail-metrics=measured_elapsed_ns'));
    expect(stdoutText, contains('export-graph-data'));
    expect(stdoutText, contains('--suite=${baseline.absolute.path}'));
    expect(stdoutText, contains('--suite=${candidate.absolute.path}'));
    expect(stdoutText, contains('--decision='));
    expect(stdoutText, contains('explain'));
    expect(stdoutText, contains('insights.json'));
    expect(
      stdoutText,
      contains(p.join('pages', 'tracelite-decision', 'index.json')),
    );
  });

  test('tracelite decision workflow preserves manifest on failure', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_decision_failure_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final fakeRoot = Directory(p.join(temp.path, 'tracelite_root'));
    Directory(p.join(fakeRoot.path, 'bin')).createSync(recursive: true);
    File(p.join(fakeRoot.path, 'bin', 'tracelite.dart')).writeAsStringSync('');
    final fakeDart = File(p.join(temp.path, 'fake-dart'));
    fakeDart.writeAsStringSync('#!/bin/sh\nexit 65\n');
    await Process.run('chmod', ['+x', fakeDart.path]);

    final baseline = File(p.join(temp.path, 'baseline-manifest.json'))
      ..writeAsStringSync('{}');
    final candidate = File(p.join(temp.path, 'candidate-manifest.json'))
      ..writeAsStringSync('{}');
    final policy = File(p.join(temp.path, 'policy-calibration.json'))
      ..writeAsStringSync('{}');
    final outDir = p.join(temp.path, 'decision');

    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/decide_tracelite.dart',
      '--tracelite-root=${fakeRoot.path}',
      '--dart=${fakeDart.path}',
      '--baseline=${baseline.path}',
      '--candidate=${candidate.path}',
      '--policy=${policy.path}',
      '--label=failing-decision',
      '--out-dir=$outDir',
      '--allow-unpinned-tracelite',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      65,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final manifestFile = File(
      p.join(outDir, 'resqlite-tracelite-decision.json'),
    );
    expect(manifestFile.existsSync(), isTrue);
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    expect(manifest['status'], 'failed');
    expect(
      manifest['tracelite_source'],
      containsPair('path', fakeRoot.absolute.path),
    );
    expect(
      manifest['tracelite_source'],
      containsPair('git_available', isFalse),
    );
    final steps = manifest['steps']! as List<Object?>;
    expect(steps, hasLength(1));
    expect(steps.single as Map<String, Object?>, containsPair('exit_code', 65));
  });

  test(
    'tracelite benchmark workflow dry-run prints release gate plan',
    () async {
      final root = Directory.current.path;
      final temp = await Directory.systemTemp.createTemp(
        'resqlite_tracelite_benchmark_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final result = await Process.run(Platform.resolvedExecutable, [
        'benchmark/run_tracelite.dart',
        '--tracelite-root=${p.join(root, 'test', 'fixtures', 'tracelite_root')}',
        '--label=unit-benchmark',
        '--out-dir=${p.join(temp.path, 'benchmark')}',
        '--graph-data-dir=${p.join(temp.path, 'pages', 'tracelite')}',
        '--runs=2',
        '--dry-run',
      ], workingDirectory: root);

      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );

      final stdoutText = result.stdout.toString();
      expect(stdoutText, contains('resqlite tracelite benchmark plan'));
      expect(stdoutText, contains('preset: production'));
      expect(stdoutText, contains('suite_run_timeout_seconds: 1200'));
      expect(stdoutText, contains('runner: script'));
      expect(stdoutText, contains('warmup_runs: 1'));
      expect(
        stdoutText,
        contains('resqlite_root: ${Directory(root).absolute.path}'),
      );
      expect(stdoutText, contains('pub get'));
      expect(stdoutText, contains('prepare tracelite sqlite shim'));
      expect(stdoutText, contains('libsqlite_traced.dylib'));
      expect(stdoutText, contains('warm up tracelite suite'));
      expect(stdoutText, contains(p.join('warmup', 'run-001')));
      expect(stdoutText, contains('suite-history'));
      expect(stdoutText, contains('--profile=production'));
      expect(stdoutText, contains('--runner=script'));
      expect(stdoutText, contains('--interfaces=resqlite'));
      expect(
        stdoutText,
        contains(
          '--scenarios=high-cardinality-fanout,'
          'many-streams-writer-throughput,sqlite-diagnostics',
        ),
      );
      expect(
        stdoutText,
        contains(
          '--policy-scenarios=high-cardinality-fanout,'
          'many-streams-writer-throughput',
        ),
      );
      expect(stdoutText, contains('--metrics=measured_elapsed_ns'));
      expect(stdoutText, contains('--policy-peers=resqlite'));
      expect(stdoutText, contains('--min-repetitions=7'));
      expect(stdoutText, contains('--max-repetitions=30'));
      expect(stdoutText, contains('--target-rse-percent=10'));
      expect(stdoutText, contains('--within-run-noise-percentile=0.75'));
      expect(stdoutText, contains('--threshold-floor-percent=5'));
      expect(stdoutText, contains('--threshold-ceiling-percent=50'));
      expect(stdoutText, contains('--guardrail-floor-percent=3'));
      expect(stdoutText, contains('--noise-gate-floor-percent=5'));
      expect(stdoutText, contains('--noise-gate-ceiling-percent=50'));
      expect(stdoutText, contains('--noise-gate-multiplier=1.5'));
      expect(stdoutText, contains('--max-outlier-percent=15'));
      expect(stdoutText, contains('--max-run-outlier-percent=20'));
      expect(stdoutText, contains('--suite-run-timeout-seconds=1200'));
      expect(stdoutText, contains('export-graph-data'));
      expect(stdoutText, contains('--suite-history='));
      expect(stdoutText, contains('validate-graph-data'));
      expect(stdoutText, contains('explain'));
      expect(stdoutText, contains('insights.json'));
      expect(stdoutText, contains(p.join('pages', 'tracelite', 'index.json')));
    },
  );

  test('tracelite benchmark workflow ci preset stays small', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_benchmark_ci_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/run_tracelite.dart',
      '--preset=ci',
      '--tracelite-root=${p.join(root, 'test', 'fixtures', 'tracelite_root')}',
      '--label=unit-ci-benchmark',
      '--out-dir=${p.join(temp.path, 'benchmark')}',
      '--dry-run',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final stdoutText = result.stdout.toString();
    expect(stdoutText, contains('preset: ci'));
    expect(stdoutText, contains('suite_run_timeout_seconds: 180'));
    expect(stdoutText, contains('runner: script'));
    expect(stdoutText, contains('warmup_runs: 0'));
    expect(stdoutText, contains('--profile=ci'));
    expect(stdoutText, contains('--runner=script'));
    expect(stdoutText, contains('--runs=1'));
    expect(stdoutText, contains('--interfaces=resqlite'));
    expect(
      stdoutText,
      contains(
        '--scenarios=narrow-batch-insert,point-select,'
        'keyed-pk-subscriptions,sqlite-diagnostics',
      ),
    );
    expect(stdoutText, contains('--min-repetitions=1'));
    expect(stdoutText, contains('--max-repetitions=3'));
    expect(stdoutText, contains('--suite-run-timeout-seconds=180'));
    expect(stdoutText, contains('prepare tracelite sqlite shim'));
    expect(stdoutText, contains('validate-graph-data'));
  });

  test(
    'tracelite benchmark workflow rebuilds wrong-arch sqlite shim',
    () async {
      final root = Directory.current.path;
      final temp = await Directory.systemTemp.createTemp(
        'resqlite_tracelite_benchmark_shim_arch_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final fakeRoot = Directory(p.join(temp.path, 'tracelite_root'));
      Directory(p.join(fakeRoot.path, 'bin')).createSync(recursive: true);
      Directory(p.join(fakeRoot.path, 'native')).createSync(recursive: true);
      Directory(p.join(fakeRoot.path, 'build')).createSync(recursive: true);
      File(
        p.join(fakeRoot.path, 'bin', 'tracelite.dart'),
      ).writeAsStringSync('');
      File(
        p.join(fakeRoot.path, 'native', 'tracelite_runtime.c'),
      ).writeAsStringSync('void tracelite_test_runtime(void) {}\n');
      File(
        p.join(fakeRoot.path, 'native', 'shim_sqlite3.c'),
      ).writeAsStringSync('void tracelite_test_shim(void) {}\n');

      final existingShim = File(
        p.join(fakeRoot.path, 'build', 'libsqlite_traced.dylib'),
      );
      existingShim.writeAsStringSync('fake stale x86_64 shim\n');
      existingShim.setLastModifiedSync(
        DateTime.now().add(const Duration(minutes: 1)),
      );

      final fakeFile = File(p.join(temp.path, 'file'));
      fakeFile.writeAsStringSync('''#!/bin/sh
case "\$1" in
  *libsqlite_traced.dylib)
    echo "\$1: Mach-O 64-bit dynamically linked shared library x86_64"
    ;;
  *)
    /usr/bin/file "\$@"
    ;;
esac
''');
      await Process.run('chmod', ['+x', fakeFile.path]);

      final fakeCc = File(p.join(temp.path, 'cc'));
      fakeCc.writeAsStringSync(r'''#!/bin/sh
set -eu
out=""
previous=""
for arg in "$@"; do
  if [ "$previous" = "-o" ]; then
    out="$arg"
  fi
  previous="$arg"
done
if [ -n "$out" ]; then
  mkdir -p "$(dirname "$out")"
  echo "fake rebuilt shim" > "$out"
fi
exit 0
''');
      await Process.run('chmod', ['+x', fakeCc.path]);

      final packageConfig = jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'resqlite',
            'rootUri': Directory(root).absolute.uri.toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
        ],
        'generator': 'fake',
      });

      final fakeDart = File(p.join(temp.path, 'fake-dart'));
      fakeDart.writeAsStringSync('''#!/bin/sh
set -eu
if [ "\$1" = "--version" ]; then
  echo 'Dart SDK version: 3.12.1 (stable) on "macos_arm64"' >&2
  exit 0
fi
if [ "\$1" = "pub" ] && [ "\$2" = "get" ]; then
  mkdir -p .dart_tool
  cat > .dart_tool/package_config.json <<'JSON'
$packageConfig
JSON
  exit 0
fi
if [ "\$1" = "run" ]; then
  shift
fi
if [ "\$1" = "bin/tracelite.dart" ] && [ "\$2" = "suite-history" ]; then
  out=""
  for arg in "\$@"; do
    case "\$arg" in
      --out-dir=*) out="\${arg#--out-dir=}" ;;
    esac
  done
  mkdir -p "\$out/run-001"
  cat > "\$out/history.json" <<JSON
{"schema":"tracelite.suite_history.v1","runs":[{"run":1,"name":"run-001","status":"ok","manifest":"\$out/run-001/manifest.json"}]}
JSON
  cat > "\$out/run-001/manifest.json" <<JSON
{"schema":"tracelite.suite.v1","runs":[]}
JSON
  exit 0
fi
exit 0
''');
      await Process.run('chmod', ['+x', fakeDart.path]);

      final outDir = p.join(temp.path, 'benchmark');
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          'benchmark/run_tracelite.dart',
          '--tracelite-root=${fakeRoot.path}',
          '--dart=${fakeDart.path}',
          '--label=shim-arch',
          '--out-dir=$outDir',
          '--no-graph-data',
          '--allow-unpinned-tracelite',
        ],
        workingDirectory: root,
        environment: {
          ...Platform.environment,
          'PATH': '${temp.path}:${Platform.environment['PATH'] ?? ''}',
        },
      );

      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      final stdoutText = result.stdout.toString();
      expect(stdoutText, contains('cc -arch arm64'));
      expect(stdoutText, isNot(contains('reuse ${existingShim.path}')));

      final manifestFile = File(
        p.join(outDir, 'resqlite-tracelite-benchmark.json'),
      );
      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      final steps = manifest['steps']! as List<Object?>;
      expect(
        steps[1] as Map<String, Object?>,
        containsPair('command', contains('cc -arch arm64')),
      );
    },
    skip: Platform.isMacOS ? false : 'Mach-O shim architecture is macOS only',
  );

  test(
    'tracelite benchmark workflow skips graph export without artifacts',
    () async {
      final root = Directory.current.path;
      final temp = await Directory.systemTemp.createTemp(
        'resqlite_tracelite_benchmark_graph_skip_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final fakeRoot = Directory(p.join(temp.path, 'tracelite_root'));
      Directory(p.join(fakeRoot.path, 'bin')).createSync(recursive: true);
      Directory(p.join(fakeRoot.path, 'native')).createSync(recursive: true);
      File(
        p.join(fakeRoot.path, 'bin', 'tracelite.dart'),
      ).writeAsStringSync('');
      File(
        p.join(fakeRoot.path, 'native', 'tracelite_runtime.c'),
      ).writeAsStringSync('void tracelite_test_runtime(void) {}\n');
      File(
        p.join(fakeRoot.path, 'native', 'shim_sqlite3.c'),
      ).writeAsStringSync('void tracelite_test_shim(void) {}\n');
      _writeFreshFakeShim(fakeRoot);

      final packageConfig = jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'resqlite',
            'rootUri': Directory(root).absolute.uri.toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
        ],
        'generator': 'fake',
      });

      final fakeDart = File(p.join(temp.path, 'fake-dart'));
      fakeDart.writeAsStringSync('''#!/bin/sh
set -eu
if [ "\$1" = "pub" ] && [ "\$2" = "get" ]; then
  mkdir -p .dart_tool
  cat > .dart_tool/package_config.json <<'JSON'
$packageConfig
JSON
  exit 0
fi
if [ "\$1" = "run" ]; then
  shift
fi
if [ "\$1" = "bin/tracelite.dart" ] && [ "\$2" = "suite-history" ]; then
  out=""
  for arg in "\$@"; do
    case "\$arg" in
      --out-dir=*) out="\${arg#--out-dir=}" ;;
    esac
  done
  mkdir -p "\$out/run-001"
  cat > "\$out/history.json" <<JSON
{"schema":"tracelite.suite_history.v1","runs":[{"run":1,"name":"run-001","status":"failed","manifest":"\$out/run-001/manifest.json"}]}
JSON
  cat > "\$out/run-001/manifest.json" <<JSON
{"schema":"tracelite.suite.v1","runs":[{"scenario":"narrow-batch-insert","status":"failed","artifact":"\$out/run-001/narrow-batch-insert.json"}]}
JSON
  exit 65
fi
if [ "\$1" = "bin/tracelite.dart" ] && [ "\$2" = "export-graph-data" ]; then
  echo "export-called" >&2
  exit 88
fi
exit 0
''');
      await Process.run('chmod', ['+x', fakeDart.path]);

      final outDir = p.join(temp.path, 'benchmark');
      final result = await Process.run(Platform.resolvedExecutable, [
        'benchmark/run_tracelite.dart',
        '--tracelite-root=${fakeRoot.path}',
        '--dart=${fakeDart.path}',
        '--label=missing-artifacts',
        '--out-dir=$outDir',
        '--allow-unpinned-tracelite',
      ], workingDirectory: root);

      expect(
        result.exitCode,
        65,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      expect(result.stderr.toString(), isNot(contains('export-called')));
      expect(
        result.stderr.toString(),
        contains('no graphable tracelite suite artifacts found'),
      );

      final manifestFile = File(
        p.join(outDir, 'resqlite-tracelite-benchmark.json'),
      );
      expect(manifestFile.existsSync(), isTrue);
      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      final steps = manifest['steps']! as List<Object?>;
      expect(steps, hasLength(6));
      expect(
        steps[1] as Map<String, Object?>,
        containsPair('name', 'prepare tracelite sqlite shim'),
      );
      expect(
        steps[2] as Map<String, Object?>,
        containsPair('name', 'warm up tracelite suite'),
      );
      expect(
        steps[4] as Map<String, Object?>,
        containsPair('command', contains('inspect')),
      );
      expect(
        steps.last as Map<String, Object?>,
        containsPair('name', 'explain tracelite artifacts'),
      );
    },
  );

  test(
    'tracelite benchmark workflow exports graphable partial suite artifacts',
    () async {
      final root = Directory.current.path;
      final temp = await Directory.systemTemp.createTemp(
        'resqlite_tracelite_benchmark_partial_graph_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final fakeRoot = Directory(p.join(temp.path, 'tracelite_root'));
      Directory(p.join(fakeRoot.path, 'bin')).createSync(recursive: true);
      Directory(p.join(fakeRoot.path, 'native')).createSync(recursive: true);
      File(
        p.join(fakeRoot.path, 'bin', 'tracelite.dart'),
      ).writeAsStringSync('');
      File(
        p.join(fakeRoot.path, 'native', 'tracelite_runtime.c'),
      ).writeAsStringSync('void tracelite_test_runtime(void) {}\n');
      File(
        p.join(fakeRoot.path, 'native', 'shim_sqlite3.c'),
      ).writeAsStringSync('void tracelite_test_shim(void) {}\n');
      _writeFreshFakeShim(fakeRoot);

      final packageConfig = jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'resqlite',
            'rootUri': Directory(root).absolute.uri.toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
        ],
        'generator': 'fake',
      });

      final fakeDart = File(p.join(temp.path, 'fake-dart'));
      fakeDart.writeAsStringSync('''#!/bin/sh
set -eu
if [ "\$1" = "pub" ] && [ "\$2" = "get" ]; then
  mkdir -p .dart_tool
  cat > .dart_tool/package_config.json <<'JSON'
$packageConfig
JSON
  exit 0
fi
if [ "\$1" = "run" ]; then
  shift
fi
if [ "\$1" = "bin/tracelite.dart" ] && [ "\$2" = "suite-history" ]; then
  out=""
  for arg in "\$@"; do
    case "\$arg" in
      --out-dir=*) out="\${arg#--out-dir=}" ;;
    esac
  done
  mkdir -p "\$out/run-001"
  cat > "\$out/run-001/ok.json" <<JSON
{"schema":"tracelite.compare.v1","rows":[]}
JSON
  cat > "\$out/history.json" <<JSON
{"schema":"tracelite.suite_history.v1","runs":[{"run":1,"name":"run-001","status":"failed","manifest":"\$out/run-001/manifest.json"}]}
JSON
  cat > "\$out/run-001/manifest.json" <<JSON
{"schema":"tracelite.suite.v1","runs":[{"scenario":"narrow-batch-insert","status":"ok","artifact":"\$out/run-001/ok.json"},{"scenario":"point-select","status":"failed","artifact":"\$out/run-001/missing.json"}]}
JSON
  exit 65
fi
if [ "\$1" = "bin/tracelite.dart" ] && [ "\$2" = "export-graph-data" ]; then
  graph_out=""
  suites=""
  for arg in "\$@"; do
    case "\$arg" in
      --out=*) graph_out="\${arg#--out=}" ;;
      --suite=*) suites="\$suites\${arg#--suite=}\\n" ;;
    esac
  done
  mkdir -p "\$graph_out"
  printf "%b" "\$suites" > "\$graph_out/export-suites.txt"
  exit 0
fi
if [ "\$1" = "bin/tracelite.dart" ] && [ "\$2" = "validate-graph-data" ]; then
  exit 0
fi
exit 0
''');
      await Process.run('chmod', ['+x', fakeDart.path]);

      final outDir = p.join(temp.path, 'benchmark');
      final result = await Process.run(Platform.resolvedExecutable, [
        'benchmark/run_tracelite.dart',
        '--tracelite-root=${fakeRoot.path}',
        '--dart=${fakeDart.path}',
        '--label=partial-artifacts',
        '--out-dir=$outDir',
        '--allow-unpinned-tracelite',
      ], workingDirectory: root);

      expect(
        result.exitCode,
        65,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );

      final filteredManifest = File(
        p.join(outDir, 'graph-data-inputs', 'run-001-manifest.json'),
      );
      expect(filteredManifest.existsSync(), isTrue);
      final filtered =
          jsonDecode(filteredManifest.readAsStringSync())
              as Map<String, Object?>;
      final runs = filtered['runs']! as List<Object?>;
      expect(runs, hasLength(1));
      final run = runs.single as Map<String, Object?>;
      expect(run['scenario'], 'narrow-batch-insert');
      expect(run['status'], 'ok');
      expect(File(run['artifact']! as String).isAbsolute, isTrue);

      final exportSuites = File(
        p.join(outDir, 'graph-data', 'export-suites.txt'),
      ).readAsStringSync();
      expect(exportSuites, contains(filteredManifest.path));

      final manifestFile = File(
        p.join(outDir, 'resqlite-tracelite-benchmark.json'),
      );
      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      final artifacts = manifest['artifacts'] as Map<String, Object?>;
      expect(artifacts['insights_json'], p.join(outDir, 'insights.json'));
      expect(artifacts['insights_markdown'], p.join(outDir, 'insights.md'));
      expect(
        artifacts['graph_data_inputs_dir'],
        p.join(outDir, 'graph-data-inputs'),
      );
      final steps = manifest['steps']! as List<Object?>;
      expect(
        steps.any(
          (step) =>
              step is Map<String, Object?> &&
              step['name'] == 'export tracelite graph data' &&
              step['exit_code'] == 0,
        ),
        isTrue,
      );
    },
  );

  test('tracelite benchmark workflow preserves manifest on failure', () async {
    final root = Directory.current.path;
    final checkoutRevision = await _currentGitRevision(root);
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_benchmark_failure_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final fakeRoot = Directory(p.join(temp.path, 'tracelite_root'));
    Directory(p.join(fakeRoot.path, 'bin')).createSync(recursive: true);
    File(p.join(fakeRoot.path, 'bin', 'tracelite.dart')).writeAsStringSync('');
    final fakeDart = File(p.join(temp.path, 'fake-dart'));
    fakeDart.writeAsStringSync('#!/bin/sh\nexit 65\n');
    await Process.run('chmod', ['+x', fakeDart.path]);

    final outDir = p.join(temp.path, 'benchmark');
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        'benchmark/run_tracelite.dart',
        '--tracelite-root=${fakeRoot.path}',
        '--dart=${fakeDart.path}',
        '--label=failing-benchmark',
        '--out-dir=$outDir',
        '--no-graph-data',
        '--allow-unpinned-tracelite',
      ],
      workingDirectory: root,
      environment: {
        'GITHUB_ACTIONS': 'true',
        'GITHUB_EVENT_NAME': 'pull_request',
        'GITHUB_REPOSITORY': 'danReynolds/resqlite',
        'GITHUB_REF': 'refs/pull/109/merge',
        'GITHUB_REF_NAME': '109/merge',
        'GITHUB_HEAD_REF': 'codex/tracelite-profiling-hooks',
        'GITHUB_BASE_REF': 'main',
        'GITHUB_SHA': checkoutRevision,
        'RESQLITE_SOURCE_HEAD_SHA': '2361882-head',
        'RESQLITE_SOURCE_BASE_SHA': 'main-base',
      },
    );

    expect(
      result.exitCode,
      65,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final manifestFile = File(
      p.join(outDir, 'resqlite-tracelite-benchmark.json'),
    );
    expect(manifestFile.existsSync(), isTrue);
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    expect(manifest['status'], 'failed');
    expect(
      manifest['tracelite_source'],
      containsPair('path', fakeRoot.absolute.path),
    );
    expect(
      manifest['tracelite_source'],
      containsPair('git_available', isFalse),
    );
    expect(
      manifest['resqlite_source'],
      containsPair('path', Directory(root).absolute.path),
    );
    final resqliteSource = manifest['resqlite_source'] as Map<String, Object?>;
    final githubActions =
        resqliteSource['github_actions'] as Map<String, Object?>;
    expect(githubActions['event_name'], 'pull_request');
    expect(githubActions['checkout_sha'], checkoutRevision);
    expect(githubActions['head_sha'], '2361882-head');
    expect(githubActions['base_sha'], 'main-base');
    expect(githubActions['checkout_matches_github_sha'], isTrue);
    expect(githubActions['checkout_matches_head_sha'], isFalse);
    expect(
      manifest['tracelite_resqlite_dependency'],
      containsPair('expected_resqlite_root', Directory(root).absolute.path),
    );
    final steps = manifest['steps']! as List<Object?>;
    expect(steps, hasLength(1));
    expect(steps.single as Map<String, Object?>, containsPair('exit_code', 65));
  });

  test('tracelite benchmark workflow records child start failure', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_benchmark_start_failure_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final fakeRoot = Directory(p.join(temp.path, 'tracelite_root'));
    Directory(p.join(fakeRoot.path, 'bin')).createSync(recursive: true);
    File(p.join(fakeRoot.path, 'bin', 'tracelite.dart')).writeAsStringSync('');

    final outDir = p.join(temp.path, 'benchmark');
    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/run_tracelite.dart',
      '--tracelite-root=${fakeRoot.path}',
      '--dart=${p.join(temp.path, 'missing-dart')}',
      '--label=start-failure',
      '--out-dir=$outDir',
      '--no-graph-data',
      '--allow-unpinned-tracelite',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      127,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    expect(
      result.stderr.toString(),
      contains('resqlite tracelite wrapper: failed to start child'),
    );

    final manifestFile = File(
      p.join(outDir, 'resqlite-tracelite-benchmark.json'),
    );
    expect(manifestFile.existsSync(), isTrue);
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    expect(manifest['status'], 'failed');
    final steps = manifest['steps']! as List<Object?>;
    expect(steps, hasLength(1));
    expect(
      steps.single as Map<String, Object?>,
      containsPair('exit_code', 127),
    );
  });

  test('tracelite benchmark workflow rejects dependency mismatch', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_dependency_mismatch_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final fakeRoot = Directory(p.join(temp.path, 'tracelite_root'));
    Directory(p.join(fakeRoot.path, 'bin')).createSync(recursive: true);
    File(p.join(fakeRoot.path, 'bin', 'tracelite.dart')).writeAsStringSync('');
    File(p.join(fakeRoot.path, 'pubspec_overrides.yaml')).writeAsStringSync('''
dependency_overrides:
  resqlite:
    path: /tmp/wrong-resqlite
''');

    final fakeDart = File(p.join(temp.path, 'fake-dart'));
    fakeDart.writeAsStringSync(r'''#!/bin/sh
if [ "$1" = "pub" ] && [ "$2" = "get" ]; then
  mkdir -p .dart_tool
  cat > .dart_tool/package_config.json <<'JSON'
{"configVersion":2,"packages":[{"name":"resqlite","rootUri":"file:///tmp/wrong-resqlite/","packageUri":"lib/","languageVersion":"3.10"}],"generator":"fake"}
JSON
  exit 0
fi
exit 0
''');
    await Process.run('chmod', ['+x', fakeDart.path]);

    final outDir = p.join(temp.path, 'benchmark');
    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/run_tracelite.dart',
      '--tracelite-root=${fakeRoot.path}',
      '--dart=${fakeDart.path}',
      '--label=dependency-mismatch',
      '--out-dir=$outDir',
      '--no-graph-data',
      '--allow-unpinned-tracelite',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      64,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    expect(
      result.stderr.toString(),
      contains('does not resolve resqlite to the checkout under test'),
    );

    final manifestFile = File(
      p.join(outDir, 'resqlite-tracelite-benchmark.json'),
    );
    expect(manifestFile.existsSync(), isTrue);
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    expect(manifest['status'], 'failed');
    final binding =
        manifest['tracelite_resqlite_dependency'] as Map<String, Object?>;
    expect(binding['matches_requested_root'], isFalse);
    expect(
      binding['resolved_resqlite_root'],
      isNot(Directory(root).absolute.path),
    );
    final steps = manifest['steps']! as List<Object?>;
    expect(steps, hasLength(2));
    expect(steps.last as Map<String, Object?>, containsPair('exit_code', 64));
  });

  test('tracelite benchmark workflow rejects unpinned checkout', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_unpinned_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final fakeRoot = Directory(p.join(temp.path, 'tracelite_root'));
    Directory(p.join(fakeRoot.path, 'bin')).createSync(recursive: true);
    File(p.join(fakeRoot.path, 'bin', 'tracelite.dart')).writeAsStringSync('');

    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/run_tracelite.dart',
      '--tracelite-root=${fakeRoot.path}',
      '--label=unpinned-benchmark',
      '--out-dir=${p.join(temp.path, 'benchmark')}',
      '--no-graph-data',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      64,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    expect(
      result.stderr.toString(),
      contains('tracelite source pin cannot be verified'),
    );
  });
}

Future<String> _currentGitRevision(String root) async {
  final result = await Process.run('git', [
    'rev-parse',
    'HEAD',
  ], workingDirectory: root);
  expect(
    result.exitCode,
    0,
    reason:
        'git rev-parse HEAD failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}',
  );
  return result.stdout.toString().trim();
}

void _writeFreshFakeShim(Directory fakeRoot) {
  final buildDir = Directory(p.join(fakeRoot.path, 'build'))
    ..createSync(recursive: true);
  final shim = File(p.join(buildDir.path, 'libsqlite_traced.dylib'))
    ..writeAsStringSync('fake shim\n');
  shim.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
}
