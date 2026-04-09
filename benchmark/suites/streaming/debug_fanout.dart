import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

void main() async {
  final dir = await Directory.systemTemp.createTemp('fanout_');
  final db = await Database.open('${dir.path}/test.db');
  await db.execute(
    'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT, value INTEGER)',
  );
  for (var i = 0; i < 100; i++) {
    await db.execute(
      'INSERT INTO items(name, value) VALUES (?, ?)',
      ['item_$i', i],
    );
  }

  const N = 10;
  const iterations = 20;

  for (var iter = 0; iter < iterations; iter++) {
    print('--- Iteration ${iter + 1} ---');
    final initCs = <Completer<void>>[];
    final reCs = <Completer<void>>[];
    final subs = <StreamSubscription>[];

    for (var i = 0; i < N; i++) {
      final ic = Completer<void>();
      final rc = Completer<void>();
      initCs.add(ic);
      reCs.add(rc);
      var ec = 0;

      final s = db.stream("SELECT COUNT(*) as cnt, '${iter}_$i' as sid FROM items");
      subs.add(s.listen((_) {
        ec++;
        if (ec == 1 && !ic.isCompleted) ic.complete();
        else if (ec >= 2 && !rc.isCompleted) rc.complete();
      }));
    }

    await Future.wait(initCs.map((c) => c.future))
        .timeout(const Duration(seconds: 5));
    print('  All $N initial emissions received.');

    await db.execute(
      'INSERT INTO items(name, value) VALUES (?, ?)',
      ['trigger_$iter', iter],
    );

    var passed = 0;
    var failed = 0;
    for (var i = 0; i < N; i++) {
      try {
        await reCs[i].future.timeout(const Duration(seconds: 2));
        passed++;
      } on TimeoutException {
        failed++;
        print('  Stream $i: TIMED OUT');
      }
    }
    print('  Result: $passed/$N re-emitted${failed > 0 ? ' ($failed failed)' : ''}');

    for (final s in subs) {
      await s.cancel();
    }
  }

  await db.close();
  await dir.delete(recursive: true);
  exit(0);
}
