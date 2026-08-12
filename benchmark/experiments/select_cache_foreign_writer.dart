// ignore_for_file: avoid_print
//
// Adversarial probe for a main-isolate `select()` result cache
// ([EXP-270](../../experiments/270-read-result-cache.md)).
//
// A cache is only as correct as the invalidation signal under it, and
// resqlite's signal has a boundary its own writes never cross: the preupdate
// hook fires on the connection that performed the write. A second connection to
// the same file — a second `Database.open` in this process, a background
// isolate, another process — commits without the first `Database` hearing
// anything at all.
//
// `stream()` has always had that boundary. `select()` has not: it re-reads the
// file every time and therefore sees any committed write, whoever made it. So
// this probe is not a test of the cache's bookkeeping. It asks the one question
// that decides whether such a cache may sit behind the existing `select()`
// contract: does a read still report what is committed on disk?
//
// It is the exp 269 `select_inline_opaque_work.dart` pattern — arm the SQL, then
// exercise the hazard the happy-path lanes cannot see — and it must be run
// before any future experiment optimizes read routing by remembering results.
//
// Usage:
//   dart run benchmark/experiments/select_cache_foreign_writer.dart
//
// Exits non-zero when a read reports a value the database no longer holds.
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('bench_cache_foreign_');
  final path = '${temp.path}/test.db';
  var stale = false;
  try {
    final owner = await resqlite.Database.open(path);
    await owner.execute('CREATE TABLE items(id INTEGER PRIMARY KEY, v TEXT)');
    await owner.execute('INSERT INTO items(id, v) VALUES (1, ?)', ['before']);

    const sql = 'SELECT v FROM items WHERE id = ?';

    // Arm: two reads through the owner, so any per-SQL description has been
    // learned and any result has been stored.
    final first = await owner.select(sql, [1]);
    await owner.select(sql, [1]);
    print('armed              v=${first.single['v']}');

    // A second connection to the same file commits a change the owner's
    // invalidation path never observes.
    final foreign = await resqlite.Database.open(path);
    await foreign.execute('UPDATE items SET v = ? WHERE id = ?', ['after', 1]);
    await foreign.close();

    final observed = (await owner.select(sql, [1])).single['v'];
    print('after foreign write v=$observed (expected: after)');

    // Read the file directly, so the probe reports the database's own answer
    // rather than trusting either connection.
    final verifier = await resqlite.Database.open(path);
    final truth = (await verifier.select(sql, [1])).single['v'];
    await verifier.close();
    print('fresh connection    v=$truth');

    stale = observed != truth;
    await owner.close();
  } finally {
    await temp.delete(recursive: true);
  }

  if (stale) {
    print('FAIL: select() returned a value the database no longer holds.');
    exit(1);
  }
  print('OK: select() reflects a committed foreign write.');
}
