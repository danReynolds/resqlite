import 'dart:ffi';

import 'package:resqlite/resqlite.dart';

@Native<Int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)>(
  assetId: 'package:resqlite_js/src/native/sqlite_js_extension.dart',
  symbol: 'sqlite3_js_init',
)
external int sqlite3JsInit(
  Pointer<Void> db,
  Pointer<Void> pzErrMsg,
  Pointer<Void> pApi,
);

/// Loads SQLite JS on every connection opened by resqlite.
ResqliteExtension sqliteJsExtension() {
  return ResqliteExtension(
    Native.addressOf<NativeFunction<ResqliteExtensionInitNative>>(
      sqlite3JsInit,
    ),
    name: 'sqlite_js',
  );
}
