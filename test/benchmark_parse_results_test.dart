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
      expect(metric.readersBusy, equals(0));
    });
  });
}
