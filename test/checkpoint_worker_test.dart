import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

const _encryptionKey =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _crossingRows = 400;
const _closeRaceRows = 1000;
const _sustainedRows = 700;
const _checkpointThresholdPages = 500;
const _payloadBytes = 8192;
final _payload = 'x' * _payloadBytes;

void main() {
  group('high-water asynchronous checkpoint worker', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'resqlite_checkpoint_high_water_test_',
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
        expect(wal.log, greaterThanOrEqualTo(_checkpointThresholdPages));
        expect(wal.checkpointed, greaterThanOrEqualTo(wal.log));

        await db.execute(_insertSql, [_payload, _crossingRows]);
        final rows = await db.select('SELECT count(*) AS count FROM events');
        expect(rows.single['count'], _crossingRows + 1);
      } finally {
        await db.close();
      }
    });

    test(
      'WAL page-count drop rearms an above-threshold first commit',
      () async {
        final db = await Database.open('${tempDir.path}/reset.db');
        try {
          await _createEventsTable(db);

          // Make the first generation substantially larger than the next. Once
          // it is fully checkpointed, the next batch is itself the first commit
          // after restart: it lands above 500 pages while still exposing a page
          // count drop from the prior generation.
          await _writeBatch(db, _closeRaceRows);
          final firstEpoch = await _waitForCheckpointedWal(db);
          expect(
            firstEpoch.log,
            greaterThanOrEqualTo(_checkpointThresholdPages),
          );

          await _writeBatch(db, _crossingRows);
          final secondEpoch = await _waitForCheckpointedWal(db);
          expect(
            secondEpoch.log,
            greaterThanOrEqualTo(_checkpointThresholdPages),
          );
          expect(
            secondEpoch.checkpointed,
            greaterThanOrEqualTo(secondEpoch.log),
          );

          final rows = await db.select('SELECT count(*) AS count FROM events');
          expect(rows.single['count'], _closeRaceRows + _crossingRows);
        } finally {
          await db.close();
        }
      },
    );

    test('attached WAL retains its inline PASSIVE checkpoint path', () async {
      final db = await Database.open('${tempDir.path}/main.db');
      try {
        final attachedPath = '${tempDir.path}/attached.db';
        await db.execute('ATTACH DATABASE ? AS aux', [attachedPath]);
        // execute() routes a single row-returning PRAGMA through the write
        // result path. Use sqlite3_exec's multi-statement path so the attached
        // schema is configured on the writer connection that owns it.
        await db.execute('''
PRAGMA aux.journal_mode = WAL;
PRAGMA aux.synchronous = NORMAL;
''');
        await db.execute('''
CREATE TABLE aux.events(
  id INTEGER PRIMARY KEY,
  payload TEXT NOT NULL,
  sequence INTEGER NOT NULL
)
''');

        await db.executeBatch(
          'INSERT INTO aux.events(payload, sequence) VALUES (?, ?)',
          [
            for (var i = 0; i < _crossingRows; i++) [_payload, i],
          ],
        );

        // Reader-pool connections do not inherit runtime ATTACH statements.
        // Observe the attached database through a second normal handle; opening
        // it does not itself checkpoint the existing WAL.
        final observer = await Database.open(attachedPath);
        try {
          final wal = await _readWalState(observer);
          expect(wal.log, greaterThanOrEqualTo(_checkpointThresholdPages));
          expect(wal.checkpointed, greaterThanOrEqualTo(wal.log));
        } finally {
          await observer.close();
        }
      } finally {
        await db.close();
      }
    });

    test(
      'sustained commits leave less than one high-water delta pending',
      () async {
        final db = await Database.open('${tempDir.path}/sustained.db');
        try {
          await _createEventsTable(db);

          for (var i = 0; i < _sustainedRows; i++) {
            await db.execute(_insertSql, [_payload, i]);
          }

          final wal = await _waitForPendingBelowThreshold(db);
          expect(wal.pending, lessThan(_checkpointThresholdPages));

          final rows = await db.select('SELECT count(*) AS count FROM events');
          expect(rows.single['count'], _sustainedRows);
        } finally {
          await db.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

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
          expect(wal.log, greaterThanOrEqualTo(_checkpointThresholdPages));
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

Future<_WalState> _waitForCheckpointedWal(Database db) => _waitForWal(
  db,
  (wal) => wal.log >= _checkpointThresholdPages && wal.checkpointed >= wal.log,
  'WAL did not finish checkpointing',
);

Future<_WalState> _waitForPendingBelowThreshold(Database db) => _waitForWal(
  db,
  (wal) => wal.pending < _checkpointThresholdPages,
  'WAL retained at least one unserviced high-water delta',
);

Future<_WalState> _waitForWal(
  Database db,
  bool Function(_WalState wal) predicate,
  String failure,
) async {
  const timeout = Duration(seconds: 5);
  final stopwatch = Stopwatch()..start();
  var last = const _WalState(busy: -1, log: -1, checkpointed: -1);

  while (stopwatch.elapsed < timeout) {
    last = await _readWalState(db);
    if (predicate(last)) return last;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  fail(
    '$failure within $timeout: '
    'busy=${last.busy}, log=${last.log}, '
    'checkpointed=${last.checkpointed}, pending=${last.pending}',
  );
}

Future<_WalState> _readWalState(Database db, {String schema = 'main'}) async {
  // SQLITE_CHECKPOINT_NOOP is observational in the vendored SQLite 3.53.2
  // (and includes the 3.51.3 WAL-reset race fix); unlike PASSIVE, this probe
  // does not perform the work under test.
  final rows = await db.select('PRAGMA $schema.wal_checkpoint(NOOP)');
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

  int get pending {
    final value = log - checkpointed;
    return value < 0 ? 0 : value;
  }
}
