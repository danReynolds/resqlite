import 'dart:io';
import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('ivm_engage_');
  final db = await Database.open('${dir.path}/t.db');
  final cols = [for (var i = 0; i < 20; i++) String.fromCharCode(97 + i)];
  await db.execute(
    'CREATE TABLE wide(id INTEGER PRIMARY KEY, ${cols.map((c) => '$c TEXT NOT NULL').join(', ')})');
  await db.executeBatch(
    'INSERT INTO wide(id, ${cols.join(', ')}) VALUES (?, ${List.filled(20, '?').join(', ')})',
    [for (var i = 0; i < 100; i++) [i, for (final _ in cols) 'v$i']]);

  // A11c-overlap shape: 50 streams projecting id, a, b over id ranges;
  // writes update column a (intersects every stream's projection).
  final subs = [
    for (var p = 0; p < 50; p++)
      db.stream(
        'SELECT id, a, b FROM wide WHERE id >= ? AND id < ? ORDER BY id',
        [p * 2, p * 2 + 2],
      ).listen((_) {}),
  ];
  await Future<void>.delayed(const Duration(milliseconds: 200));
  ProfileCounters.reset();
  for (var w = 0; w < 500; w++) {
    await db.execute('UPDATE wide SET a = ? WHERE id = ?', ['w$w', w % 100]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final snap = ProfileCounters.snapshot();
  print('ivm_skipped=${snap['ivm_skipped_total']} '
      'ivm_applied=${snap['ivm_applied_total']} '
      'ivm_bail=${snap['ivm_bail_total']} '
      'invalidate_count=${snap['invalidate_count']}');
  for (final s in subs) {
    await s.cancel();
  }
  await db.close();
  await dir.delete(recursive: true);
  exit(0);
}
