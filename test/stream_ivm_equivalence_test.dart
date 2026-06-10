/// Randomized equivalence harness for tiered incremental maintenance.
///
/// Registers one stream per admission mode (full, windowed full,
/// skip-only, aggregate, text-equality) plus an inadmissible control,
/// then runs seeded random write storms — inserts, updates, deletes,
/// rowid changes, NULL cells, transactions, savepoint rollbacks, and
/// capture-overflow batches. After every storm settles, each stream's
/// latest emission must equal a fresh `select()` of the same SQL.
///
/// This is the load-bearing safety net for the IVM tiers: any divergence
/// between maintained state and re-query semantics fails here, whichever
/// path produced the emission.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

const _seeds = [7, 160, 4242];
const _roundsPerSeed = 12;
const _writesPerRound = 18;

final class _Watched {
  _Watched(this.label, this.sql, this.params);

  final String label;
  final String sql;
  final List<Object?> params;
  final List<List<Map<String, Object?>>> emissions = [];
  StreamSubscription<List<Map<String, Object?>>>? sub;
}

void main() {
  for (final seed in _seeds) {
    test('emissions equal fresh selects under write storm (seed $seed)',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'resqlite_ivm_equiv_',
      );
      final db = await Database.open('${tempDir.path}/t.db');
      addTearDown(() async {
        await db.close();
        try {
          await tempDir.delete(recursive: true);
        } on PathNotFoundException {
          // ignore
        }
      });

      await db.execute(
        'CREATE TABLE msgs(id INTEGER PRIMARY KEY, conv INTEGER NOT NULL, '
        'score INTEGER, body TEXT NOT NULL, kind TEXT NOT NULL)',
      );
      final prng = math.Random(seed);
      var nextId = 1;
      await db.executeBatch(
        'INSERT INTO msgs(id, conv, score, body, kind) VALUES (?, ?, ?, ?, ?)',
        [
          for (; nextId <= 60; nextId++)
            [
              nextId,
              nextId % 6,
              prng.nextBool() ? null : prng.nextInt(1000),
              'b$nextId',
              nextId % 3 == 0 ? 'pin' : 'note',
            ],
        ],
      );

      final watched = <_Watched>[
        _Watched(
          'full range',
          'SELECT id, conv, score FROM msgs '
              'WHERE id >= ? AND id < ? ORDER BY id',
          [10, 40],
        ),
        _Watched(
          'full keyed',
          'SELECT * FROM msgs WHERE id = ?',
          [25],
        ),
        _Watched(
          'windowed feed',
          'SELECT id, score FROM msgs WHERE conv = ? '
              'ORDER BY score DESC, id DESC LIMIT 5',
          [2],
        ),
        _Watched(
          'windowed asc',
          'SELECT id, conv FROM msgs ORDER BY conv, id LIMIT 7',
          const [],
        ),
        _Watched(
          'skip-only pane',
          'SELECT id, body FROM msgs WHERE conv = ? '
              'ORDER BY score DESC LIMIT 4',
          [3],
        ),
        _Watched(
          'text equality',
          "SELECT id, kind FROM msgs WHERE kind = 'pin' ORDER BY id",
          const [],
        ),
        _Watched(
          'aggregates',
          'SELECT COUNT(*) AS n, SUM(score) AS total, MIN(score) AS lo, '
              'MAX(score) AS hi, AVG(score) AS mean '
              'FROM msgs WHERE conv = ?',
          [2],
        ),
        _Watched(
          'global count',
          'SELECT COUNT(*) AS n FROM msgs',
          const [],
        ),
        _Watched(
          'inadmissible control',
          'SELECT conv, COUNT(*) AS n FROM msgs '
              'WHERE id > 0 GROUP BY conv ORDER BY conv',
          const [],
        ),
      ];

      for (final w in watched) {
        w.sub = db.stream(w.sql, w.params).listen(w.emissions.add);
        addTearDown(() => w.sub!.cancel());
      }

      Future<void> settle() async {
        // Quiet-window drain: counts stable across consecutive windows.
        int total() =>
            watched.fold(0, (a, w) => a + w.emissions.length);
        var last = total();
        var quiet = 0;
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (quiet < 2 && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          final now = total();
          if (now == last) {
            quiet++;
          } else {
            quiet = 0;
            last = now;
          }
        }
      }

      await settle();
      for (final w in watched) {
        expect(w.emissions, isNotEmpty, reason: '${w.label}: no initial');
      }
      // Let async admissions land before the storm so maintained paths
      // actually engage.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final liveIds = List<int>.generate(60, (i) => i + 1);

      Future<void> oneWrite(math.Random prng) async {
        final roll = prng.nextInt(100);
        if (roll < 35 || liveIds.isEmpty) {
          // Insert.
          final id = nextId++;
          liveIds.add(id);
          await db.execute(
            'INSERT INTO msgs(id, conv, score, body, kind) '
            'VALUES (?, ?, ?, ?, ?)',
            [
              id,
              prng.nextInt(6),
              prng.nextBool() ? null : prng.nextInt(1000),
              'b$id',
              prng.nextBool() ? 'pin' : 'note',
            ],
          );
        } else if (roll < 65) {
          // Update (sometimes to NULL score, sometimes kind flips).
          final id = liveIds[prng.nextInt(liveIds.length)];
          await db.execute(
            'UPDATE msgs SET conv = ?, score = ?, kind = ? WHERE id = ?',
            [
              prng.nextInt(6),
              prng.nextBool() ? null : prng.nextInt(1000),
              prng.nextBool() ? 'pin' : 'note',
              id,
            ],
          );
        } else if (roll < 80) {
          // Delete.
          final idx = prng.nextInt(liveIds.length);
          final id = liveIds.removeAt(idx);
          await db.execute('DELETE FROM msgs WHERE id = ?', [id]);
        } else if (roll < 90) {
          // Rowid change.
          final idx = prng.nextInt(liveIds.length);
          final oldId = liveIds[idx];
          final newId = nextId++;
          liveIds[idx] = newId;
          await db.execute('UPDATE msgs SET id = ? WHERE id = ?', [
            newId,
            oldId,
          ]);
        } else if (roll < 96) {
          // Transaction, occasionally with a rolled-back savepoint.
          await db.transaction((tx) async {
            final id = nextId++;
            liveIds.add(id);
            await tx.execute(
              'INSERT INTO msgs(id, conv, score, body, kind) '
              "VALUES (?, ?, ?, ?, 'note')",
              [id, prng.nextInt(6), prng.nextInt(1000), 'tx$id'],
            );
            if (prng.nextBool()) {
              try {
                await tx.transaction((tx2) async {
                  await tx2.execute(
                    'UPDATE msgs SET score = 777777 WHERE id = ?',
                    [liveIds[prng.nextInt(liveIds.length)]],
                  );
                  throw StateError('undo');
                });
              } on StateError {
                // expected
              }
            }
          });
        } else {
          // Capture-overflow batch (> 256 delta rows poisons the cycle).
          final base = nextId;
          nextId += 300;
          liveIds.addAll([for (var i = base; i < base + 300; i++) i]);
          await db.executeBatch(
            'INSERT INTO msgs(id, conv, score, body, kind) '
            "VALUES (?, ?, ?, ?, 'note')",
            [
              for (var i = base; i < base + 300; i++)
                [i, i % 6, i % 7 == 0 ? null : i, 'bulk$i'],
            ],
          );
        }
      }

      for (var round = 0; round < _roundsPerSeed; round++) {
        for (var w = 0; w < _writesPerRound; w++) {
          await oneWrite(prng);
        }
        await settle();
        for (final w in watched) {
          final fresh = await db.select(w.sql, w.params);
          expect(
            w.emissions.last,
            fresh,
            reason:
                '${w.label} diverged at seed $seed round $round '
                '(emissions: ${w.emissions.length})',
          );
        }
      }
    });
  }
}
