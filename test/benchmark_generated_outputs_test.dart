library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../benchmark/generate_devices.dart' as generate_devices;
import '../benchmark/generate_history.dart' as generate_history;
import '../benchmark/shared/release_artifact.dart';
import 'benchmark_pipeline_fixtures.dart';

void main() {
  test('history writer skips timestamp-only churn', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'resqlite_history_writer_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final outputFile = File('${tempDir.path}/history.json');
    const encoder = JsonEncoder.withIndent('  ');
    final current = <String, Object?>{
      'generated': '2026-04-23T00:00:00.000Z',
      'runs': const [],
      'experiments': const [],
      'tracked': const [],
    };
    await outputFile.writeAsString(encoder.convert(current));

    final timestampOnlyChange = <String, Object?>{
      ...current,
      'generated': '2026-06-08T00:00:00.000Z',
    };
    final wroteTimestampOnly = await generate_history.writeHistoryData(
      outputFile,
      timestampOnlyChange,
    );

    expect(wroteTimestampOnly, isFalse);
    expect(jsonDecode(await outputFile.readAsString()), current);

    final payloadChange = <String, Object?>{
      ...timestampOnlyChange,
      'tracked': const ['metric'],
    };
    final wrotePayloadChange = await generate_history.writeHistoryData(
      outputFile,
      payloadChange,
    );

    expect(wrotePayloadChange, isTrue);
    expect(jsonDecode(await outputFile.readAsString()), payloadChange);
  });

  test('generated devices and history outputs match golden fixtures', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'resqlite_benchmark_golden_',
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
    File(
      markdownFile.path.replaceFirst('.md', '.json'),
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(sidecar));

    File(
      '${experimentsDir.path}/README.md',
    ).writeAsStringSync(fixtureExperimentsReadmeMarkdown);
    File(
      '${experimentsDir.path}/083-test.md',
    ).writeAsStringSync(fixtureExperimentMarkdown);

    final devicesOutput = generate_devices.buildDevicesData(
      hardwareResultsMarkdown: fixtureHardwareResultsMarkdown(
        resultFile: '2026-04-23T11-08-40-fixture.md',
      ),
      resultsDir: resultsDir,
      generatedAt: '2026-04-23T00:00:00.000Z',
    );

    final historyOutput = generate_history.buildHistoryData(
      resultsDir: resultsDir,
      experimentsDir: experimentsDir,
      generatedAt: '2026-04-23T00:00:00.000Z',
    );

    final devicesGolden = File(
      'test/fixtures/benchmark_pipeline/devices_golden.json',
    ).readAsStringSync();
    final historyGolden = File(
      'test/fixtures/benchmark_pipeline/history_golden.json',
    ).readAsStringSync();

    expect(
      const JsonEncoder.withIndent('  ').convert(devicesOutput),
      devicesGolden.trim(),
    );
    expect(
      const JsonEncoder.withIndent('  ').convert(historyOutput),
      historyGolden.trim(),
    );
  });
}
