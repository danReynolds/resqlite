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

enum SqliteVectorType {
  float32('FLOAT32'),
  float16('FLOAT16'),
  bfloat16('BFLOAT16'),
  int8('INT8'),
  uint8('UINT8');

  const SqliteVectorType(this.optionValue);

  final String optionValue;
}

/// A vector index to initialize on every resqlite connection.
///
/// SQLite Vector requires `vector_init(table, column, options)` for each
/// connection that will use vector search. Use this when the table already
/// exists before `Database.open` returns. For migrations that create the table,
/// run the migration first and reopen the database with this index configured.
final class SqliteVectorIndex {
  SqliteVectorIndex({
    required this.table,
    required this.column,
    required this.dimension,
    this.type = SqliteVectorType.float32,
    Iterable<String> extraOptions = const [],
  }) : extraOptions = List.unmodifiable(extraOptions) {
    if (table.trim().isEmpty) {
      throw ArgumentError.value(table, 'table', 'must not be empty');
    }
    if (column.trim().isEmpty) {
      throw ArgumentError.value(column, 'column', 'must not be empty');
    }
    if (dimension <= 0) {
      throw ArgumentError.value(dimension, 'dimension', 'must be positive');
    }
  }

  final String table;
  final String column;
  final int dimension;
  final SqliteVectorType type;
  final List<String> extraOptions;

  String get options {
    return [
      'type=${type.optionValue}',
      'dimension=$dimension',
      ...extraOptions,
    ].join(',');
  }
}

/// Loads SQLite Vector on every connection opened by resqlite.
ResqliteExtension sqliteVectorExtension({
  Iterable<SqliteVectorIndex> indexes = const [],
  Iterable<ResqliteConnectionSetup> setup = const [],
}) {
  return ResqliteExtension(
    Native.addressOf<ResqliteExtensionEntrypoint>(sqlite3VectorInit),
    name: 'sqlite_vector',
    setup: [
      for (final index in indexes)
        ResqliteConnectionSetup.sql(
          'SELECT vector_init(?, ?, ?)',
          parameters: [index.table, index.column, index.options],
        ),
      ...setup,
    ],
  );
}
