# resqlite_js

SQLite JS extension support for `package:resqlite`.

This package exposes SQLite JS's native entrypoint as a `ResqliteExtension`.
It does not depend on `package:sqlite3`.

```dart
import 'package:resqlite/resqlite.dart';
import 'package:resqlite_js/resqlite_js.dart';

final db = await Database.open(
  'app.db',
  extensions: [sqliteJsExtension()],
);

final rows = await db.select('SELECT js_version() AS version');
```

Advanced per-connection setup can be added with `onRegister`:

```dart
sqliteJsExtension(
  onRegister: (ext) {
    ext.execute('CREATE TEMP TABLE js_setup(value TEXT)');
  },
);
```

The bundled native binaries are derived from the `sqlite_js` Dart package and
are covered by the license in `LICENSE`.
