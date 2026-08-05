/// [EXP-262](../experiments/262-release-scenario-persistence.md): a release run
/// that dies mid-repeat must leave behind the scenarios that completed, marked
/// clearly enough that a trend cannot mistake it for a whole run — and a memory
/// regression must be something a caller can fail on, not just something the
/// table mentions.
import 'package:test/test.dart';

import '../benchmark/shared/release_artifact.dart';
import '../benchmark/shared/release_reporting.dart';
import '../benchmark/shared/stats.dart';

/// A minimal `## Memory` section in the shape `extractMemoryMedians` parses.
String _memorySection(Map<String, double> byLabel) {
  final buf = StringBuffer()
    ..writeln('## Memory')
    ..writeln()
    ..writeln('### Select 10k rows → Maps')
    ..writeln()
    ..writeln(
      '| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |',
    )
    ..writeln('|---|---|---|---|---|');
  byLabel.forEach((label, mb) {
    // Column order matters: CI is `low..high`, MDE is `±N.NN`.
    buf.writeln(
      '| $label | ${mb.toStringAsFixed(2)} | ${(mb + 1).toStringAsFixed(2)} '
      '| ${(mb - 0.1).toStringAsFixed(2)}..${(mb + 0.1).toStringAsFixed(2)} '
      '| ±0.20 |',
    );
  });
  return (buf..writeln()).toString();
}

void main() {
  group('partial run artifacts', () {
    Map<String, Object?> artifact({
      required int completed,
      required int total,
      int repeatCount = 0,
    }) => buildReleaseRunArtifact(
      label: 'exp262',
      repeatCount: repeatCount,
      markdown: _memorySection({'resqlite select()': 1.0}),
      aggregates: <String, AggregateStats>{},
      scenariosCompleted: completed,
      scenarioTotal: total,
    );

    test('a run that stopped mid-repeat is marked partial', () {
      final a = artifact(completed: 9, total: 16);
      expect(a['scenariosCompleted'], 9);
      expect(a['scenarioTotal'], 16);
      expect(a['partial'], isTrue);
    });

    test('a completed repeat is not marked partial', () {
      final a = artifact(completed: 16, total: 16, repeatCount: 1);
      expect(a['partial'], isNull, reason: 'absent means "whole run"');
      expect(a['scenariosCompleted'], 16);
    });

    test('the in-flight repeat never inflates repeatCount', () {
      // What the runner persists mid-repeat: repeats that already finished,
      // which is 0 while the first one is still running. A trend reading
      // repeatCount must not see a sample that has not been collected.
      final a = artifact(completed: 9, total: 16);
      expect(a['repeatCount'], 0);
    });

    test('scenario counts are omitted entirely when not supplied', () {
      final a = buildReleaseRunArtifact(
        label: 'legacy',
        repeatCount: 5,
        markdown: _memorySection({'resqlite select()': 1.0}),
        aggregates: <String, AggregateStats>{},
      );
      expect(a.containsKey('scenariosCompleted'), isFalse);
      expect(a.containsKey('partial'), isFalse);
    });
  });

  group('memory acceptance criteria', () {
    test('a rise beyond the threshold is a gate-able regression', () {
      final result = compareMemory(
        _memorySection({'resqlite select()': 12.0}),
        _memorySection({'resqlite select()': 4.0}),
      );
      expect(result.hasRegression, isTrue);
      expect(result.regressions, 1);
      expect(result.regressedBenchmarks.single, contains('+8.00 MB'));
      expect(result.markdown, contains('Regression'));
    });

    test('a fall is a win, and never trips the gate', () {
      final result = compareMemory(
        _memorySection({'resqlite select()': 4.0}),
        _memorySection({'resqlite select()': 12.0}),
      );
      expect(result.hasRegression, isFalse);
      expect(result.wins, 1);
    });

    test('a move inside the threshold is neutral', () {
      final result = compareMemory(
        _memorySection({'resqlite select()': 4.1}),
        _memorySection({'resqlite select()': 4.0}),
      );
      expect(result.hasRegression, isFalse);
      expect(result.neutral, 1);
    });

    test('no memory section on either side is not a regression', () {
      final result = compareMemory('# Results\n', '# Results\n');
      expect(result.markdown, isEmpty);
      expect(result.hasRegression, isFalse);
    });

    test('a missing baseline cannot fail the gate', () {
      final result = compareMemory(
        _memorySection({'resqlite select()': 99.0}),
        '# Results\n',
      );
      expect(result.hasRegression, isFalse);
      expect(result.markdown, contains('baseline unavailable'));
    });

    group('shouldFailOnMemory', () {
      MemoryComparison regressing() => compareMemory(
        _memorySection({'resqlite select()': 12.0}),
        _memorySection({'resqlite select()': 4.0}),
      );

      test('fails only when the flag is passed and a regression exists', () {
        expect(
          shouldFailOnMemory(
            failOnMemoryRegression: true,
            comparison: regressing(),
          ),
          isTrue,
        );
      });

      test('a regression without the flag does not fail the run', () {
        expect(
          shouldFailOnMemory(
            failOnMemoryRegression: false,
            comparison: regressing(),
          ),
          isFalse,
        );
      });

      test('the flag alone does not fail a clean run', () {
        expect(
          shouldFailOnMemory(
            failOnMemoryRegression: true,
            comparison: compareMemory(
              _memorySection({'resqlite select()': 4.0}),
              _memorySection({'resqlite select()': 4.0}),
            ),
          ),
          isFalse,
        );
      });

      test('no comparison at all cannot fail the run', () {
        expect(
          shouldFailOnMemory(failOnMemoryRegression: true, comparison: null),
          isFalse,
        );
      });
    });

    test('the render-only wrapper still returns the same table', () {
      const current = 'x';
      expect(
        generateMemoryComparison(current, current),
        compareMemory(current, current).markdown,
      );
    });
  });
}
