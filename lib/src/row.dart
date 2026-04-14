import 'dart:collection';

/// Column metadata shared across all rows in a [ResultSet].
///
/// Created once per query and reused by every [Row]. Contains the column
/// names and a precomputed name-to-index map for O(1) lookups.
final class RowSchema {
  RowSchema(this.names) : _indexByName = {
    for (var i = 0; i < names.length; i++) names[i]: i,
  };

  /// Column names in query order, matching the SELECT clause.
  final List<String> names;
  final Map<String, int> _indexByName;

  /// The number of columns in this schema.
  int get columnCount => names.length;

  /// Returns the column index for [name], or -1 if not found.
  int indexOf(String name) => _indexByName[name] ?? -1;
}

/// A query result set backed by a flat values list.
///
/// Implements `List<Row>` (and therefore `List<Map<String, Object?>>`)
/// with lazy [Row] creation — accessing `result[i]` creates a lightweight
/// view on demand rather than materializing all rows upfront.
///
/// ```dart
/// final results = await db.select('SELECT id, name FROM users');
/// print(results.length);       // row count
/// print(results[0]['name']);    // lazy Row created here
/// ```
///
/// This design minimizes the object count for isolate transfer — only the
/// flat values list, [RowSchema], and the [ResultSet] wrapper cross the
/// isolate boundary. [Row] objects are created on the receiving side.
final class ResultSet with ListMixin<Row> {
  ResultSet(this._values, this._schema, this._rowCount);

  final List<Object?> _values;
  final RowSchema _schema;
  final int _rowCount;

  @override
  int get length => _rowCount;

  @override
  set length(int newLength) => throw UnsupportedError('Fixed-length list');

  @override
  Row operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return Row._(_values, _schema, index * _schema.columnCount);
  }

  @override
  void operator []=(int index, Row value) =>
      throw UnsupportedError('Unmodifiable list');
}

/// A single query result row.
///
/// Implements `Map<String, Object?>` so you can use familiar map syntax:
///
/// ```dart
/// final row = results[0];
/// print(row['name']);           // column access by name
/// print(row.containsKey('id')); // true
/// print(row.keys);              // column names
/// ```
///
/// Rows are immutable views over the shared [ResultSet] values list.
/// Use `Map<String, Object?>.from(row)` if you need a mutable copy.
///
/// Implements `Map<String, Object?>` for compatibility with standard Dart
/// database patterns. Created lazily by [ResultSet] on access — not
/// transferred across isolates.
final class Row with MapMixin<String, Object?> {
  Row._(this._values, this._schema, this._offset);

  final List<Object?> _values;
  final RowSchema _schema;
  final int _offset;

  @override
  Object? operator [](Object? key) {
    if (key is! String) return null;
    final idx = _schema.indexOf(key);
    if (idx < 0) return null;
    return _values[_offset + idx];
  }

  @override
  bool containsKey(Object? key) =>
      key is String && _schema._indexByName.containsKey(key);

  @override
  bool containsValue(Object? value) {
    final end = _offset + _schema.columnCount;
    for (var i = _offset; i < end; i++) {
      if (_values[i] == value) return true;
    }
    return false;
  }

  @override
  int get length => _schema.columnCount;

  @override
  bool get isEmpty => _schema.columnCount == 0;

  @override
  bool get isNotEmpty => _schema.columnCount != 0;

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('Unmodifiable row');

  @override
  Object? remove(Object? key) =>
      throw UnsupportedError('Unmodifiable row');

  @override
  void clear() => throw UnsupportedError('Unmodifiable row');

  @override
  Iterable<String> get keys => _schema.names;

  @override
  Iterable<Object?> get values => _RowValues(this);

  @override
  Iterable<MapEntry<String, Object?>> get entries => _RowEntries(this);

  @override
  void forEach(void Function(String key, Object? value) action) {
    final names = _schema.names;
    for (var i = 0; i < names.length; i++) {
      action(names[i], _values[_offset + i]);
    }
  }
}

final class _RowValues extends IterableBase<Object?> {
  _RowValues(this._row);

  final Row _row;

  @override
  Iterator<Object?> get iterator => _RowValueIterator(_row);

  @override
  int get length => _row._schema.columnCount;

  @override
  bool contains(Object? element) => _row.containsValue(element);
}

final class _RowValueIterator implements Iterator<Object?> {
  _RowValueIterator(this._row);

  final Row _row;
  int _index = -1;

  @override
  Object? get current =>
      _index < 0 ? null : _row._values[_row._offset + _index];

  @override
  bool moveNext() {
    final next = _index + 1;
    if (next >= _row._schema.columnCount) {
      _index = _row._schema.columnCount;
      return false;
    }
    _index = next;
    return true;
  }
}

final class _RowEntries extends IterableBase<MapEntry<String, Object?>> {
  _RowEntries(this._row);

  final Row _row;

  @override
  Iterator<MapEntry<String, Object?>> get iterator => _RowEntryIterator(_row);

  @override
  int get length => _row._schema.columnCount;
}

final class _RowEntryIterator implements Iterator<MapEntry<String, Object?>> {
  _RowEntryIterator(this._row);

  final Row _row;
  int _index = -1;

  @override
  MapEntry<String, Object?> get current {
    if (_index < 0) {
      throw StateError('No element');
    }
    return MapEntry(
      _row._schema.names[_index],
      _row._values[_row._offset + _index],
    );
  }

  @override
  bool moveNext() {
    final next = _index + 1;
    if (next >= _row._schema.columnCount) {
      _index = _row._schema.columnCount;
      return false;
    }
    _index = next;
    return true;
  }
}
