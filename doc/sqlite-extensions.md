# SQLite extension authoring

resqlite extensions use SQLite's standard native extension entrypoint ABI, but
they load through resqlite's database-pool API instead of `package:sqlite3`.

That means an app opts in when opening the database:

```dart
final db = await Database.open(
  'app.db',
  extensions: [sqliteVectorExtension()],
);
```

The extension is registered on the writer connection and every reader
connection in that pool. Other resqlite databases opened without the extension
do not see its SQL functions, collations, or virtual tables.

Internally, resqlite temporarily registers the native entrypoints with
`sqlite3_auto_extension()` while it opens the pool, then cancels those
registrations before returning. SQLite's auto-extension list is process-global
for a SQLite image, so resqlite serializes that register/open/cancel sequence
and de-dupes repeated entrypoint pointers before crossing into C.

## How this compares to package:sqlite3

`package:sqlite3` exposes `sqlite3.ensureExtensionLoaded(extension)`, which
registers an entrypoint globally for future connections in that SQLite image.
That is convenient for a single connection API, but it makes the load point a
process-level side effect.

resqlite's public API keeps the extension list attached to `Database.open`.
This is a better fit for resqlite because a `Database` owns a writer/reader
connection pool. Callers can see the extension set at the same place they see
the path, encryption key, and other connection-level choices.

## Companion package template

A companion package should depend on `resqlite`, not `sqlite3`.

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

ResqliteExtension sqliteExampleExtension() {
  return ResqliteExtension(
    Native.addressOf<ResqliteExtensionEntrypoint>(sqlite3ExampleInit),
    name: 'sqlite_example',
  );
}
```

The package's `hook/build.dart` should compile or bundle the extension as a
native asset and export the asset id used by `@Native`. Existing wrappers in
this repo, such as `packages/resqlite_vector` and `packages/resqlite_js`, use
this pattern.

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

These mirror the useful parts of `package:sqlite3`'s `SqliteExtension` API while
preserving resqlite's open-scoped loading semantics.

## Package shape

Prefer one package per native extension. Native assets are selected at the
package boundary, and extension sizes vary enough that a single umbrella
package would make bundle size and licensing harder to reason about.

A documentation-only index package could be useful later, but it should not
eagerly depend on every extension binary.
