# resqlite_vector

SQLite Vector extension support for `package:resqlite`.

This package exposes SQLite Vector's native entrypoint as a
`ResqliteExtension` value for `Database.open`.

```dart
import 'package:resqlite/resqlite.dart';
import 'package:resqlite_vector/resqlite_vector.dart';

final db = await Database.open(
  'app.db',
  extensions: [SqliteVectorExtension()],
);

final version = await db.select('SELECT vector_version() AS version');
```

To initialize vector indexes on every writer and reader connection, pass
`SqliteVectorIndex` entries:

```dart
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
  ],
);
```

`SqliteVectorIndex` maps to SQLite Vector's
`vector_init(table, column, options)` setup SQL. The target table and column
must already exist before `Database.open` runs this setup. If migrations create
the table, run those migrations first, close that bootstrap connection, then
reopen with `SqliteVectorExtension(indexes: [...])`.

Advanced setup can be added with `onRegister`:

```dart
SqliteVectorExtension(
  onRegister: (ext) {
    ext.execute('SELECT vector_init(?, ?, ?)', parameters: [
      'items',
      'embedding',
      'type=FLOAT32,dimension=1536',
    ]);
  },
);
```

The bundled native binaries are derived from the `sqlite_vector` Dart package
and are covered by the license in `LICENSE`.
