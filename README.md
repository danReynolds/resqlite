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

// Reactive queries — automatic dependency detection using SQLite's
// authorizer hook and the pre-update hook for column-aware invalidation.
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

Visit the [project site](https://danreynolds.github.io/resqlite/) to browse interactive experiments and benchmarks.

## Features

- **Zero main-isolate jank.** Reads, writes, and reactive re-queries all run on persistent worker isolates. A 5,000-row query uses sub-millisecond main-isolate time.
- **Reactive SQL.** [`db.stream(sql)`](./lib/src/database.dart) turns table-backed queries into live streams. Dependencies are detected automatically — works with JOINs, subqueries, views, CTEs. No table lists to maintain.
- **Column-aware invalidation.** Writes to unrelated columns do not wake streams that cannot change. Identical queries are deduplicated, unchanged results are suppressed, and uncertain metadata falls back safely to table-level invalidation.
- **Just SQL.** [`select`](./lib/src/database.dart), [`execute`](./lib/src/database.dart), [`executeBatch`](./lib/src/database.dart), [`transaction`](./lib/src/database.dart), [`stream`](./lib/src/database.dart). No ORM, no query builder, no code generation.
- **Encryption.** Optional AES-256 encryption via SQLite3 Multiple Ciphers. Same API — just pass a key.

## Getting Started

```yaml
dependencies:
  resqlite: ^0.6.0
```

Or via the CLI:

```sh
dart pub add resqlite
flutter pub add resqlite
```

## Performance

resqlite is designed to work in the background and keep apps running smooth. Reads, writes, and stream queries all run on background worker isolates. The main isolate only receives finished results.

| Metric | Wall time | Main isolate time |
|---|---:|---:|
| Point query (1 row) | 0.010ms | 0.010ms |
| 1,000-row select() | 0.39ms | 0.09ms |
| 10,000-row select() | 4.71ms | 0.90ms |
| Batch insert (1,000 rows) | 0.41ms | 0.41ms |
| Stream invalidation | 0.06ms | 0.06ms |

~104K point queries/sec. 3x faster wall-clock reads and 13x less main-isolate time at 1K rows compared to synchronous alternatives. Sub-millisecond stream invalidation.

Measured on a 10-core Apple M1 Pro, Dart 3.11, macOS 26.2. Results will vary by hardware. The [sqlite3](https://pub.dev/packages/sqlite3) package is a great choice for synchronous workloads; [sqlite_async](https://pub.dev/packages/sqlite_async) (PowerSync) offers production-tested streaming with built-in throttling. resqlite is optimized for Flutter apps where main-isolate time is the critical constraint.

See the full comparison in the [interactive benchmark dashboard](https://danreynolds.github.io/resqlite/benchmarks/), or run the benchmarks on your machine and [add your results](https://github.com/danReynolds/resqlite/blob/main/benchmark/HARDWARE_RESULTS.md).

Pre-publish profiling now uses the trace-backed [`benchmark/run_tracelite.dart`](benchmark/run_tracelite.dart) gate, which preserves suite history, calibrated policy artifacts, and dashboard-ready graph data.

## Reactive Queries

```dart
db.stream('SELECT * FROM users WHERE active = ?', [1]).listen((users) {
  setState(() => this.users = users);
});
```

That's the entire reactive API. Under the hood:

- **Automatic dependency tracking** via SQLite's [authorizer hook](https://www.sqlite.org/c3ref/set_authorizer.html) — no manual table lists
- **Column-aware dispatch** — writes to columns outside a stream's projection are skipped when SQLite metadata is precise
- **Deduplication** — 100 widgets watching the same query = 1 actual SQLite query per write
- **Unchanged suppression** — writes that don't change your query's results are silently filtered
- **Immediate** — re-queries fire on write commit, not on a timer

**Virtual table limitation:** SQLite's [preupdate hook](https://www.sqlite.org/c3ref/preupdate_blobwrite.html) does not fire for virtual-table writes (FTS5, R-Tree, etc.), so streams over virtual tables do not auto-invalidate. For external-content FTS, join the real content table in the streamed query so normal table invalidation applies. For other cases, use [`select`](./lib/src/database.dart) instead of [`stream`](./lib/src/database.dart).

## API

```dart
final db = await Database.open('app.db');

// Reads
final rows = await db.select('SELECT * FROM users WHERE id = ?', [42]);
final json = await db.selectBytes('SELECT * FROM users'); // JSON serialized in C — no Dart object allocation

// Writes
final result = await db.execute('INSERT INTO users(name) VALUES (?)', ['Ada']);
await db.executeBatch('INSERT INTO users(name) VALUES (?)', [['Ada'], ['Grace']]); // bulk inserts in a single transaction

// Transactions
await db.transaction((tx) async {
  await tx.execute('INSERT INTO users(name) VALUES (?)', ['Ada']);
  final rows = await tx.select('SELECT COUNT(*) as c FROM users');
  return rows.first['c'];
});

// Reactive streams
db.stream('SELECT * FROM users ORDER BY id').listen((rows) { ... });

// Encryption
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
2. If SQLite reported precise column metadata, streams whose selected columns are disjoint from the write do not wake up.
3. Streams on other tables do not wake up; uncertain column metadata falls back to table-level re-query.
4. The worker hashes the new result. If the data hasn't changed, nothing is sent back and no work is done on the main isolate.
5. If it changed, the [`StreamBuilder`](https://api.flutter.dev/flutter/widgets/StreamBuilder-class.html) receives the new data and rebuilds.

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

1,000 rows in **~0.4ms**. All-or-nothing atomicity — a crash mid-import leaves zero partial rows. Streams watching the table fire once on commit, not per row.

## SQLite Extensions

resqlite supports SQLite loadable extensions through small companion packages
that expose native extension entrypoints as `ResqliteExtension` values. The
extension list belongs to the database being opened, and resqlite registers
each extension on the writer and reader connections in that database pool.

```yaml
dependencies:
  resqlite: ^0.6.0
  resqlite_vector: ^0.1.0
  resqlite_js: ^0.1.0
```

```dart
import 'package:resqlite/resqlite.dart';
import 'package:resqlite_js/resqlite_js.dart';
import 'package:resqlite_vector/resqlite_vector.dart';

final db = await Database.open(
  'app.db',
  extensions: [
    SqliteVectorExtension(
      indexes: [
        SqliteVectorIndex(
          table: 'items',
          column: 'embedding',
          dimension: 1536,
        ),
      ],
    ),
    SqliteJsExtension(),
  ],
);

final vectorVersion = await db.select('SELECT vector_version() AS version');
final jsVersion = await db.select('SELECT js_version() AS version');
```

Available extension-related capabilities:

| Category | Capability | Package | What it adds | How to enable |
| --- | --- | --- | --- | --- |
| Built in | FTS5 | `resqlite` | Full-text virtual tables, tokenizers, ranking helpers. | Use `CREATE VIRTUAL TABLE ... USING fts5(...)`. |
| Built in | JSON functions | `resqlite` | JSON extraction, construction, and table-valued JSON traversal. | Call functions such as `json_extract` and `json_each` from SQL. |
| Built in | Math functions | `resqlite` | SQLite scalar math functions for scoring and analytics. | Call functions such as `sqrt`, `sin`, and `pow` from SQL. |
| Companion package | SQLite Vector | `resqlite_vector` | Vector conversion functions and vector search helpers. | Add `SqliteVectorExtension(...)`; use `SqliteVectorIndex` for `vector_init` setup. |
| Companion package | SQLite JS | `resqlite_js` | JavaScript-backed SQLite functions, aggregates, window functions, and collations. | Add `SqliteJsExtension(...)`. |
| Custom package | Native SQLite extension | `resqlite` plus your package | Any SQLite ABI-compatible loadable extension. | Expose a `ResqliteExtension` subclass, or use `ResqliteExtension.inLibrary(...)` / `fromAddress(...)`. |

The extension package pattern is intentionally small:

1. Bundle or build the native SQLite extension with a `hook/build.dart`.
2. Expose the extension init symbol with `@Native<ResqliteExtensionInitNative>`.
3. Expose a small `ResqliteExtension` subclass for app code to pass around.
4. Pass the extension to `Database.open(extensions: [...])`.

Use `packages/resqlite_js` as the minimal package template; extension hooks are
specific enough that resqlite documents the pattern instead of shipping a
generic scaffold.

Pass each native extension once per `Database.open`. If multiple app modules
need the same extension, centralize their setup into one extension value; passing
the same native entrypoint twice is rejected so setup order is explicit.

Extensions that need per-connection SQL setup can record it during registration:

```dart
final class SqliteExampleExtension extends ResqliteExtension {
  SqliteExampleExtension()
    : super(
        Native.addressOf<ResqliteExtensionEntrypoint>(sqlite3ExampleInit),
        name: 'sqlite_example',
        onRegister: (ext) {
          ext.execute('SELECT example_init(?)', parameters: ['items']);
        },
      );
}
```

resqlite runs extension native load and setup during `Database.open`, before
the database is returned and before normal reader/writer workers start.
Companion packages should expose domain-specific options for common setup, like
`SqliteVectorIndex`, and reserve raw `onRegister` setup for advanced escape
hatches. See [SQLite extension authoring](./doc/sqlite-extensions.md) for the
package pattern and compatibility contract.

## Architecture

- **Reads** go through a [persistent reader pool](./lib/src/reader/reader_pool.dart) (2-4 workers with dedicated C connections)
- **Writes** go through a single [persistent writer isolate](./lib/src/writer/write_worker.dart)
- **Streams** use SQLite's [authorizer hook](https://www.sqlite.org/c3ref/set_authorizer.html) for table/column [dependency tracking](./lib/src/stream_engine.dart) and [preupdate hook](https://www.sqlite.org/c3ref/preupdate_blobwrite.html) for column-aware write invalidation
- **Large results** use hybrid transmission — [`SendPort`](https://api.dart.dev/dart-isolate/SendPort-class.html) for small, zero-copy [`Isolate.exit`](https://api.dart.dev/dart-isolate/Isolate/exit.html) for large

See the [full architecture breakdown](./doc/arch/architecture.md) for how the reader pool, writer isolate, and stream engine fit together.

## Learn More

- [Homepage](https://danreynolds.github.io/resqlite/) — project overview, architecture, and write-up
- [Interactive Benchmarks](https://danreynolds.github.io/resqlite/benchmarks/) — compare performance over time and across devices
- [API Reference](https://danreynolds.github.io/resqlite/api/resqlite/resqlite-library.html) — full Dart API docs
- [Architecture overview](./doc/arch/architecture.md) — how the reader pool, writer isolate, and stream engine fit together
- [Experiment log](https://github.com/danReynolds/resqlite/blob/main/experiments/README.md) — 110+ documented experiments with benchmarks and reasoning behind every design decision
- [Benchmark suite](https://github.com/danReynolds/resqlite/blob/main/benchmark/README.md) — run the full suite yourself, or [see community results across hardware](https://github.com/danReynolds/resqlite/blob/main/benchmark/HARDWARE_RESULTS.md)
