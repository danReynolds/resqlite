import 'dart:io';
import 'dart:math' as math;
import 'package:resqlite/resqlite.dart';

Future<void> main(List<String> args) async {
  final mode = args.first;
  for (var trial = 0; trial < 6; trial++) {
    final dir = await Directory.systemTemp.createTemp('agg_bisect_');
    final db = await Database.open('${dir.path}/t.db');
    await db.execute(
        'CREATE TABLE msgs(id INTEGER PRIMARY KEY, v INTEGER NOT NULL)');
    await db.executeBatch('INSERT INTO msgs(id, v) VALUES (?, ?)',
        [for (var i = 1; i <= 50; i++) [i, i]]);
    var nextId = 51;
    final live = List<int>.generate(50, (i) => i + 1);
    final prng = math.Random(trial * 31 + 7);
    final emissions = <int>[];
    final sub = db
        .stream('SELECT COUNT(*) AS n FROM msgs')
        .listen((r) => emissions.add(r[0]['n'] as int));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    Future<bool> check(int op) async {
      var last = -1;
      while (emissions.isNotEmpty && emissions.last != last) {
        last = emissions.last;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final truth = (await db.select('SELECT COUNT(*) AS n FROM msgs'))[0]['n'];
      if (emissions.isNotEmpty && emissions.last != truth) {
        print('$mode trial $trial: DIVERGED at op $op '
            'emitted=${emissions.last} truth=$truth');
        return false;
      }
      return true;
    }
    var diverged = false;
    for (var op = 0; op < 400; op++) {
      if (op % 25 == 24 && !await check(op)) { diverged = true; break; }
      var effMode = mode;
      if (mode == 'storm' || mode.startsWith('storm-')) {
        final drop = mode.startsWith('storm-') ? mode.substring(6) : '';
        final classes = ['insert', 'update', 'mix', 'rowid', 'tx', 'overflow']
            .where((c) => c != drop)
            .toList();
        effMode = classes[prng.nextInt(classes.length)];
      }
      switch (effMode) {
        case 'insert':
          await db.execute('INSERT INTO msgs(id, v) VALUES (?, 1)', [nextId++]);
          live.add(nextId - 1);
        case 'mix':
          if (prng.nextBool() || live.isEmpty) {
            await db.execute('INSERT INTO msgs(id, v) VALUES (?, 1)', [nextId++]);
            live.add(nextId - 1);
          } else {
            final id = live.removeAt(prng.nextInt(live.length));
            await db.execute('DELETE FROM msgs WHERE id = ?', [id]);
          }
        case 'rowid':
          if (live.isNotEmpty && prng.nextBool()) {
            final i = prng.nextInt(live.length);
            final oldId = live[i];
            live[i] = nextId++;
            await db.execute('UPDATE msgs SET id = ? WHERE id = ?', [live[i], oldId]);
          } else {
            await db.execute('INSERT INTO msgs(id, v) VALUES (?, 1)', [nextId++]);
            live.add(nextId - 1);
          }
        case 'tx':
          await db.transaction((tx) async {
            await tx.execute('INSERT INTO msgs(id, v) VALUES (?, 1)', [nextId++]);
            live.add(nextId - 1);
            if (prng.nextBool()) {
              try {
                await tx.transaction((tx2) async {
                  await tx2.execute('UPDATE msgs SET v = 9 WHERE id = ?',
                      [live[prng.nextInt(live.length)]]);
                  throw StateError('undo');
                });
              } on StateError {/**/}
            }
          });
        case 'update':
          if (live.isNotEmpty) {
            await db.execute('UPDATE msgs SET v = ? WHERE id = ?',
                [prng.nextInt(100), live[prng.nextInt(live.length)]]);
          }
        case 'overflow':
          if (op % 40 == 13) {
            final base = nextId; nextId += 300;
            live.addAll([for (var i = base; i < base + 300; i++) i]);
            await db.executeBatch('INSERT INTO msgs(id, v) VALUES (?, ?)',
                [for (var i = base; i < base + 300; i++) [i, 1]]);
          } else {
            await db.execute('INSERT INTO msgs(id, v) VALUES (?, 1)', [nextId++]);
            live.add(nextId - 1);
          }
      }
    }
    final ok = diverged ? false : await check(400);
    if (ok) print('$mode trial $trial: OK');
    await sub.cancel();
    await db.close();
    await dir.delete(recursive: true);
    if (!ok) exit(1);
  }
  exit(0);
}
