/// Executable source for the code sample on the knowledge base's landing page.
///
/// `doc/arch/home.md` does not contain that sample. It references the
/// `quickstart` region below, and `benchmark/generate_knowledge_page.dart`
/// splices the region in at build time — so the code a reader sees is, by
/// construction, code that runs. It cannot drift from the library, because
/// there is only one copy of it and CI executes that copy.
///
/// This is a stronger binding than a hash: a hash detects that a sample
/// changed, whereas transclusion makes disagreement impossible. Prefer it
/// wherever the documented code can actually be run.
library;

import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Directory startingCwd;

  setUp(() {
    // The sample opens `'app.db'`, and that literal is worth keeping — it is
    // the first line of resqlite anybody reads, and a `dbPath` variable would
    // be documentation about the test rather than about the library. Running
    // from a temp directory lets the documented line be the executed line,
    // character for character.
    startingCwd = Directory.current;
    tmp = Directory.systemTemp.createTempSync('resqlite-home-sample-');
    Directory.current = tmp;
  });

  tearDown(() {
    Directory.current = startingCwd;
    tmp.deleteSync(recursive: true);
  });

  test('the landing page quickstart runs', () async {
    // #docregion quickstart
    final db = await Database.open('app.db');
    // #enddocregion quickstart

    await db.execute(
      'CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT, active INTEGER DEFAULT 1)',
    );
    await db.execute('INSERT INTO users(name) VALUES (?)', ['Grace']);

    // #docregion quickstart

    // Reads and writes stay off the UI thread.
    final users = await db.select('SELECT * FROM users WHERE active = ?', [1]);
    await db.execute('INSERT INTO users(name) VALUES (?)', ['Ada']);

    // Reactive queries. Dependencies are detected from the SQL itself —
    // JOINs, subqueries, views and CTEs all work, with no table lists to maintain.
    var activeUsers = <Map<String, Object?>>[];
    db.stream('SELECT * FROM users WHERE active = ?', [1]).listen((rows) {
      // Rebuild your UI here — in Flutter, setState(() => this.users = rows).
      activeUsers = rows;
    });
    // #enddocregion quickstart

    expect(users, hasLength(1), reason: 'select saw the seeded row');

    // The stream is the part most likely to rot silently, so assert it really
    // delivers rather than merely subscribing without throwing.
    while (activeUsers.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      activeUsers.map((r) => r['name']),
      containsAll(<String>['Grace', 'Ada']),
    );

    await db.close();
  });
}
