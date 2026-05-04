/// Tests for `Database.writerProfileSnapshot()` — the cross-isolate
/// writer-side counter snapshot added by exp 123.
///
/// These tests run in default (non-profile) builds, so all writer-side
/// counters stay at zero by design — the harness contract is that
/// `kProfileMode == false` tree-shakes the timing instrumentation
/// away. What is verified here is the *protocol* — the snapshot
/// round-trips cleanly across the isolate boundary, returns a well-
/// formed payload, and survives the `reset: true` flag without
/// corrupting state. The exp 123 audit harness
/// (`benchmark/profile/writer_dispatch_split_audit.dart`) is the
/// integration test for the actual counter increments.
library;

import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

void main() {
  group('Database.writerProfileSnapshot', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('writer_snap_');
      db = await Database.open('${tempDir.path}/test.db');
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } on PathNotFoundException {
          // ignore
        }
      }
    });

    test(
      'returns a well-formed snapshot with non-negative counters on a fresh db',
      () async {
        final snap = await db.writerProfileSnapshot();
        expect(snap.handlerUs, greaterThanOrEqualTo(0));
        expect(snap.handlerCount, greaterThanOrEqualTo(0));
        expect(snap.nativeUs, greaterThanOrEqualTo(0));
        expect(snap.nativeCount, greaterThanOrEqualTo(0));
        // FFI wall is always a subset of handler wall — the contract
        // holds in both kProfileMode states (zeros in default builds,
        // monotonic in profile builds).
        expect(snap.nativeUs, lessThanOrEqualTo(snap.handlerUs));
        expect(snap.nativeCount, lessThanOrEqualTo(snap.handlerCount));
      },
    );

    test(
      'snapshot round-trips through the isolate boundary while writes run',
      () async {
        // The snapshot request crosses the writer's normal request
        // protocol — interleaving it with writes verifies the request
        // type does not block, corrupt, or otherwise interfere with
        // Execute/Batch handling. Counter values themselves stay at
        // zero in default builds (kProfileMode=false), but the
        // round-trip must still succeed.
        await db.execute('CREATE TABLE t(x INTEGER)');
        final mid = await db.writerProfileSnapshot();
        await db.execute('INSERT INTO t(x) VALUES (?)', [1]);
        await db.executeBatch(
          'INSERT INTO t(x) VALUES (?)',
          [[2], [3], [4]],
        );
        final after = await db.writerProfileSnapshot();

        // Counts are monotonic across snapshots — they never decrease
        // without an explicit reset.
        expect(after.handlerCount, greaterThanOrEqualTo(mid.handlerCount));
        expect(after.nativeCount, greaterThanOrEqualTo(mid.nativeCount));
      },
    );

    test(
      'reset: true is idempotent and never returns negative state',
      () async {
        // After reset, the counters must be zero regardless of what
        // they accumulated previously. In default builds (non-profile)
        // they are always zero anyway; this test pins the contract so
        // the protocol stays correct when profile mode is enabled.
        await db.execute('CREATE TABLE t(x INTEGER)');
        await db.execute('INSERT INTO t(x) VALUES (?)', [1]);

        final reset1 = await db.writerProfileSnapshot(reset: true);
        // The reset snapshot returns the values the writer held just
        // before clearing them, so its counters can be >= 0 — they
        // never come back negative.
        expect(reset1.handlerUs, greaterThanOrEqualTo(0));
        expect(reset1.nativeUs, greaterThanOrEqualTo(0));

        // The next snapshot, taken without any intervening writes,
        // sees the freshly-zeroed state.
        final after = await db.writerProfileSnapshot();
        expect(after.handlerCount, equals(0));
        expect(after.handlerUs, equals(0));
        expect(after.nativeCount, equals(0));
        expect(after.nativeUs, equals(0));

        // Calling reset again is harmless.
        final reset2 = await db.writerProfileSnapshot(reset: true);
        expect(reset2.handlerCount, equals(0));
        expect(reset2.nativeCount, equals(0));
      },
    );
  });
}
