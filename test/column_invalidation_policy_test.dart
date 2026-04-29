// Direct unit tests on `ColumnInvalidationPolicy.affects`.
//
// These are the load-bearing proof of the column-level dispatch
// elision policy. Black-box "stream emits / does not emit" cannot
// distinguish:
//   * elision skipped the re-query (the optimization worked), from
//   * re-query happened but exp 075's hash short-circuit suppressed
//     the emission anyway (no observable difference to the subscriber).
//
// Direct tests on the policy helper prove the dispatch-side decision
// regardless of result-change-detection confounds.
import 'package:resqlite/src/dependency_tracking.dart'
    show ColumnDependencies, ColumnDependencyMap;
import 'package:resqlite/src/stream_engine.dart';
import 'package:test/test.dart';

StreamEntry _entryWith({
  required Set<String> dependencies,
  required ColumnDependencyMap columnDependencies,
}) {
  final entry = StreamEntry(key: 0, sql: '<unused>', params: const []);
  entry.dependencies = dependencies;
  entry.columnDependencies = columnDependencies;
  return entry;
}

void main() {
  group('ColumnInvalidationPolicy.affects', () {
    test('disjoint concrete column sets → false (elide dispatch)', () {
      final entry = _entryWith(
        dependencies: {'users'},
        columnDependencies: {
          'users': ColumnDependencies.fixed({'name'}),
        },
      );
      final result = ColumnInvalidationPolicy.affects(
        entry,
        const ['users'],
        {
          'users': ColumnDependencies.fixed({'email'}),
        },
      );
      expect(result, isFalse);
    });

    test('overlapping concrete column sets → true', () {
      final entry = _entryWith(
        dependencies: {'users'},
        columnDependencies: {
          'users': ColumnDependencies.fixed({'name', 'email'}),
        },
      );
      final result = ColumnInvalidationPolicy.affects(
        entry,
        const ['users'],
        {
          'users': ColumnDependencies.fixed({'email', 'phone'}),
        },
      );
      expect(result, isTrue);
    });

    test('writer-side wildcard for a watched table → true', () {
      final entry = _entryWith(
        dependencies: {'users'},
        columnDependencies: {
          'users': ColumnDependencies.fixed({'name'}),
        },
      );
      final result = ColumnInvalidationPolicy.affects(
        entry,
        const ['users'],
        const <String, ColumnDependencies>{'users': ColumnDependencies.all},
      );
      expect(result, isTrue);
    });

    test('reader-side wildcard for a dirty table → true', () {
      final entry = _entryWith(
        dependencies: {'users'},
        columnDependencies: const <String, ColumnDependencies>{
          'users': ColumnDependencies.all,
        },
      );
      final result = ColumnInvalidationPolicy.affects(
        entry,
        const ['users'],
        {
          'users': ColumnDependencies.fixed({'email'}),
        },
      );
      expect(result, isTrue);
    });

    test('dirty table absent from column map (table-only) → true', () {
      final entry = _entryWith(
        dependencies: {'users'},
        columnDependencies: {
          'users': ColumnDependencies.fixed({'name'}),
        },
      );
      final result = ColumnInvalidationPolicy.affects(
        entry,
        const ['users'],
        // Empty column map — the dirty table has no entry, table-only fallback.
        const <String, ColumnDependencies>{},
      );
      expect(result, isTrue);
    });

    test(
      'reader-side missing entry for the dirty table → true (degrade safely)',
      () {
        final entry = _entryWith(
          dependencies: {'users'},
          // No column entry for `users` at all — degrade safely.
          columnDependencies: const <String, ColumnDependencies>{},
        );
        final result = ColumnInvalidationPolicy.affects(
          entry,
          const ['users'],
          {
            'users': ColumnDependencies.fixed({'email'}),
          },
        );
        expect(result, isTrue);
      },
    );

    test('dirty table not in entry deps → continue (false)', () {
      // Entry watches `users`; writer dirties `posts` only.
      final entry = _entryWith(
        dependencies: {'users'},
        columnDependencies: {
          'users': ColumnDependencies.fixed({'name'}),
        },
      );
      final result = ColumnInvalidationPolicy.affects(
        entry,
        const ['posts'],
        {
          'posts': ColumnDependencies.fixed({'title'}),
        },
      );
      expect(result, isFalse);
    });

    test(
      'mixed dirty list — one disjoint, one overlapping → true (loops, returns on first hit)',
      () {
        final entry = _entryWith(
          dependencies: {'users', 'posts'},
          columnDependencies: {
            'users': ColumnDependencies.fixed({'name'}),
            'posts': ColumnDependencies.fixed({'title'}),
          },
        );
        final result = ColumnInvalidationPolicy.affects(
          entry,
          const ['users', 'posts'],
          {
            // users disjoint, posts overlapping
            'users': ColumnDependencies.fixed({'email'}),
            'posts': ColumnDependencies.fixed({'title', 'body'}),
          },
        );
        expect(result, isTrue);
      },
    );

    test('mixed dirty list — both disjoint → false (true elision)', () {
      final entry = _entryWith(
        dependencies: {'users', 'posts'},
        columnDependencies: {
          'users': ColumnDependencies.fixed({'name'}),
          'posts': ColumnDependencies.fixed({'title'}),
        },
      );
      final result = ColumnInvalidationPolicy.affects(
        entry,
        const ['users', 'posts'],
        {
          'users': ColumnDependencies.fixed({'email'}),
          'posts': ColumnDependencies.fixed({'body'}),
        },
      );
      expect(result, isFalse);
    });
  });
}
