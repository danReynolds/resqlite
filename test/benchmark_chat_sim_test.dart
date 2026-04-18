/// Unit test for the A5 chat sim workload.
///
/// Per METHODOLOGY.md § Adding a workload — Definition of Done:
/// asserts behavior (schema, op-type coverage, peer set), not timing.
library;

import 'package:test/test.dart';

import '../benchmark/suites/chat_sim.dart';

void main() {
  group('Chat Sim workload (A5)', () {
    test('workload meta declares expected identity', () {
      expect(chatSimMeta.slug, equals('chat_sim'));
      expect(chatSimMeta.version, equals(1));
      expect(chatSimMeta.sectionHeading, equals('Chat Sim (v1)'));
      expect(chatSimMeta.metricKey, equals('chat_sim_v1'));
    });

    test('runs end-to-end and emits all four op-type subsections',
        () async {
      final markdown = await runChatSimBenchmark();

      expect(markdown, contains('## Chat Sim (v1)'));

      // Every op type must appear as a subsection so per-op timings
      // are parsed as distinct metric keys.
      expect(markdown, contains('### Insert message'));
      expect(markdown, contains('### Update conversation'));
      expect(markdown, contains('### Fetch last-20 messages (JOIN users)'));
      expect(markdown, contains('### Fetch user by PK'));

      // All four peers must be represented. sqlite3 is included here
      // because chat sim doesn't need streams.
      expect(markdown, contains('| resqlite '));
      expect(markdown, contains('| sqlite3 '));
      expect(markdown, contains('| sqlite_async '));
      expect(markdown, contains('| drift '));

      // Standard 5-column header appears in each subsection.
      expect(
        markdown,
        contains('| Library | Wall med (ms) | Wall p90 (ms) | '
            'Main med (ms) | Main p90 (ms) |'),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
