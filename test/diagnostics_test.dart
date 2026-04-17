/// Tests for `Database.diagnostics()` — the per-connection diagnostic
/// snapshot used by benchmark workloads and mobile memory reporting.
///
/// Verifies behavior only, not specific byte values (those are
/// implementation- and platform-dependent). The invariants covered:
///
///   1. All byte fields are non-negative on a fresh db.
///   2. WAL sidecar size grows after writes.
///   3. Schema bytes grow after adding tables + first queries.
///   4. `readersBusyAtSnapshot` is false between operations.
///   5. `walBytes` reports zero on a fresh db with no writes.
///
/// Page-cache-bytes and stmt-bytes growth are not asserted — both are
/// very sensitive to VM timing and pcache behavior, and assertions
/// tend to flake. Callers of `diagnostics()` should treat those
/// counters as informational rather than load-bearing.
library;

import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

void main() {
  group('Database.diagnostics', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('diag_test_');
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

    test('returns a snapshot with non-negative counters on a fresh db',
        () async {
      final d = await db.diagnostics();
      expect(d.sqlitePageCacheBytes, greaterThanOrEqualTo(0));
      expect(d.sqliteSchemaBytes, greaterThanOrEqualTo(0));
      expect(d.sqliteStmtBytes, greaterThanOrEqualTo(0));
      expect(d.walBytes, greaterThanOrEqualTo(0));
      expect(d.readersBusyAtSnapshot, isFalse);
      expect(d.sqliteTotalBytes,
          equals(d.sqlitePageCacheBytes +
              d.sqliteSchemaBytes +
              d.sqliteStmtBytes));
    });

    test('walBytes grows after writes in WAL mode', () async {
      final before = await db.diagnostics();
      await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, v INTEGER)');
      await db.executeBatch('INSERT INTO t(v) VALUES (?)',
          [for (var i = 0; i < 200; i++) [i]]);
      final after = await db.diagnostics();
      expect(after.walBytes, greaterThan(before.walBytes),
          reason: 'WAL sidecar should grow after a batch of inserts');
    });

    test('schemaBytes grows after adding tables', () async {
      final before = await db.diagnostics();
      await db.execute('CREATE TABLE a(id INTEGER PRIMARY KEY, name TEXT)');
      await db.execute('CREATE INDEX a_name ON a(name)');
      await db.execute('CREATE TABLE b(id INTEGER PRIMARY KEY, v REAL)');
      // Run a query so the readers load the schema into their parse cache.
      await db.select('SELECT * FROM a');
      await db.select('SELECT * FROM b');
      final after = await db.diagnostics();
      expect(after.sqliteSchemaBytes, greaterThan(before.sqliteSchemaBytes),
          reason: 'Schema memory should grow after DDL + first queries');
    });

    test('readersBusyAtSnapshot is false between operations', () async {
      await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY)');
      // Await each op before snapshotting — no concurrent reader work.
      await db.select('SELECT * FROM t');
      final d = await db.diagnostics();
      expect(d.readersBusyAtSnapshot, isFalse);
    });

    test('toString includes all counter fields', () async {
      final d = await db.diagnostics();
      final s = d.toString();
      expect(s, contains('pageCache'));
      expect(s, contains('schema'));
      expect(s, contains('stmt'));
      expect(s, contains('wal'));
    });

    test('walBytes is zero on a fresh db with no writes', () async {
      // Fresh db — no writes have committed yet, so the -wal sidecar
      // either doesn't exist or is empty. Either way, diagnostics
      // reports 0 without throwing.
      final d = await db.diagnostics();
      expect(d.walBytes, equals(0));
    });
  });
}
