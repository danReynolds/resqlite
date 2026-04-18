/// Tests the [WorkloadMeta] versioning convention used by scenario
/// benchmarks. Per METHODOLOGY.md § Workload versioning, workloads
/// carry an explicit version that appears in both markdown section
/// headings and metric keys so the dashboard doesn't silently conflate
/// data across breaking op-mix changes.
library;

import 'package:test/test.dart';

import '../benchmark/shared/workload.dart';

void main() {
  group('WorkloadMeta', () {
    test('sectionHeading and metricKey include the version', () {
      const meta = WorkloadMeta(
        slug: 'chat_sim',
        version: 1,
        title: 'Chat Sim',
        description: 'Mixed R/W workload with join queries.',
      );
      expect(meta.sectionHeading, equals('Chat Sim (v1)'));
      expect(meta.metricKey, equals('chat_sim_v1'));
    });

    test('bumping the version produces a distinct key', () {
      const v1 = WorkloadMeta(
        slug: 'chat_sim',
        version: 1,
        title: 'Chat Sim',
        description: 'Original mix.',
      );
      const v2 = WorkloadMeta(
        slug: 'chat_sim',
        version: 2,
        title: 'Chat Sim',
        description: 'Adds a 3rd join.',
      );
      expect(v1.metricKey, isNot(equals(v2.metricKey)));
      expect(v1.sectionHeading, isNot(equals(v2.sectionHeading)));
    });

    test('asserts on invalid version', () {
      expect(
        () => WorkloadMeta(
          slug: 'bad',
          version: 0,
          title: 'Bad',
          description: 'zero is not a valid starting version',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('asserts on empty slug', () {
      expect(
        () => WorkloadMeta(
          slug: '',
          version: 1,
          title: 'Bad',
          description: 'needs a slug',
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
