library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../benchmark/check_experiment_dispositions.dart' as dispositions;
import '../benchmark/generate_devices.dart' as generate_devices;
import '../benchmark/generate_history.dart' as generate_history;
import '../benchmark/shared/release_artifact.dart';
import '../benchmark/shared/stats.dart';
import '../benchmark/shared/workload_registry.dart';
import 'benchmark_pipeline_fixtures.dart';

void main() {
  group('release sidecar summary artifact', () {
    test('stores compact repeat aggregates and benchmark summary', () {
      final artifact = buildReleaseRunArtifact(
        label: 'fixture',
        repeatCount: 3,
        markdown: fixtureBenchmarkMarkdown,
        aggregates: {
          'Select → Maps / 1000 rows / resqlite select()': AggregateStats([
            1.10,
            1.20,
            1.30,
          ]),
        },
        environment: const {'runtime': 'dart-vm'},
        comparisonBaselineFile: 'baseline.md',
        comparisonBaselineMode: 'explicit',
        comparisonBaselineCompatibility: const {
          'selectedBaselineFile': 'baseline.md',
          'mode': 'explicit',
          'compatible': false,
          'reasons': ['ci differs'],
          'comparisonExecuted': true,
        },
        generatedAt: '2026-04-23T00:00:00.000Z',
      );

      expect(artifact['schemaVersion'], equals(3));
      expect(artifact['comparisonBaselineFile'], equals('baseline.md'));
      expect(artifact['comparisonBaselineMode'], equals('explicit'));
      expect(
        artifact['comparisonBaselineCompatibility'],
        containsPair('comparisonExecuted', true),
      );
      expect(artifact.containsKey('benchmarks'), isFalse);
      expect(artifact.containsKey('benchmarkSummary'), isTrue);

      final repeatAggregates =
          artifact['repeatAggregates'] as Map<String, Object?>;
      final aggregate = repeatAggregates.values.single as Map<String, Object?>;
      expect(
        aggregate.keys,
        equals({'median', 'madPct', 'stability', 'comparisonThresholdPct'}),
      );

      final sections = artifactBenchmarks(artifact);
      expect(sections, isNotNull);
      expect(sections, hasLength(1));
      expect(sections!.single['title'], equals('Select → Maps'));
    });
  });

  group('generate_devices', () {
    test('uses benchmark summary from sidecar when present', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'resqlite_devices_sidecar_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final resultsDir = Directory('${tempDir.path}/results')..createSync();
      final markdownFile = File(
        '${resultsDir.path}/2026-04-23T11-08-40-fixture.md',
      )..writeAsStringSync('# summary only\n');

      final sidecar = buildReleaseRunArtifact(
        label: 'fixture',
        repeatCount: 3,
        markdown: fixtureBenchmarkMarkdown,
        aggregates: const {},
        environment: const {'runtime': 'dart-vm'},
        generatedAt: '2026-04-23T00:00:00.000Z',
      );
      File(
        markdownFile.path.replaceFirst('.md', '.json'),
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(sidecar));

      final output = generate_devices.buildDevicesData(
        hardwareResultsMarkdown: fixtureHardwareResultsMarkdown(
          resultFile: '2026-04-23T11-08-40-fixture.md',
        ),
        resultsDir: resultsDir,
        generatedAt: '2026-04-23T00:00:00.000Z',
      );

      final devices = output['devices'] as List<Map<String, Object?>>;
      expect(devices, hasLength(1));
      expect(devices.single['environment'], isNotNull);

      final benchmarks =
          devices.single['benchmarks'] as List<Map<String, Object?>>;
      expect(benchmarks, isNotEmpty);
      expect(benchmarks.single['title'], equals('Select → Maps'));
    });

    test(
      'falls back to markdown benchmark parsing when sidecar omits benchmark tables',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'resqlite_devices_test_',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final resultsDir = Directory('${tempDir.path}/results')..createSync();
        final markdownFile = File(
          '${resultsDir.path}/2026-04-23T11-08-40-fixture.md',
        )..writeAsStringSync(fixtureBenchmarkMarkdown);

        final sidecar = buildReleaseRunArtifact(
          label: 'fixture',
          repeatCount: 3,
          markdown: fixtureBenchmarkMarkdown,
          aggregates: const {},
          environment: const {'runtime': 'dart-vm'},
          generatedAt: '2026-04-23T00:00:00.000Z',
        );
        sidecar.remove('benchmarkSummary');
        File(markdownFile.path.replaceFirst('.md', '.json')).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(sidecar),
        );

        final output = generate_devices.buildDevicesData(
          hardwareResultsMarkdown: fixtureHardwareResultsMarkdown(
            resultFile: '2026-04-23T11-08-40-fixture.md',
          ),
          resultsDir: resultsDir,
          generatedAt: '2026-04-23T00:00:00.000Z',
        );

        final devices = output['devices'] as List<Map<String, Object?>>;
        expect(devices, hasLength(1));
        expect(devices.single['environment'], isNotNull);

        final benchmarks =
            devices.single['benchmarks'] as List<Map<String, Object?>>;
        expect(benchmarks, isNotEmpty);
        expect(benchmarks.single['title'], equals('Select → Maps'));
      },
    );

    test('parses in-review experiments and Approach sections', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'resqlite_history_in_review_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final resultsDir = Directory('${tempDir.path}/results')..createSync();
      final experimentsDir = Directory('${tempDir.path}/experiments')
        ..createSync();

      File('${experimentsDir.path}/README.md').writeAsStringSync('''
## In Review

| # | Experiment | Impact | PR |
|---|---|---|---|
| [100](100-test.md) | Test In Review | Still being evaluated | |
''');

      File('${experimentsDir.path}/100-test.md').writeAsStringSync('''
# Experiment 100: Test In Review

**Date:** 2026-04-25
**Status:** In Review
**Benchmark Run:** none (synthetic test fixture; no real release artifact)

## Problem
Synthetic in-review fixture.

## Approach
Scheduler details should be extracted.

## Decision
Keep in review.
''');

      final output = generate_history.buildHistoryData(
        resultsDir: resultsDir,
        experimentsDir: experimentsDir,
        generatedAt: '2026-04-25T00:00:00.000Z',
      );

      final experiments = output['experiments'] as List<Map<String, Object?>>;
      final experiment = experiments.single;
      expect(experiment['status'], equals('in_review'));
      expect(
        experiment['approach'],
        equals('Scheduler details should be extracted.'),
      );
    });
  });

  group('generate_history', () {
    test(
      'prefers sidecar metrics and carries environment into history',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'resqlite_history_test_',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final resultsDir = Directory('${tempDir.path}/results')..createSync();
        final experimentsDir = Directory('${tempDir.path}/experiments')
          ..createSync();

        final markdownFile = File(
          '${resultsDir.path}/2026-04-23T11-08-40-fixture.md',
        )..writeAsStringSync(fixtureBenchmarkMarkdown);

        final sidecar = buildReleaseRunArtifact(
          label: 'fixture',
          repeatCount: 3,
          markdown: fixtureBenchmarkMarkdown,
          aggregates: const {},
          environment: const {'runtime': 'dart-vm', 'gitSha': 'deadbeef'},
          generatedAt: '2026-04-23T00:00:00.000Z',
        );
        final sidecarMetrics = sidecar['metrics'] as Map<String, Object?>;
        sidecarMetrics['Select → Maps / 1000 rows / resqlite select()'] = 9.99;
        File(markdownFile.path.replaceFirst('.md', '.json')).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(sidecar),
        );

        File(
          '${experimentsDir.path}/README.md',
        ).writeAsStringSync(fixtureExperimentsReadmeMarkdown);

        File(
          '${experimentsDir.path}/083-test.md',
        ).writeAsStringSync(fixtureExperimentMarkdown);

        final output = generate_history.buildHistoryData(
          resultsDir: resultsDir,
          experimentsDir: experimentsDir,
          generatedAt: '2026-04-23T00:00:00.000Z',
        );

        final runs = output['runs'] as List<Map<String, Object?>>;
        expect(runs, hasLength(1));
        final run = runs.single;
        final metrics = run['metrics'] as Map<String, Object?>;
        expect(metrics['Select → Maps / 1000 rows / resqlite select()'], 9.99);
        expect(
          (run['environment'] as Map<String, Object?>)['runtime'],
          'dart-vm',
        );

        final experiments = output['experiments'] as List<Map<String, Object?>>;
        final experiment = experiments.single;
        expect(
          experiment['primaryMetrics'],
          equals(['Select → Maps / 1000 rows / resqlite select()']),
        );
        expect(
          (experiment['benchmarkRun'] as Map<String, Object?>)['source'],
          equals('same-day'),
        );
      },
    );

    test('does not map Tracelite experiment docs to release runs', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'resqlite_history_tracelite_mapping_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final resultsDir = Directory('${tempDir.path}/results')..createSync();
      final experimentsDir = Directory('${tempDir.path}/experiments')
        ..createSync();

      File(
        '${resultsDir.path}/2026-06-08T07-34-23-exp144-sqlite3mc-2-3-5.md',
      ).writeAsStringSync(fixtureBenchmarkMarkdown);

      File('${experimentsDir.path}/README.md').writeAsStringSync('''
## Rejected

| # | Experiment | Impact | PR |
|---|---|---|---|
| [146](146-lower-batch-pack-threshold.md) | Lower batch packing threshold | Slower/noisy under Tracelite | |
''');

      File(
        '${experimentsDir.path}/146-lower-batch-pack-threshold.md',
      ).writeAsStringSync('''
# Experiment 146: Lower batch packing threshold

**Date:** 2026-06-08
**Status:** Rejected
**Benchmark Run:** Tracelite A/B experiment, `exp-146-lower-batch-pack-threshold`

## Problem
Synthetic Tracelite fixture.

## Results
Tracelite decision artifacts live under build/.
''');

      final output = generate_history.buildHistoryData(
        resultsDir: resultsDir,
        experimentsDir: experimentsDir,
        generatedAt: '2026-06-08T00:00:00.000Z',
      );

      final experiments = output['experiments'] as List<Map<String, Object?>>;
      final experiment = experiments.single;
      expect(experiment['id'], equals('146'));
      expect(experiment.containsKey('benchmarkRun'), isFalse);
    });
  });

  group('missing-run-without-declaration guard', () {
    Map<String, Object?> exp({
      required String id,
      required String status,
      Object? benchmarkRun,
    }) => {
      'id': id,
      'title': 'exp $id',
      'status': status,
      if (benchmarkRun != null) 'benchmarkRun': benchmarkRun,
    };

    test('flags a chartable experiment >= cutoff with no run and no opt-out', () {
      final issues = generate_history.findUndeclaredMissingRunExperiments([
        exp(id: '178', status: 'accepted'),
      ], const <String>{}, cutoff: 178);
      expect(issues, hasLength(1));
      expect(issues.single, contains('exp 178'));
      expect(issues.single, contains('no **Benchmark Run:** declaration'));
    });

    test('stays silent when the experiment declares the opt-out header', () {
      final issues = generate_history.findUndeclaredMissingRunExperiments([
        exp(id: '178', status: 'accepted'),
      ], <String>{'178'}, cutoff: 178);
      expect(issues, isEmpty);
    });

    test('stays silent when a benchmark run is linked', () {
      final issues = generate_history.findUndeclaredMissingRunExperiments([
        exp(id: '178', status: 'in_review', benchmarkRun: {'id': 'exp178-x'}),
      ], const <String>{}, cutoff: 178);
      expect(issues, isEmpty);
    });

    test('grandfathers experiments below the cutoff', () {
      final issues = generate_history.findUndeclaredMissingRunExperiments([
        exp(id: '177', status: 'in_review'),
        exp(id: '116', status: 'in_review'),
      ], const <String>{}, cutoff: 178);
      expect(issues, isEmpty);
    });

    test('exp 188 walked the cutoff to 1 — every chartable id is in scope', () {
      // After the exp 188 backfill, every accepted/in-review experiment must
      // either link a run or declare opt-out. The pure detector should flag a
      // chartable id of any number when no declaration is present.
      final issues = generate_history.findUndeclaredMissingRunExperiments([
        exp(id: '003', status: 'accepted'),
        exp(id: '083', status: 'in_review'),
      ], const <String>{}, cutoff: 1);
      expect(issues, hasLength(2));
      expect(issues[0], contains('exp 003'));
      expect(issues[1], contains('exp 083'));
    });

    test('ignores rejected experiments (they may legitimately lack a run)', () {
      final issues = generate_history.findUndeclaredMissingRunExperiments([
        exp(id: '200', status: 'rejected'),
      ], const <String>{}, cutoff: 178);
      expect(issues, isEmpty);
    });

    test('the live experiment set passes the guard at the shipped cutoff', () {
      // Regression anchor: the real experiments/ tree must stay clean so the
      // CI generator does not start failing on already-merged work.
      final output = generate_history.buildHistoryData(
        resultsDir: Directory('benchmark/results'),
        experimentsDir: Directory('experiments'),
        generatedAt: '2026-06-16T00:00:00.000Z',
      );
      final experiments = output['experiments'] as List<Map<String, Object?>>;
      // buildHistoryData consumes the opt-out flag internally; re-derive the
      // declared opt-out set from the docs to feed the pure detector.
      final docFiles = Directory('experiments')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList();
      final optOuts = <String>{};
      for (final e in experiments) {
        final id = e['id'] as String;
        final match = docFiles.firstWhere(
          (f) => f.uri.pathSegments.last.startsWith('$id-'),
          orElse: () => File(''),
        );
        if (match.path.isEmpty) continue;
        final headerMatch = RegExp(
          r'^\*\*Benchmark Run:\*\*\s*(.+)$',
          caseSensitive: false,
          multiLine: true,
        ).firstMatch(match.readAsStringSync());
        final header = headerMatch?.group(1)?.trim().toLowerCase();
        if (header == null) continue;
        if (header.startsWith('none') ||
            header.startsWith('n/a') ||
            header.startsWith('not applicable') ||
            header.startsWith('tracelite')) {
          optOuts.add(id.toLowerCase());
        }
      }
      final issues = generate_history.findUndeclaredMissingRunExperiments(
        experiments,
        optOuts,
      );
      expect(
        issues,
        isEmpty,
        reason:
            'Live experiments tripped the missing-run guard:\n${issues.join('\n')}',
      );
    });
  });

  group('terminal-disposition guard', () {
    Future<Directory> fixture({
      required String indexStatus,
      required String writeupStatus,
      String? outcomeClass,
    }) async {
      final tmp = await Directory.systemTemp.createTemp('resqlite_disp_test_');
      addTearDown(() => tmp.delete(recursive: true));
      Directory('${tmp.path}/index').createSync(recursive: true);
      Directory('${tmp.path}/signals/entries').createSync(recursive: true);
      File('${tmp.path}/index/100.json').writeAsStringSync(
        jsonEncode({'file': '100-test.md', 'title': 'T', 'status': indexStatus}),
      );
      File(
        '${tmp.path}/100-test.md',
      ).writeAsStringSync('# Experiment 100\n\n**Status:** $writeupStatus\n');
      if (outcomeClass != null) {
        File('${tmp.path}/signals/entries/100.json').writeAsStringSync(
          jsonEncode({
            'directions': ['x'],
            'outcomeClass': outcomeClass,
          }),
        );
      }
      return tmp;
    }

    test('flags an in-review index status', () async {
      final dir = await fixture(
        indexStatus: 'in_review',
        writeupStatus: 'Accepted',
      );
      final issues = dispositions.findStrandedInReview(root: dir.path);
      expect(issues, hasLength(1));
      expect(issues.single, contains('index/100.json'));
      expect(issues.single, contains('not terminal'));
    });

    test('flags an in-review writeup Status line', () async {
      final dir = await fixture(
        indexStatus: 'accepted',
        writeupStatus: 'In Review',
      );
      final issues = dispositions.findStrandedInReview(root: dir.path);
      expect(issues, hasLength(1));
      expect(issues.single, contains('100-test.md'));
    });

    test('flags an in-review signal outcomeClass', () async {
      final dir = await fixture(
        indexStatus: 'accepted',
        writeupStatus: 'Accepted',
        outcomeClass: 'in_review_accepted',
      );
      final issues = dispositions.findStrandedInReview(root: dir.path);
      expect(issues, hasLength(1));
      expect(issues.single, contains('entries/100.json'));
    });

    test('stays silent for terminal dispositions with descriptive text', () async {
      final dir = await fixture(
        indexStatus: 'rejected',
        writeupStatus: 'Rejected (below noise floor)',
        outcomeClass: 'rejected_below_signal',
      );
      expect(dispositions.findStrandedInReview(root: dir.path), isEmpty);
    });

    test('the live experiment set has no stranded in-review experiments', () {
      // Regression anchor: once reconciled, the real tree must stay terminal so
      // the CI guard does not start failing on already-merged work.
      final issues = dispositions.findStrandedInReview(root: 'experiments');
      expect(
        issues,
        isEmpty,
        reason: 'Experiments stuck in review:\n${issues.join('\n')}',
      );
    });
  });

  group('generate_history noise classification', () {
    String runMarkdown({
      required String label,
      required int repeats,
      required double sqlite3Median,
      required double sqlite3P90,
    }) {
      return '''
# resqlite Benchmark Results

Run settings:
- Label: `$label`
- Repeats: `$repeats`

## Select → Maps

### 1000 rows

| Library | Wall med | Wall p90 | Main med | Main p90 |
|---|---|---|---|---|
| resqlite select() | 1.00 | 1.10 | 0.10 | 0.12 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med | Wall p90 | Main med | Main p90 |
|---|---|---|---|---|
| resqlite execute() | 1.50 | 2.50 | 1.50 | 2.50 |
| sqlite3 execute() | $sqlite3Median | $sqlite3P90 | $sqlite3Median | $sqlite3P90 |
''';
    }

    test('flags single-sample, sqlite3-elevated, and sqlite3-p90 runs', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'resqlite_noise_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final resultsDir = Directory('${tempDir.path}/results')..createSync();
      final experimentsDir = Directory('${tempDir.path}/experiments')
        ..createSync();

      // 1. Clean run — 5 repeats, sqlite3 envelope normal.
      File('${resultsDir.path}/2026-04-23T10-00-00-clean.md').writeAsStringSync(
        runMarkdown(
          label: 'clean',
          repeats: 5,
          sqlite3Median: 5.0,
          sqlite3P90: 7.0,
        ),
      );
      // 2. Single-sample run — should be flagged regardless of sqlite3 numbers.
      File(
        '${resultsDir.path}/2026-04-23T11-00-00-single.md',
      ).writeAsStringSync(
        runMarkdown(
          label: 'single',
          repeats: 1,
          sqlite3Median: 4.5,
          sqlite3P90: 6.0,
        ),
      );
      // 3. Multi-sample but sqlite3 median elevated — flagged via control gate.
      File(
        '${resultsDir.path}/2026-04-23T12-00-00-loaded-median.md',
      ).writeAsStringSync(
        runMarkdown(
          label: 'loaded-median',
          repeats: 5,
          sqlite3Median: 13.0,
          sqlite3P90: 20.0,
        ),
      );
      // 4. Multi-sample but sqlite3 p90 catastrophic — flagged via p90 gate.
      File(
        '${resultsDir.path}/2026-04-23T13-00-00-loaded-p90.md',
      ).writeAsStringSync(
        runMarkdown(
          label: 'loaded-p90',
          repeats: 5,
          sqlite3Median: 6.0,
          sqlite3P90: 100.0,
        ),
      );

      final output = generate_history.buildHistoryData(
        resultsDir: resultsDir,
        experimentsDir: experimentsDir,
        generatedAt: '2026-04-23T00:00:00.000Z',
      );

      final runs = output['runs'] as List<Map<String, Object?>>;
      final byLabel = {for (final r in runs) r['label'] as String: r};

      expect(byLabel['clean']!.containsKey('noisy'), isFalse);
      expect(byLabel['clean']!['repeatCount'], equals(5));

      expect(byLabel['single']!['noisy'], isTrue);
      expect(
        byLabel['single']!['noisyReason'] as String,
        contains('single-sample run'),
      );

      expect(byLabel['loaded-median']!['noisy'], isTrue);
      expect(
        byLabel['loaded-median']!['noisyReason'] as String,
        contains('sqlite3 control elevated'),
      );

      expect(byLabel['loaded-p90']!['noisy'], isTrue);
      expect(
        byLabel['loaded-p90']!['noisyReason'] as String,
        contains('p90 elevated'),
      );
    });
  });

  group('workload registry', () {
    test(
      'curated definitions resolve cleanly and chart groups stay coherent',
      () {
        final syntheticKeys = [
          for (final definition in curatedMetricDefinitions)
            'Synthetic / ${definition.pattern} / resqlite',
        ];

        final catalog = resolveCuratedMetrics(syntheticKeys);
        expect(catalog.tracked, hasLength(curatedMetricDefinitions.length));

        final grouped = <String>{};
        for (final chartId in experimentChartIds) {
          expect(catalog.chartGroups, contains(chartId));
          for (final key in catalog.chartGroups[chartId]!) {
            expect(grouped.add(key), isTrue, reason: 'metric assigned twice');
            expect(catalog.metricDisplay[key], isNotNull);
          }
        }

        expect(grouped, equals(catalog.tracked.toSet()));
      },
    );
  });
}
