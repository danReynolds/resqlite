import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('tracelite profile workflow dry-run prints artifact plan', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_workflow_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/profile/run_tracelite_profile.dart',
      '--tracelite-root=${p.join(root, 'test', 'fixtures', 'tracelite_root')}',
      '--runtime=${p.join(temp.path, 'libtracelite_runtime.test')}',
      '--label=unit-run',
      '--out-dir=${p.join(temp.path, 'profile')}',
      '--graph-data-dir=${p.join(temp.path, 'pages', 'tracelite')}',
      '--dry-run',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final stdoutText = result.stdout.toString();
    expect(stdoutText, contains('resqlite tracelite profile plan'));
    expect(stdoutText, contains('primary tracelite artifacts'));
    expect(stdoutText, contains('profile.tlt-region'));
    expect(stdoutText, contains('workload-summary.json'));
    expect(stdoutText, contains('insights.json'));
    expect(stdoutText, contains('insights.md'));
    expect(stdoutText, contains(p.join('pages', 'tracelite', 'index.json')));
    expect(stdoutText, contains('explain'));
    expect(stdoutText, contains('validate-graph-data'));
    expect(
      stdoutText,
      contains('benchmark/profile/run_tracelite_workloads.dart'),
    );
    expect(stdoutText, contains('RESQLITE_TRACELITE=true'));
    expect(stdoutText, contains('TRACELITE_REGION='));
    expect(stdoutText, contains('TRACELITE_RUNTIME='));
    expect(stdoutText, isNot(contains('profile.json')));
    expect(stdoutText, isNot(contains('parity-diff.txt')));
  });

  test('tracelite profile workflow validates workload insight IDs', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_profile_validate_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final fakeRoot = _fakeTraceliteRoot(temp);
    final fakeDart = _fakeProfileDart(
      temp,
      insights: _insightsJson(const {
        'workload_dispatch_floors',
        'workload_work_bound',
        'workload_tail_spread',
        'workload_rss_signal',
        'workload_allocation_signal',
        'workload_wal_signal',
      }),
    );
    final runtime = File(p.join(temp.path, 'libtracelite_runtime.test'))
      ..writeAsStringSync('fake runtime\n');

    final outDir = p.join(temp.path, 'profile');
    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/profile/run_tracelite_profile.dart',
      '--tracelite-root=${fakeRoot.path}',
      '--runtime=${runtime.path}',
      '--dart=${fakeDart.path}',
      '--label=unit-profile',
      '--out-dir=$outDir',
      '--no-graph-data',
      '--allow-unpinned-tracelite',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    expect(
      result.stdout.toString(),
      contains('validated workload-summary insights'),
    );
    expect(File(p.join(outDir, 'manifest.json')).existsSync(), isTrue);
  });

  test('tracelite profile workflow rejects thin workload insights', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_profile_thin_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final fakeRoot = _fakeTraceliteRoot(temp);
    final fakeDart = _fakeProfileDart(
      temp,
      insights: _insightsJson(const {'workload_loaded'}),
    );
    final runtime = File(p.join(temp.path, 'libtracelite_runtime.test'))
      ..writeAsStringSync('fake runtime\n');

    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/profile/run_tracelite_profile.dart',
      '--tracelite-root=${fakeRoot.path}',
      '--runtime=${runtime.path}',
      '--dart=${fakeDart.path}',
      '--label=unit-profile-thin',
      '--out-dir=${p.join(temp.path, 'profile')}',
      '--no-graph-data',
      '--allow-unpinned-tracelite',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      65,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    expect(
      result.stderr.toString(),
      contains('tracelite workload-summary insights are incomplete'),
    );
    expect(result.stderr.toString(), contains('workload_work_bound'));
  });
}

Directory _fakeTraceliteRoot(Directory parent) {
  final root = Directory(p.join(parent.path, 'tracelite_root'));
  Directory(p.join(root.path, 'bin')).createSync(recursive: true);
  File(p.join(root.path, 'bin', 'tracelite.dart')).writeAsStringSync('');
  return root;
}

File _fakeProfileDart(Directory parent, {required String insights}) {
  final insightsFile = File(p.join(parent.path, 'insights-fixture.json'))
    ..writeAsStringSync(insights);
  final fakeDart = File(p.join(parent.path, 'fake-dart'));
  fakeDart.writeAsStringSync('''#!/bin/sh
set -eu
if [ "\$1" = "run" ]; then
  shift
fi

for arg in "\$@"; do
  if [ "\$arg" = "benchmark/profile/run_tracelite_workloads.dart" ]; then
    echo "# workloads"
    exit 0
  fi
done

if [ "\$1" = "bin/tracelite.dart" ] && [ "\$2" = "create-region" ]; then
  out=""
  for arg in "\$@"; do
    case "\$arg" in
      --out=*) out="\${arg#--out=}" ;;
    esac
  done
  mkdir -p "\$(dirname "\$out")"
  echo "region" > "\$out"
  exit 0
fi

if [ "\$1" = "bin/tracelite.dart" ] && [ "\$2" = "workload-summary" ]; then
  out_json=""
  for arg in "\$@"; do
    case "\$arg" in
      --out-json=*) out_json="\${arg#--out-json=}" ;;
    esac
  done
  mkdir -p "\$(dirname "\$out_json")"
  cat > "\$out_json" <<'JSON'
{"schema":"tracelite.workload_summary.v1","workloads":{}}
JSON
  echo "# workload summary"
  exit 0
fi

if [ "\$1" = "bin/tracelite.dart" ] && [ "\$2" = "explain" ]; then
  out_json=""
  for arg in "\$@"; do
    case "\$arg" in
      --out-json=*) out_json="\${arg#--out-json=}" ;;
    esac
  done
  mkdir -p "\$(dirname "\$out_json")"
  cp "${insightsFile.path}" "\$out_json"
  echo "# tracelite insights"
  exit 0
fi

exit 64
''');
  Process.runSync('chmod', ['+x', fakeDart.path]);
  return fakeDart;
}

String _insightsJson(Set<String> ids) {
  return '${jsonEncode({
    'schema': 'tracelite.insights.v1',
    'sources': [
      {
        'path': '/tmp/workload-summary.json',
        'artifact_schema': 'tracelite.workload_summary.v1',
        'insights': [
          for (final id in ids) {'severity': 'info', 'id': id, 'title': id, 'body': id},
        ],
      },
    ],
  })}\n';
}
