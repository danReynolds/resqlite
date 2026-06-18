/// Unit test for the SQLite diagnostics benchmark section.
///
/// Asserts structure and parseability, not exact KiB values — those are
/// intentionally platform- and allocator-dependent.
library;

import 'package:test/test.dart';

import '../benchmark/suites/sqlite_diagnostics.dart';

void main() {
  group('SQLite Diagnostics benchmark', () {
    test(
      'runs end-to-end and emits the expected subsections',
      () async {
        final markdown = await runSqliteDiagnosticsBenchmark();

        expect(markdown, contains('## SQLite Diagnostics'));
        expect(
          markdown,
          contains(
            '### Warm read working set (20000 rows + 2000 point lookups)',
          ),
        );
        expect(
          markdown,
          contains('### Statement cache footprint (48 distinct SELECT texts)'),
        );
        expect(
          markdown,
          contains('### WAL after write burst (1000 inserted rows)'),
        );
        expect(
          markdown,
          contains(
            '### JSON buffer reclaim (8 large selectBytes + 64 small settles)',
          ),
        );
        expect(
          markdown,
          contains(
            '| Library | SQLite total (KiB) | Page cache (KiB) | '
            'Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | '
            'Readers busy |',
          ),
        );
        expect(markdown, contains('| resqlite |'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
