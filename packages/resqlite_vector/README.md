# resqlite_vector

SQLite Vector extension support for `package:resqlite`.

This package exposes SQLite Vector's native entrypoint as a
`ResqliteExtension`. It does not depend on `package:sqlite3`.

```dart
import 'package:resqlite/resqlite.dart';
import 'package:resqlite_vector/resqlite_vector.dart';

final db = await Database.open(
  'app.db',
  extensions: [sqliteVectorExtension()],
);

final version = await db.select('SELECT vector_version() AS version');
```

The bundled native binaries are derived from the `sqlite_vector` Dart package
and are covered by the license in `LICENSE`.
