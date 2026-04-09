import 'package:resqlite/resqlite.dart';

Future<void> main() async {
  final db = await Database.open('example.db');

  // Create a table.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS users(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE
    )
  ''');

  // Insert rows.
  await db.execute(
    'INSERT OR IGNORE INTO users(name, email) VALUES (?, ?)',
    ['Ada Lovelace', 'ada@example.com'],
  );

  // Batch insert.
  await db.executeBatch(
    'INSERT OR IGNORE INTO users(name, email) VALUES (?, ?)',
    [
      ['Grace Hopper', 'grace@example.com'],
      ['Margaret Hamilton', 'margaret@example.com'],
    ],
  );

  // Read rows — runs on a worker isolate, returns instantly to the main thread.
  final users = await db.select('SELECT * FROM users ORDER BY name');
  for (final row in users) {
    print('${row['name']} <${row['email']}>');
  }

  // Transactions — reads inside see uncommitted writes.
  final count = await db.transaction((tx) async {
    await tx.execute(
      'INSERT OR IGNORE INTO users(name, email) VALUES (?, ?)',
      ['Hedy Lamarr', 'hedy@example.com'],
    );
    final rows = await tx.select('SELECT COUNT(*) as c FROM users');
    return rows.first['c'] as int;
  });
  print('Total users after transaction: $count');

  // Reactive stream — re-emits whenever the users table changes.
  final stream = db.stream('SELECT COUNT(*) as c FROM users');
  final sub = stream.listen((rows) {
    print('Live count: ${rows.first['c']}');
  });

  // Trigger an update — the stream re-emits automatically.
  await db.execute(
    'INSERT OR IGNORE INTO users(name, email) VALUES (?, ?)',
    ['Katherine Johnson', 'katherine@example.com'],
  );

  // Give the stream a moment to deliver, then clean up.
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await sub.cancel();
  await db.close();
}
