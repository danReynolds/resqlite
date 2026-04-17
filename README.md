<h1 align="center">
  <img src="docs/logo.png" alt="" width="180"><br>
  resqlite
</h1>

[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20Android%20%7C%20macOS%20%7C%20Linux%20%7C%20Windows-brightgreen.svg)]()
[![Docs](https://img.shields.io/badge/docs-Homepage-58a6ff.svg)](https://danreynolds.github.io/resqlite/)
[![API Docs](https://img.shields.io/badge/docs-API%20Reference-blue.svg)](https://danreynolds.github.io/resqlite/api/resqlite/resqlite-library.html)
[![Benchmarks](https://img.shields.io/badge/benchmarks-Interactive%20Dashboard-brightgreen.svg)](https://danreynolds.github.io/resqlite/benchmarks/)

High-performance, reactive SQLite for Dart and Flutter.

Write plain SQL. Stream anything. No main isolate jank. No ORM. No codegen.

```dart
final db = await Database.open('app.db');

// Reads and writes stay off your UI thread.
final users = await db.select('SELECT * FROM users WHERE active = ?', [1]);
await db.execute('INSERT INTO users(name) VALUES (?)', ['Ada']);

// Reactive queries — automatic table dependency detection using SQLite's
// authorizer hook and the pre-update hook for invalidation.
db.stream('SELECT * FROM users WHERE active = ?', [1]).listen((users) {
  setState(() => this.users = users);
});

// Transactions — reads inside see uncommitted writes.
await db.transaction((tx) async {
  await tx.execute('INSERT INTO users(name) VALUES (?)', ['Sonja']);
  final rows = await tx.select('SELECT COUNT(*) as c FROM users');
  print('total: ${rows.first['c']}');
});
```

## Features

- **🚀 Zero main-isolate jank.** Reads, writes, and reactive re-queries all run on persistent worker isolates. A 5,000-row query uses sub-millisecond main-isolate time.
- **⚡ Reactive SQL.** [`db.stream(sql)`](./lib/src/database.dart) turns any query into a live stream. Table dependencies are detected automatically — works with JOINs, subqueries, views, CTEs. No table lists to maintain.
- **🔁 Smart invalidation.** Identical queries are deduplicated. Unchanged results are suppressed. Re-queries fire immediately on write commit — sub-millisecond, no polling.
- **📦 Just SQL.** [`select`](./lib/src/database.dart), [`execute`](./lib/src/database.dart), [`executeBatch`](./lib/src/database.dart), [`transaction`](./lib/src/database.dart), [`stream`](./lib/src/database.dart). No ORM, no query builder, no code generation.
- **🔒 Encryption.** Optional AES-256 encryption via SQLite3 Multiple Ciphers. Same API — just pass a key.

## Performance

resqlite is designed to work in the background and keep apps running smooth. Reads, writes, and stream queries all run on background worker isolates. The main isolate only receives finished results.

| Metric | Wall time | Main isolate time |
|---|---:|---:|
| Point query (1 row) | 0.010ms | 0.010ms |
| 1,000-row select() | 0.40ms | 0.10ms |
| 10,000-row select() | 5.60ms | 1.01ms |
| Batch insert (1,000 rows) | 0.43ms | 0.00ms |
| Stream invalidation | 0.05ms | 0.05ms |

~107K point queries/sec. 1.8x faster wall-clock reads and 7.9x less main-isolate time at 1K rows compared to synchronous alternatives. Sub-millisecond stream invalidation.

Measured on a 10-core Apple M1 Pro, Dart 3.11, macOS 26.2. Batch inserts at scale are comparable to sqlite3. Results will vary by hardware. The [sqlite3](https://pub.dev/packages/sqlite3) package is a great choice for synchronous workloads; [sqlite_async](https://pub.dev/packages/sqlite_async) (PowerSync) offers production-tested streaming with built-in throttling. resqlite is optimized for Flutter apps where main-isolate time is the critical constraint.

See the full comparison in the [interactive benchmark dashboard](https://danreynolds.github.io/resqlite/benchmarks/), or run the benchmarks on your machine and [add your results](./benchmark/HARDWARE_RESULTS.md).

## Reactive Queries

```dart
db.stream('SELECT * FROM users WHERE active = ?', [1]).listen((users) {
  setState(() => this.users = users);
});
```

That's the entire reactive API. Under the hood:

- **Automatic dependency tracking** via SQLite's [authorizer hook](https://www.sqlite.org/c3ref/set_authorizer.html) — no manual table lists
- **Deduplication** — 100 widgets watching the same query = 1 actual SQLite query per write
- **Unchanged suppression** — writes that don't change your query's results are silently filtered
- **Immediate** — re-queries fire on write commit, not on a timer

## API

```dart
final db = await Database.open('app.db');

// Reads
final rows = await db.select('SELECT * FROM users WHERE id = ?', [42]);
final json = await db.selectBytes('SELECT * FROM users'); // Optimized for byte response use cases like HTTP servers.

// Writes
final result = await db.execute('INSERT INTO users(name) VALUES (?)', ['Ada']);
await db.executeBatch('INSERT INTO users(name) VALUES (?)', [['Ada'], ['Grace']]); // Optimized for bulk inserts and atomic batch updates.

// Transactions
await db.transaction((tx) async {
  await tx.execute('INSERT INTO users(name) VALUES (?)', ['Ada']);
  final rows = await tx.select('SELECT COUNT(*) as c FROM users');
  return rows.first['c'];
});

// Reactive streams
db.stream('SELECT * FROM users ORDER BY id').listen((rows) { ... });

// Out of the box encryption support.
final db = await Database.open('secure.db', encryptionKey: '0123...abcdef');

await db.close();
```

## In Practice

### Large reads without jank

Your UI renders at 60fps — 16ms per frame. A 5,000-row [`select`](./lib/src/database.dart) takes 2.5ms total, but only **0.65ms on the main isolate:**

```dart
final items = await db.select(
  'SELECT id, name, price FROM products ORDER BY name',
);

// Row objects are created lazily — only the rows you access get materialized.
for (final item in items) {
  print('${item['name']}: \$${item['price']}');
}
```

The expensive work — SQLite stepping, string decoding, result building — runs on a persistent background worker. The main isolate receives an optimized array and wraps it in lightweight [`Row`](./lib/src/row.dart) views on access.

### Live-updating UI

Create a reactive [`stream`](./lib/src/database.dart) and use it with the standard [`StreamBuilder`](https://api.flutter.dev/flutter/widgets/StreamBuilder-class.html). The library handles invalidation, deduplication, and change detection:

```dart
class TaskDashboard extends StatefulWidget { ... }

class _TaskDashboardState extends State<TaskDashboard> {
  // Create streams once — not on every build.
  late final _pendingCount = db.stream(
    'SELECT COUNT(*) as c FROM tasks WHERE done = 0',
  );
  late final _myTasks = db.stream(
    'SELECT * FROM tasks WHERE assigned_to = ? ORDER BY due',
    [userId],
  );

  @override
  Widget build(BuildContext context) => Column(children: [
    StreamBuilder(
      stream: _pendingCount,
      builder: (context, snap) => Text('${snap.data?.first['c']} remaining'),
    ),
    StreamBuilder(
      stream: _myTasks,
      builder: (context, snap) => TaskList(tasks: snap.data ?? []),
    ),
  ]);
}
```

When a write hits the `tasks` table:

1. resqlite looks up affected streams via an inverted index — no scanning.
2. Only those streams re-query. Streams on other tables don't wake up.
3. The worker hashes the new result. If the data hasn't changed, nothing is sent back and no work is done on the main isolate.
4. If it changed, the [`StreamBuilder`](https://api.flutter.dev/flutter/widgets/StreamBuilder-class.html) receives the new data and rebuilds.

### JSON bytes for HTTP responses

[`selectBytes`](./lib/src/database.dart) produces JSON directly in C — no Dart object allocation for the result data:

```dart
Future<Response> handleProducts(Request request) async {
  final bytes = await db.selectBytes(
    'SELECT id, name, price FROM products WHERE active = ?',
    [1],
  );
  return Response.ok(bytes, headers: {'content-type': 'application/json'});
}
```

String escaping, number formatting, and JSON structure are handled in native code. The result crosses to Dart as a single [`Uint8List`](https://api.dart.dev/dart-typed_data/Uint8List-class.html). At 1,000 rows this is **5× faster** than building Dart maps and calling [`jsonEncode`](https://api.dart.dev/dart-convert/jsonEncode.html), and uses **0ms of main-isolate time.**

### Bulk sync

[`executeBatch`](./lib/src/database.dart) runs one prepared statement across many parameter sets in a single transaction — one prepare, one commit, no per-row overhead:

```dart
await db.executeBatch(
  'INSERT OR REPLACE INTO products(id, name, price) VALUES (?, ?, ?)',
  serverRows.map((r) => [r['id'], r['name'], r['price']]).toList(),
);
```

1,000 rows in **0.8ms**. All-or-nothing atomicity — a crash mid-import leaves zero partial rows. Streams watching the table fire once on commit, not per row.

## Architecture TLDR

- **Reads** go through a [persistent reader pool](./lib/src/reader_pool.dart) (2-4 workers with dedicated C connections)
- **Writes** go through a single [persistent writer isolate](./lib/src/write_worker.dart)
- **Streams** use SQLite's [authorizer hook](https://www.sqlite.org/c3ref/set_authorizer.html) for [dependency tracking](./lib/src/stream_engine.dart) and [preupdate hook](https://www.sqlite.org/c3ref/preupdate_count.html) for write invalidation
- **Large results** use hybrid transmission — [`SendPort`](https://api.dart.dev/dart-isolate/SendPort-class.html) for small, zero-copy [`Isolate.exit`](https://api.dart.dev/dart-isolate/Isolate/exit.html) for large

- [Full Breakdown](./docs/arch/architecture.md) — how the reader pool, writer isolate, and stream engine fit together


## Getting Started

Currently source-only (`publish_to: none`):

```yaml
dependencies:
  resqlite:
    path: ../resqlite
```

Requires native Dart/Flutter builds (not web). The C code compiles automatically via Dart's native asset hooks.

resqlite does not include a migration framework — schema management is done with plain SQL:

```dart
await db.execute('CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, name TEXT)');
```

For versioned migrations, track a schema version in a `PRAGMA user_version` or a metadata table and run your DDL accordingly. This is a deliberate choice — resqlite stays close to raw SQL and leaves schema tooling to your application.

## Learn More

- [Architecture overview](./docs/arch/architecture.md) — how the reader pool, writer isolate, and stream engine fit together
- [Experiment log](./experiments/README.md) — 41 documented experiments with benchmarks and reasoning behind every design decision
- [Benchmark suite](./benchmark/README.md) — run the full suite yourself, or [see community results across hardware](./benchmark/HARDWARE_RESULTS.md)
