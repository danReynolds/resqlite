import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

const _encryptionKey =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _crossingRows = 400;
const _closeRaceRows = 1000;
const _payloadBytes = 8192;
final _payload = 'x' * _payloadBytes;

void main() {
  group('asynchronous checkpoint worker', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'resqlite_checkpoint_worker_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } on PathNotFoundException {
          // The database close path may already have released and removed a
          // platform-specific sidecar between exists() and delete().
        }
      }
    });

    test('threshold-crossing batch checkpoints and remains usable', () async {
      final db = await Database.open('${tempDir.path}/threshold.db');
      try {
        await _createEventsTable(db);
        await _writeBatch(db, _crossingRows);

        final wal = await _waitForCheckpointedWal(db);
        expect(wal.log, greaterThanOrEqualTo(500));
        expect(wal.checkpointed, greaterThanOrEqualTo(wal.log));

        await db.execute(_insertSql, [_payload, _crossingRows]);
        final rows = await db.select('SELECT count(*) AS count FROM events');
        expect(rows.single['count'], _crossingRows + 1);
      } finally {
        await db.close();
      }
    });

    test(
      'close drains a threshold-crossing checkpoint without hanging',
      () async {
        final db = await Database.open('${tempDir.path}/close.db');
        try {
          await _createEventsTable(db);
          // This commit is deliberately larger than the minimum crossing shape,
          // increasing the chance that close overlaps the PASSIVE worker while
          // keeping the test bounded to a small, fixed data set.
          await _writeBatch(db, _closeRaceRows);

          await db.close().timeout(const Duration(seconds: 5));
        } finally {
          // close() is idempotent, including after the timed call above wins.
          await db.close().timeout(const Duration(seconds: 5));
        }
      },
    );

    test(
      'encrypted database checkpoint connection uses the same key',
      () async {
        final db = await Database.open(
          '${tempDir.path}/encrypted.db',
          encryptionKey: _encryptionKey,
        );
        try {
          await _createEventsTable(db);
          await _writeBatch(db, _crossingRows);

          // A checkpoint connection opened without the writer's key cannot
          // backfill this encrypted WAL. Reaching a fully checkpointed snapshot
          // is the focused compatibility assertion; the broader encryption
          // behavior remains covered by encryption_test.dart.
          final wal = await _waitForCheckpointedWal(db);
          expect(wal.log, greaterThanOrEqualTo(500));
          expect(wal.checkpointed, greaterThanOrEqualTo(wal.log));

          final rows = await db.select('SELECT count(*) AS count FROM events');
          expect(rows.single['count'], _crossingRows);
        } finally {
          await db.close();
        }
      },
    );
  });
}

Future<void> _createEventsTable(Database db) => db.execute('''
CREATE TABLE events(
  id INTEGER PRIMARY KEY,
  payload TEXT NOT NULL,
  sequence INTEGER NOT NULL
)
''');

const _insertSql = 'INSERT INTO events(payload, sequence) VALUES (?, ?)';

Future<void> _writeBatch(Database db, int rowCount) =>
    db.executeBatch(_insertSql, [
      for (var i = 0; i < rowCount; i++) [_payload, i],
    ]);

Future<_WalState> _waitForCheckpointedWal(Database db) async {
  const timeout = Duration(seconds: 5);
  final stopwatch = Stopwatch()..start();
  var last = const _WalState(busy: -1, log: -1, checkpointed: -1);

  while (stopwatch.elapsed < timeout) {
    last = await _readWalState(db);
    if (last.log >= 500 && last.checkpointed >= last.log) return last;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  fail(
    'WAL did not finish checkpointing within $timeout: '
    'busy=${last.busy}, log=${last.log}, '
    'checkpointed=${last.checkpointed}',
  );
}

Future<_WalState> _readWalState(Database db) async {
  // SQLITE_CHECKPOINT_NOOP is observational in the vendored SQLite 3.51.3;
  // unlike PASSIVE, this probe does not perform the work under test.
  final rows = await db.select('PRAGMA wal_checkpoint(NOOP)');
  final row = rows.single;
  return _WalState(
    busy: row['busy'] as int,
    log: row['log'] as int,
    checkpointed: row['checkpointed'] as int,
  );
}

final class _WalState {
  const _WalState({
    required this.busy,
    required this.log,
    required this.checkpointed,
  });

  final int busy;
  final int log;
  final int checkpointed;
}
