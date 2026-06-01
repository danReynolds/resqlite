import 'dart:ffi';

import 'package:resqlite/resqlite.dart';

@Native<ResqliteExtensionInitNative>(
  assetId: 'package:resqlite_vector/src/native/sqlite_vector_extension.dart',
  symbol: 'sqlite3_vector_init',
)
external int sqlite3VectorInit(
  Pointer<Void> db,
  Pointer<Void> pzErrMsg,
  Pointer<Void> pApi,
);

/// Loads SQLite Vector on every connection opened by resqlite.
ResqliteExtension sqliteVectorExtension() {
  return ResqliteExtension(
    Native.addressOf<ResqliteExtensionEntrypoint>(sqlite3VectorInit),
    name: 'sqlite_vector',
  );
}
