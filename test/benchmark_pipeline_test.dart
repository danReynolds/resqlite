library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

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
