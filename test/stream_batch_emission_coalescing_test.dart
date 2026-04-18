/// Regression guard for experiment 079: batch-scoped stream emission
/// coalescing via the writer-busy probe.
///
/// When a sustained write burst happens while a stream is active, our
/// reactive engine should emit ~once at the end (the final settled
/// state) rather than once per write. This test exercises the Sync
/// Burst pattern at miniature scale: a stream on `SELECT COUNT(*)`
/// while the caller runs 20 serial `executeBatch` calls. Pre-079 this
/// emitted ~20 times; post-079 it emits 1–2 times.
///
/// The test also verifies the correctness invariant: every emission
/// sequence must converge to the correct final state. An overly
/// aggressive coalescing that dropped the *final* emission would
/// break the stream contract.
library;

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

void main() {
  group('Batch emission coalescing (exp 079)', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_079_');
      db = await Database.open('${tempDir.path}/test.db');
      await db.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, v INTEGER NOT NULL)',
      );
    });

    tearDown(() async {
      await db.close();
      await tempDir.delete(recursive: true);
    });

    test('serial batches emit far fewer than once per batch', () async {
      const batchCount = 20;
      const rowsPerBatch = 100;

      final emissions = <int>[];
      final stream = db.stream('SELECT COUNT(*) AS c FROM items');
      final sub = stream.listen((rows) {
        emissions.add(rows.first['c']! as int);
      });

      // Wait for initial empty emission.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions, equals([0]),
          reason: 'initial emission should report empty table');
      emissions.clear();

      for (var b = 0; b < batchCount; b++) {
        final rows = [
          for (var i = 0; i < rowsPerBatch; i++)
            [b * rowsPerBatch + i + 1],
        ];
        await db.executeBatch('INSERT INTO items(v) VALUES (?)', rows);
      }

      // Let any trailing emission settle.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await sub.cancel();

      // Correctness: the LAST emission (if any) must reflect the final
      // row count. The user's contract is "eventually consistent after
      // writes settle" — coalescing must not drop the final update.
      expect(emissions.isNotEmpty, isTrue,
          reason: 'final emission must not be dropped');
      expect(emissions.last, equals(batchCount * rowsPerBatch),
          reason: 'final emission must reflect total rows written');

      // Coalescing: emissions should be far fewer than the batch count.
      // Pre-079 this was ~batchCount; post-079 it's 1–3. Budget is
      // deliberately loose (≤ 5) so platform/timing variance doesn't
      // flake the test — a regression to "~20 emits" would clearly fail.
      expect(
        emissions.length,
        lessThanOrEqualTo(5),
        reason: 'expected ≤ 5 emissions across $batchCount batches '
            '(exp 079 target); got ${emissions.length}',
      );
    });

    test('single-write isolated from burst still emits', () async {
      // When there's NO ongoing write burst, a single executeBatch
      // should produce an emission. This guards against the busy-probe
      // accidentally suppressing isolated emissions.
      final emissions = <int>[];
      final stream = db.stream('SELECT COUNT(*) AS c FROM items');
      final sub = stream.listen((rows) {
        emissions.add(rows.first['c']! as int);
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions, equals([0]));

      await db.executeBatch('INSERT INTO items(v) VALUES (?)', [
        [1],
        [2],
      ]);

      // Give plenty of time for the emission after the writer is idle.
      // The writer is NOT busy when the re-query completes, so the
      // emission should fire normally.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await sub.cancel();

      expect(emissions, contains(2),
          reason: 'single isolated batch must still emit');
    });
  });
}
