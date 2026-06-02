# SQLite extension authoring

resqlite extensions use SQLite's standard native extension entrypoint ABI, but
they load through resqlite's database-pool API.

That means an app opts in when opening the database:

```dart
final db = await Database.open(
  'app.db',
  extensions: [SqliteVectorExtension()],
);
```

The extension is registered on the writer connection and every reader
connection in that pool. Other resqlite databases opened without the extension
do not see its SQL functions, collations, or virtual tables.

Internally, resqlite temporarily registers the native entrypoints with
`sqlite3_auto_extension()` while it opens the pool, then cancels those
registrations before returning. SQLite's auto-extension list is process-global
for a SQLite image, so resqlite serializes that register/open/cancel sequence
and rejects duplicate extension entries before crossing into C. If an extension
needs multiple setup statements, record them from one extension value.

## Companion package template

A companion package imports `package:resqlite/resqlite.dart`, exposes the
extension init symbol, and wraps that symbol in a small extension class.

```dart
import 'dart:ffi';

import 'package:resqlite/resqlite.dart';

@Native<ResqliteExtensionInitNative>(
  assetId: 'package:resqlite_example/src/native/example_extension.dart',
  symbol: 'sqlite3_example_init',
)
external int sqlite3ExampleInit(
  Pointer<Void> db,
  Pointer<Void> pzErrMsg,
  Pointer<Void> pApi,
);

final class SqliteExampleExtension extends ResqliteExtension {
  SqliteExampleExtension()
    : super(
        Native.addressOf<ResqliteExtensionEntrypoint>(sqlite3ExampleInit),
        name: 'sqlite_example',
      );
}
```

The package's `hook/build.dart` should compile or bundle the extension as a
native asset and export the asset id used by `@Native`. Existing wrappers in
this repo use this shape. `packages/resqlite_js` is the minimal reference; it
has one native entrypoint, one `hook/build.dart`, and one Dart extension class.

The reusable package shape is:

```text
resqlite_example/
  hook/build.dart
  lib/resqlite_example.dart
  lib/src/resqlite_example.dart
  native_libraries/<platform>/...
```

The hook can either compile C sources or select checked-in binaries. Keep the
hook specific to the extension package because native sources, binary names,
platform coverage, and licensing usually vary by extension.

## Connection setup

Some extensions need per-connection SQL after the native entrypoint has loaded.
For example, SQLite Vector exposes `vector_init(table, column, options)` for
each indexed vector column. ICU-style extensions may expose SQL functions that
register a collation for the current connection.

Represent that as `onRegister` setup on the extension class:

```dart
final class SqliteExampleExtension extends ResqliteExtension {
  SqliteExampleExtension()
    : super(
        Native.addressOf<ResqliteExtensionEntrypoint>(sqlite3ExampleInit),
        name: 'sqlite_example',
        onRegister: (ext) {
          ext.execute(
            'SELECT example_init(?, ?)',
            parameters: ['table_name', 'column_name'],
          );
        },
      );
}
```

`onRegister` is synchronous. Calls to `ext.execute(...)` enqueue setup SQL;
they do not return rows and there is nothing to `await`. resqlite executes the
queued setup during `Database.open`, after native extension loading and before
the database is returned. Native open work runs on one temporary open isolate,
including extension load/setup, so heavy setup does not block the caller
isolate.

The default scope is `ResqliteConnectionScope.all`, which runs on the writer and
every reader connection. Use `ResqliteConnectionScope.writer` for writer-only
PRAGMAs or temporary writer state, and `ResqliteConnectionScope.readers` for
reader-only state.

Each `execute` call must contain exactly one SQL statement. Use multiple calls
for multi-step setup so resqlite can preserve order and report the failing
extension and statement. Passing two extension values with the same native
entrypoint is rejected; combine their setup in one extension value instead.

Prefer domain-specific options over exposing raw setup for common cases. The
vector wrapper follows that pattern:

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

For setup that depends on schema created by migrations, create the schema first,
close the bootstrap connection, then reopen with the extension setup configured.
Deferred setup on an already-open database can be considered later, but the
current API keeps extension initialization deterministic at open time.

## Compatibility contract

An extension package must expose an init function with SQLite's loadable
extension signature:

```c
int sqlite3_example_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
);
```

The native code should be compiled as a SQLite extension, not as another Dart
SQLite wrapper. It must be ABI-compatible with the SQLite image resqlite ships,
and it should not bundle or initialize a second SQLite database library for its
SQL registration path.

Use `@Native(symbol: ...)` explicitly. Extension package names, Dart external
function names, and native exported symbols often differ, and explicit symbols
avoid fragile name inference.

## Escape hatches

Most companion packages should use `Native.addressOf` with
`ResqliteExtensionEntrypoint`. Dart requires `Native.addressOf` to see the
`@Native` function directly, so resqlite intentionally exports the short
`ResqliteExtensionEntrypoint` typedef instead of hiding that call behind an
unchecked helper.

For lower-level integrations, resqlite also exposes:

```dart
ResqliteExtension.fromAddress(pointer, name: 'example');
ResqliteExtension.inLibrary(library, 'sqlite3_example_init');
```

Use these when an application or package resolves the native entrypoint outside
of a generated `@Native` binding.

## Package shape

Prefer one package per native extension. Native assets are selected at the
package boundary, and extension sizes vary enough that a single umbrella
package would make bundle size and licensing harder to reason about.

A documentation-only index package could be useful later, but it should not
eagerly depend on every extension binary.
