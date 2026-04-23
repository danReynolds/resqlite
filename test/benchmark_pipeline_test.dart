library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../benchmark/generate_devices.dart' as generate_devices;
import '../benchmark/generate_history.dart' as generate_history;
import '../benchmark/shared/release_artifact.dart';
import '../benchmark/shared/stats.dart';
import '../benchmark/shared/workload_registry.dart';

void main() {
  group('release sidecar summary artifact', () {
    test('stores compact repeat aggregates and benchmark summary', () {
      final artifact = buildReleaseRunArtifact(
        label: 'fixture',
        repeatCount: 3,
        markdown: _fixtureBenchmarkMarkdown,
        aggregates: {
          'Select → Maps / 1000 rows / resqlite select()': AggregateStats([
            1.10,
            1.20,
            1.30,
          ]),
        },
        environment: const {'runtime': 'dart-vm'},
        generatedAt: '2026-04-23T00:00:00.000Z',
      );

      expect(artifact['schemaVersion'], equals(3));
      expect(artifact.containsKey('benchmarks'), isFalse);
      expect(artifact.containsKey('benchmarkSummary'), isTrue);

      final repeatAggregates =
          artifact['repeatAggregates'] as Map<String, Object?>;
      final aggregate = repeatAggregates.values.single as Map<String, Object?>;
      expect(
        aggregate.keys,
        equals({
          'median',
          'madPct',
          'stability',
          'comparisonThresholdPct',
        }),
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
        markdown: _fixtureBenchmarkMarkdown,
        aggregates: const {},
        environment: const {'runtime': 'dart-vm'},
        generatedAt: '2026-04-23T00:00:00.000Z',
      );
      File(markdownFile.path.replaceFirst('.md', '.json')).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(sidecar),
      );

      final output = generate_devices.buildDevicesData(
        hardwareResultsMarkdown: _fixtureHardwareResultsMarkdown(
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
        )..writeAsStringSync(_fixtureBenchmarkMarkdown);

        final sidecar = buildReleaseRunArtifact(
          label: 'fixture',
          repeatCount: 3,
          markdown: _fixtureBenchmarkMarkdown,
          aggregates: const {},
          environment: const {'runtime': 'dart-vm'},
          generatedAt: '2026-04-23T00:00:00.000Z',
        );
        sidecar.remove('benchmarkSummary');
        File(markdownFile.path.replaceFirst('.md', '.json')).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(sidecar),
        );

        final output = generate_devices.buildDevicesData(
          hardwareResultsMarkdown: _fixtureHardwareResultsMarkdown(
            resultFile: '2026-04-23T11-08-40-fixture.md',
          ),
          resultsDir: resultsDir,
          generatedAt: '2026-04-23T00:00:00.000Z',
        );

        final devices =
            output['devices'] as List<Map<String, Object?>>;
        expect(devices, hasLength(1));
        expect(devices.single['environment'], isNotNull);

        final benchmarks =
            devices.single['benchmarks'] as List<Map<String, Object?>>;
        expect(benchmarks, isNotEmpty);
        expect(benchmarks.single['title'], equals('Select → Maps'));
      },
    );
  });

  group('generate_history', () {
    test('prefers sidecar metrics and carries environment into history', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'resqlite_history_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final resultsDir = Directory('${tempDir.path}/results')..createSync();
      final experimentsDir = Directory('${tempDir.path}/experiments')
        ..createSync();

      final markdownFile = File(
        '${resultsDir.path}/2026-04-23T11-08-40-fixture.md',
      )..writeAsStringSync(_fixtureBenchmarkMarkdown);

      final sidecar = buildReleaseRunArtifact(
        label: 'fixture',
        repeatCount: 3,
        markdown: _fixtureBenchmarkMarkdown,
        aggregates: const {},
        environment: const {'runtime': 'dart-vm', 'gitSha': 'deadbeef'},
        generatedAt: '2026-04-23T00:00:00.000Z',
      );
      (sidecar['metrics'] as Map<String, Object?>)
          ['Select → Maps / 1000 rows / resqlite select()'] = 9.99;
      File(markdownFile.path.replaceFirst('.md', '.json')).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(sidecar),
      );

      File('${experimentsDir.path}/README.md').writeAsStringSync(
        '''
## Accepted

| ID | Title | Impact | Commit |
|---|---|---|---|
| [083](083-test.md) | Test Experiment | Synthetic summary | [`deadbee`](https://example.com) |
''',
      );

      File('${experimentsDir.path}/083-test.md').writeAsStringSync(
        '''
**Date:** 2026-04-23
**Commit:** [`deadbee`](https://example.com)

## Problem
Synthetic benchmark fixture.

## Hypothesis
Structured sidecars should win over markdown parsing.

## Primary Metrics
- `1000 rows / resqlite select()`

## Decision
Accepted for testing.
''',
      );

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
      expect((run['environment'] as Map<String, Object?>)['runtime'], 'dart-vm');

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
    });
  });

  group('workload registry', () {
    test('curated definitions resolve cleanly and chart groups stay coherent', () {
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
    });
  });
}

String _fixtureHardwareResultsMarkdown({required String resultFile}) => '''
## Devices

| Device | CPU | OS | Dart | Date | By | Result File |
|---|---|---|---|---|---|---|
| Fixture Mac | M1 | macOS 26.2 | 3.11 | 2026-04-23 | @tester | $resultFile |
''';

const _fixtureBenchmarkMarkdown = '''
# resqlite Benchmark Results

## Select → Maps

### 1000 rows

| Library | Wall med | Wall p90 | Main med | Main p90 |
|---|---|---|---|---|
| resqlite select() | 1.23 | 1.50 | 0.12 | 0.15 |
| sqlite3 select() | 2.34 | 2.80 | 2.34 | 2.80 |
''';
