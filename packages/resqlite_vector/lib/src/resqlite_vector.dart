import 'dart:ffi';

import 'package:resqlite/resqlite.dart';

@Native<Int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)>(
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
    Native.addressOf<NativeFunction<ResqliteExtensionInitNative>>(
      sqlite3VectorInit,
    ),
    name: 'sqlite_vector',
  );
}
