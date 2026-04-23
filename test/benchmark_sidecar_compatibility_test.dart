library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../benchmark/generate_devices.dart' as generate_devices;
import '../benchmark/shared/release_artifact.dart';
import 'benchmark_pipeline_fixtures.dart';

void main() {
  group('legacy sidecar compatibility', () {
    test('artifactBenchmarks reads legacy embedded benchmarks payload', () {
      final legacyArtifact = <String, Object?>{
        'schemaVersion': 1,
        'kind': 'release-benchmark-run',
        'metrics': const <String, Object?>{},
        'benchmarks': [
          {
            'key': 'Select → Maps / 1000 rows',
            'title': 'Select → Maps',
            'subtitle': '1000 rows',
            'entries': [
              {
                'library': 'resqlite select()',
                'values': [1.23, 1.50, 0.12, 0.15],
              },
            ],
          },
        ],
      };

      final benchmarks = artifactBenchmarks(legacyArtifact);
      expect(benchmarks, isNotNull);
      expect(benchmarks, hasLength(1));
      expect(benchmarks!.single['title'], equals('Select → Maps'));
    });

    test(
      'artifactBenchmarks falls back to legacy benchmarks when benchmarkSummary is empty',
      () {
        final artifact = <String, Object?>{
          'schemaVersion': 3,
          'kind': 'release-benchmark-run',
          'metrics': const <String, Object?>{},
          'benchmarkSummary': const {
            'sections': [],
          },
          'benchmarks': [
            {
              'key': 'Select → Maps / 1000 rows',
              'title': 'Select → Maps',
              'subtitle': '1000 rows',
              'entries': [
                {
                  'library': 'resqlite select()',
                  'values': [1.23, 1.50, 0.12, 0.15],
                },
              ],
            },
          ],
        };

        final benchmarks = artifactBenchmarks(artifact);
        expect(benchmarks, isNotNull);
        expect(benchmarks, hasLength(1));
        expect(benchmarks!.single['title'], equals('Select → Maps'));
      },
    );

    test(
      'generate_devices uses legacy sidecar benchmarks without markdown tables',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'resqlite_legacy_sidecar_test_',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final resultsDir = Directory('${tempDir.path}/results')..createSync();
        final markdownFile = File(
          '${resultsDir.path}/2026-04-23T11-08-40-fixture.md',
        )..writeAsStringSync('# no benchmark tables\n');

        final legacyArtifact = <String, Object?>{
          'schemaVersion': 1,
          'kind': 'release-benchmark-run',
          'generatedAt': '2026-04-23T00:00:00.000Z',
          'label': 'fixture',
          'repeatCount': 3,
          'environment': const {
            'runtime': 'dart-vm',
            'gitSha': 'deadbeef',
          },
          'metrics': const {
            'Select → Maps / 1000 rows / resqlite select()': 1.23,
            'Select → Maps / 1000 rows / resqlite select() [main]': 0.12,
          },
          'benchmarks': [
            {
              'key': 'Select → Maps / 1000 rows',
              'title': 'Select → Maps',
              'subtitle': '1000 rows',
              'entries': [
                {
                  'library': 'resqlite select()',
                  'values': [1.23, 1.50, 0.12, 0.15],
                },
                {
                  'library': 'sqlite3 select()',
                  'values': [2.34, 2.80, 2.34, 2.80],
                },
              ],
            },
          ],
        };

        File(markdownFile.path.replaceFirst('.md', '.json')).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(legacyArtifact),
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
        expect(
          (devices.single['environment'] as Map<String, Object?>)['runtime'],
          'dart-vm',
        );
        final benchmarks =
            devices.single['benchmarks'] as List<Map<String, Object?>>;
        expect(benchmarks, hasLength(1));
        expect(benchmarks.single['title'], equals('Select → Maps'));
      },
    );
  });
}
