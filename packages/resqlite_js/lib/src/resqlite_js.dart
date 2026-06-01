import 'dart:ffi';

import 'package:resqlite/resqlite.dart';

@Native<ResqliteExtensionInitNative>(
  assetId: 'package:resqlite_js/src/native/sqlite_js_extension.dart',
  symbol: 'sqlite3_js_init',
)
external int sqlite3JsInit(
  Pointer<Void> db,
  Pointer<Void> pzErrMsg,
  Pointer<Void> pApi,
);

/// Loads SQLite JS on every connection opened by resqlite.
ResqliteExtension sqliteJsExtension({ResqliteExtensionRegister? onRegister}) {
  return ResqliteExtension(
    Native.addressOf<ResqliteExtensionEntrypoint>(sqlite3JsInit),
    name: 'sqlite_js',
    onRegister: onRegister,
  );
}
