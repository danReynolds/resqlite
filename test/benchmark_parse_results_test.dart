library;

import 'package:test/test.dart';

import '../benchmark/shared/parse_results.dart';

void main() {
  group('benchmark/shared/parse_results.dart', () {
    test('SQLite Diagnostics is excluded from timing metrics', () {
      const markdown = '''
# resqlite Benchmark Results

## SQLite Diagnostics

### Warm read working set

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 1024.0 | 900.0 | 80.0 | 44.0 | 512.0 | 0 |
''';

      final timing = extractResqliteMedians(markdown);
      expect(timing, isEmpty);
    });

    test('SQLite Diagnostics metrics parse into their own namespace', () {
      const markdown = '''
# resqlite Benchmark Results

## SQLite Diagnostics

### Warm read working set

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 1024.0 | 900.0 | 80.0 | 44.0 | 512.0 | 0 |
''';

      final diagnostics = extractSqliteDiagnosticsMedians(markdown);
      final metric =
          diagnostics['SQLite Diagnostics / Warm read working set / resqlite'];
      expect(metric, isNotNull);
      expect(metric!.sqliteTotalKiB, equals(1024.0));
      expect(metric.pageCacheKiB, equals(900.0));
      expect(metric.schemaKiB, equals(80.0));
      expect(metric.stmtKiB, equals(44.0));
      expect(metric.walKiB, equals(512.0));
      expect(metric.jsonBufKiB, isNull);
      expect(metric.readersBusy, equals(0));
    });

    test('SQLite Diagnostics parses json_buf column when present', () {
      const markdown = '''
# resqlite Benchmark Results

## SQLite Diagnostics

### JSON buffer reclaim

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 2048.0 | 1900.0 | 80.0 | 44.0 | 512.0 | 64.0 | 0 |
''';

      final diagnostics = extractSqliteDiagnosticsMedians(markdown);
      final metric =
          diagnostics['SQLite Diagnostics / JSON buffer reclaim / resqlite'];
      expect(metric, isNotNull);
      expect(metric!.jsonBufKiB, equals(64.0));
      expect(metric.readersBusy, equals(0));
    });
  });

  group('parseFilenameMetadata', () {
    test('parses full local timestamp format', () {
      final meta = parseFilenameMetadata(
        '2026-04-08T15-43-57-with-streaming.md',
      );
      expect(meta, isNotNull);
      expect(meta!.date, equals('2026-04-08'));
      expect(meta.timestamp, equals('2026-04-08T15:43:57'));
      expect(meta.label, equals('with-streaming'));
    });

    test('parses UTC timestamp with trailing Z suffix', () {
      // Regression: harnesses that stamp filenames via
      // DateTime.toUtc().toIso8601String() emit a `Z` after the seconds.
      // Without accepting it, generate_history.dart silently skips the run.
      final meta = parseFilenameMetadata(
        '2026-07-14T11-25-21Z-exp229-simd-base64-neon.md',
      );
      expect(meta, isNotNull);
      expect(meta!.date, equals('2026-07-14'));
      expect(meta.timestamp, equals('2026-07-14T11:25:21'));
      expect(meta.label, equals('exp229-simd-base64-neon'));
    });

    test('strips a directory prefix before parsing', () {
      final meta = parseFilenameMetadata(
        'benchmark/results/2026-07-14T11-25-21Z-exp229-simd-base64-neon.md',
      );
      expect(meta, isNotNull);
      expect(meta!.label, equals('exp229-simd-base64-neon'));
    });

    test('parses date-only format', () {
      final meta = parseFilenameMetadata('2026-04-08-codex-main-four-way.md');
      expect(meta, isNotNull);
      expect(meta!.date, equals('2026-04-08'));
      expect(meta.timestamp, equals('2026-04-08T00:00:00'));
      expect(meta.label, equals('codex-main-four-way'));
    });

    test('returns null for non-markdown files', () {
      expect(parseFilenameMetadata('2026-07-14T11-25-21Z-exp229.json'), isNull);
    });
  });
}
