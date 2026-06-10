/// Tier-1 incremental view maintenance for streams (exp 160).
///
/// A stream is *admitted* when its query falls inside a deliberately tiny
/// grammar whose semantics this module can mirror exactly:
///
///   SELECT <bare columns | *> FROM <table>
///     [WHERE <col> <op> <int> (AND ...)*]
///     [ORDER BY <pk> [ASC]]
///
/// with every comparison on INTEGER-typed values only, the table having a
/// single-column `INTEGER PRIMARY KEY` (a rowid alias), the key column in
/// the projection, and either an `ORDER BY <pk>` or a `pk = ?` equality
/// predicate (so result order is fully determined). Everything outside the
/// grammar simply stays on the existing re-query path — a classifier miss
/// costs performance, never correctness.
///
/// For admitted streams, the engine maintains the materialized result by
/// applying the writer's row deltas:
///
///   * a delta row failing the predicate before AND after the write is a
///     *proven miss* — no reader dispatch, no SQLite, no hash;
///   * in-window updates / entries / departures patch the cached rows
///     locally and emit;
///   * anything unprovable (type mismatch, cache inconsistency, schema
///     drift) bails to the normal re-query path.
library;

import 'row_deltas.dart';

// ---------------------------------------------------------------------------
// Query shape
// ---------------------------------------------------------------------------

final class IvmPredicate {
  const IvmPredicate(this.columnIndex, this.op, this.value);

  /// Table column index (cid from `PRAGMA table_info`).
  final int columnIndex;

  /// One of `=`, `<`, `<=`, `>`, `>=` (== normalizes to =).
  final String op;

  /// Comparison constant, resolved from a literal or the stream's fixed
  /// bind parameters at classification time.
  final int value;

  bool evaluate(int cell) => switch (op) {
    '=' => cell == value,
    '<' => cell < value,
    '<=' => cell <= value,
    '>' => cell > value,
    '>=' => cell >= value,
    _ => false,
  };
}

final class IvmShape {
  const IvmShape({
    required this.table,
    required this.predicates,
    required this.projection,
    required this.pkColumnIndex,
    required this.pkOutputName,
    required this.tableColumnCount,
  });

  final String table;
  final List<IvmPredicate> predicates;

  /// Output column name → table column index, in projection order.
  final List<(String, int)> projection;

  /// Table column index of the INTEGER PRIMARY KEY (rowid alias).
  final int pkColumnIndex;

  /// The pk's name as it appears in emitted row maps.
  final String pkOutputName;

  /// `PRAGMA table_info` row count at classification time. A delta whose
  /// column count differs means the schema changed under us — demote.
  final int tableColumnCount;
}

// ---------------------------------------------------------------------------
// Classifier
// ---------------------------------------------------------------------------

/// Classify a stream query against the tier-1 grammar.
///
/// [tableInfo] is the result of `PRAGMA table_info(table)`. Returns `null`
/// when the query is not admissible.
IvmShape? classifyIvmQuery(
  String sql,
  List<Object?> params,
  String table,
  List<Map<String, Object?>> tableInfo,
) {
  // Table metadata: name (declared case) → cid, and the single INTEGER
  // PRIMARY KEY column.
  if (tableInfo.isEmpty || tableInfo.length > 64) return null;
  final cidByLowerName = <String, int>{};
  final declaredNameByCid = <int, String>{};
  var pkCid = -1;
  var pkCount = 0;
  for (final col in tableInfo) {
    final cid = col['cid'];
    final name = col['name'];
    final type = col['type'];
    final pk = col['pk'];
    if (cid is! int || name is! String || pk is! int) return null;
    cidByLowerName[name.toLowerCase()] = cid;
    declaredNameByCid[cid] = name;
    if (pk > 0) {
      pkCount++;
      if (pk == 1 && type is String && type.toUpperCase() == 'INTEGER') {
        pkCid = cid;
      }
    }
  }
  // Exactly one pk column, and it must be the INTEGER rowid alias.
  if (pkCount != 1 || pkCid < 0) return null;

  final tokens = _tokenize(sql);
  if (tokens == null) return null;
  final cursor = _Cursor(tokens);

  if (!cursor.takeKeyword('select')) return null;

  // Projection.
  final projection = <(String, int)>[];
  if (cursor.takeSymbol('*')) {
    for (var cid = 0; cid < tableInfo.length; cid++) {
      final name = declaredNameByCid[cid];
      if (name == null) return null;
      projection.add((name, cid));
    }
  } else {
    while (true) {
      final ident = cursor.takeIdent();
      if (ident == null) return null;
      final cid = cidByLowerName[ident.toLowerCase()];
      if (cid == null) return null;
      // Bare column reference: SQLite names the result column as written.
      projection.add((ident, cid));
      if (!cursor.takeSymbol(',')) break;
    }
  }

  if (!cursor.takeKeyword('from')) return null;
  final fromIdent = cursor.takeIdent();
  if (fromIdent == null || fromIdent.toLowerCase() != table.toLowerCase()) {
    return null;
  }

  // WHERE conjunction.
  final predicates = <IvmPredicate>[];
  var paramIndex = 0;
  var hasPkEquality = false;
  if (cursor.takeKeyword('where')) {
    while (true) {
      final ident = cursor.takeIdent();
      if (ident == null) return null;
      final cid = cidByLowerName[ident.toLowerCase()];
      if (cid == null) return null;
      final op = cursor.takeOperator();
      if (op == null) return null;
      final int value;
      if (cursor.takeSymbol('?')) {
        if (paramIndex >= params.length) return null;
        final param = params[paramIndex++];
        if (param is! int) return null;
        value = param;
      } else {
        final literal = cursor.takeIntLiteral();
        if (literal == null) return null;
        value = literal;
      }
      predicates.add(IvmPredicate(cid, op, value));
      if (op == '=' && cid == pkCid) hasPkEquality = true;
      if (!cursor.takeKeyword('and')) break;
    }
  }
  // Every bind parameter must be consumed by the WHERE clause — a `?`
  // anywhere else was already rejected by the grammar, but a surplus
  // parameter means the SQL used it somewhere we didn't model.
  if (paramIndex != params.length) return null;

  // ORDER BY — only the pk, only ascending.
  var orderedByPk = false;
  if (cursor.takeKeyword('order')) {
    if (!cursor.takeKeyword('by')) return null;
    final ident = cursor.takeIdent();
    if (ident == null) return null;
    if (cidByLowerName[ident.toLowerCase()] != pkCid) return null;
    cursor.takeKeyword('asc'); // optional
    orderedByPk = true;
  }

  cursor.takeSymbol(';');
  if (!cursor.atEnd) return null;

  // Result order must be fully determined: either ordered by pk, or pinned
  // to at most one row by a pk equality predicate.
  if (!orderedByPk && !hasPkEquality) return null;

  // The pk must be projected so cached rows can be keyed.
  String? pkOutputName;
  for (final (name, cid) in projection) {
    if (cid == pkCid) {
      pkOutputName = name;
      break;
    }
  }
  if (pkOutputName == null) return null;

  return IvmShape(
    table: table,
    predicates: predicates,
    projection: projection,
    pkColumnIndex: pkCid,
    pkOutputName: pkOutputName,
    tableColumnCount: tableInfo.length,
  );
}

// ---------------------------------------------------------------------------
// Tokenizer — strict by construction: any unexpected character rejects.
// ---------------------------------------------------------------------------

final class _Token {
  const _Token(this.kind, this.text, [this.intValue = 0]);
  final int kind; // 0 ident/keyword, 1 int literal, 2 symbol/operator
  final String text;
  final int intValue;
}

List<_Token>? _tokenize(String sql) {
  final tokens = <_Token>[];
  var i = 0;
  while (i < sql.length) {
    final c = sql.codeUnitAt(i);
    // Whitespace.
    if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
      i++;
      continue;
    }
    // Identifier / keyword.
    if (_isIdentStart(c)) {
      final start = i;
      while (i < sql.length && _isIdentChar(sql.codeUnitAt(i))) {
        i++;
      }
      tokens.add(_Token(0, sql.substring(start, i)));
      continue;
    }
    // Integer literal (optionally negative).
    if (_isDigit(c) ||
        (c == 0x2d /* - */ &&
            i + 1 < sql.length &&
            _isDigit(sql.codeUnitAt(i + 1)))) {
      final start = i;
      i++;
      while (i < sql.length && _isDigit(sql.codeUnitAt(i))) {
        i++;
      }
      final text = sql.substring(start, i);
      final value = int.tryParse(text);
      if (value == null) return null;
      tokens.add(_Token(1, text, value));
      continue;
    }
    // Operators / symbols.
    switch (c) {
      case 0x2a: // *
        tokens.add(const _Token(2, '*'));
        i++;
      case 0x2c: // ,
        tokens.add(const _Token(2, ','));
        i++;
      case 0x3f: // ?
        tokens.add(const _Token(2, '?'));
        i++;
      case 0x3b: // ;
        tokens.add(const _Token(2, ';'));
        i++;
      case 0x3d: // = or ==
        i++;
        if (i < sql.length && sql.codeUnitAt(i) == 0x3d) i++;
        tokens.add(const _Token(2, '='));
      case 0x3c: // < or <=
        i++;
        if (i < sql.length && sql.codeUnitAt(i) == 0x3d) {
          tokens.add(const _Token(2, '<='));
          i++;
        } else {
          tokens.add(const _Token(2, '<'));
        }
      case 0x3e: // > or >=
        i++;
        if (i < sql.length && sql.codeUnitAt(i) == 0x3d) {
          tokens.add(const _Token(2, '>='));
          i++;
        } else {
          tokens.add(const _Token(2, '>'));
        }
      default:
        // Anything else (quotes, dots, parens, arithmetic, ...) is outside
        // the grammar.
        return null;
    }
  }
  return tokens;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isIdentStart(int c) =>
    (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || c == 0x5f;
bool _isIdentChar(int c) => _isIdentStart(c) || _isDigit(c);

/// SQL keywords that may never appear as bare identifiers in an admitted
/// query — their presence anywhere outside their grammar position rejects.
const _reservedAsIdent = {
  'select',
  'from',
  'where',
  'and',
  'or',
  'not',
  'order',
  'by',
  'asc',
  'desc',
  'limit',
  'offset',
  'group',
  'having',
  'join',
  'left',
  'inner',
  'outer',
  'cross',
  'union',
  'except',
  'intersect',
  'distinct',
  'as',
  'in',
  'between',
  'like',
  'is',
  'null',
  'case',
  'when',
  'collate',
  'glob',
  'exists',
};

final class _Cursor {
  _Cursor(this.tokens);
  final List<_Token> tokens;
  int pos = 0;

  bool get atEnd => pos >= tokens.length;

  bool takeKeyword(String keyword) {
    if (atEnd) return false;
    final t = tokens[pos];
    if (t.kind == 0 && t.text.toLowerCase() == keyword) {
      pos++;
      return true;
    }
    return false;
  }

  String? takeIdent() {
    if (atEnd) return null;
    final t = tokens[pos];
    if (t.kind != 0) return null;
    if (_reservedAsIdent.contains(t.text.toLowerCase())) return null;
    pos++;
    return t.text;
  }

  bool takeSymbol(String symbol) {
    if (atEnd) return false;
    final t = tokens[pos];
    if (t.kind == 2 && t.text == symbol) {
      pos++;
      return true;
    }
    return false;
  }

  String? takeOperator() {
    if (atEnd) return null;
    final t = tokens[pos];
    if (t.kind == 2 &&
        (t.text == '=' ||
            t.text == '<' ||
            t.text == '<=' ||
            t.text == '>' ||
            t.text == '>=')) {
      pos++;
      return t.text;
    }
    return null;
  }

  int? takeIntLiteral() {
    if (atEnd) return null;
    final t = tokens[pos];
    if (t.kind != 1) return null;
    pos++;
    return t.intValue;
  }
}

// ---------------------------------------------------------------------------
// Maintained state + delta application
// ---------------------------------------------------------------------------

enum IvmOutcome {
  /// All deltas were proven irrelevant — nothing to emit, no re-query.
  unchanged,

  /// The cached result was patched; the caller should emit it.
  applied,

  /// Something was unprovable or inconsistent — fall back to re-query.
  bail,
}

final class IvmState {
  IvmState(this.shape);

  final IvmShape shape;

  /// Materialized rows, ascending by pk. `null` until built from the
  /// entry's last result (and after any bail/fallback re-query).
  List<Map<String, Object?>>? rows;

  /// Sorted pk values parallel to [rows].
  List<int>? keys;

  /// Build the maintained cache from the last emitted result. Returns
  /// false (leaving the cache unset) when the rows cannot be keyed.
  bool rebuild(List<Map<String, Object?>> lastResult) {
    final newRows = List<Map<String, Object?>>.generate(
      lastResult.length,
      (i) => Map<String, Object?>.of(lastResult[i]),
      growable: true,
    );
    final newKeys = <int>[];
    for (final row in newRows) {
      final key = row[shape.pkOutputName];
      if (key is! int) return false;
      if (newKeys.isNotEmpty && key <= newKeys.last) {
        // Result was not strictly ascending by pk — never patch it.
        return false;
      }
      newKeys.add(key);
    }
    rows = newRows;
    keys = newKeys;
    return true;
  }

  /// Apply [deltas] (already filtered to this shape's table).
  ///
  /// On [IvmOutcome.applied], [rows] is a *fresh* list (previously emitted
  /// lists are never mutated). On [IvmOutcome.bail], the cache is cleared.
  IvmOutcome apply(List<RowDelta> deltas) {
    var currentRows = rows;
    var currentKeys = keys;
    if (currentRows == null || currentKeys == null) return _bail();

    var mutated = false;
    List<Map<String, Object?>> workRows = currentRows;
    List<int> workKeys = currentKeys;

    void ensureMutable() {
      if (!mutated) {
        workRows = List<Map<String, Object?>>.of(workRows);
        workKeys = List<int>.of(workKeys);
        mutated = true;
      }
    }

    bool? evalPredicates(List<Object?> values) {
      for (final pred in shape.predicates) {
        final cell = values[pred.columnIndex];
        if (cell == null) return false; // SQL comparison with NULL → no match
        if (cell is! int) return null; // unprovable type
        if (!pred.evaluate(cell)) return false;
      }
      return true;
    }

    bool applyOne(
      bool hasOld,
      bool hasNew,
      int oldKey,
      int newKey,
      List<Object?>? oldValues,
      List<Object?>? newValues,
    ) {
      final pOldOrNull = hasOld ? evalPredicates(oldValues!) : false;
      final pNewOrNull = hasNew ? evalPredicates(newValues!) : false;
      if (pOldOrNull == null || pNewOrNull == null) return false;
      final pOld = pOldOrNull;
      final pNew = pNewOrNull;

      final oldIdx = _binarySearch(workKeys, oldKey);
      if (!pOld && !pNew) {
        // Proven miss — but if the cache claims the row is present, it is
        // out of sync with reality.
        if (hasOld && oldIdx >= 0) return false;
        return true;
      }

      if (pOld && pNew) {
        // Row stays in the result; keys are equal here (rowid changes were
        // split by the caller).
        if (oldIdx < 0) return false;
        final patched = _projectRow(newValues);
        if (patched == null) return false;
        if (_projectedEquals(workRows[oldIdx], patched)) return true;
        ensureMutable();
        workRows[oldIdx] = patched;
        return true;
      }

      if (pOld) {
        // Row leaves the result.
        if (oldIdx < 0) return false;
        ensureMutable();
        workRows.removeAt(oldIdx);
        workKeys.removeAt(oldIdx);
        return true;
      }

      // Row enters the result.
      final newIdx = _binarySearch(workKeys, newKey);
      if (newIdx >= 0) return false;
      final inserted = _projectRow(newValues!);
      if (inserted == null) return false;
      ensureMutable();
      final insertAt = -(newIdx + 1);
      workRows.insert(insertAt, inserted);
      workKeys.insert(insertAt, newKey);
      return true;
    }

    for (final delta in deltas) {
      // Schema drift guard: the capture's column count must match the
      // shape's view of the table.
      final values = delta.newValues ?? delta.oldValues;
      if (values == null || values.length != shape.tableColumnCount) {
        return _bail();
      }
      if (delta.oldValues != null &&
          delta.oldValues!.length != shape.tableColumnCount) {
        return _bail();
      }

      final bool ok;
      if (delta.op == deltaOpUpdate && delta.oldRowid != delta.newRowid) {
        // Rowid changed: split into departure + entry.
        ok =
            applyOne(
              true,
              false,
              delta.oldRowid,
              delta.oldRowid,
              delta.oldValues,
              null,
            ) &&
            applyOne(
              false,
              true,
              delta.newRowid,
              delta.newRowid,
              null,
              delta.newValues,
            );
      } else {
        ok = applyOne(
          delta.oldValues != null,
          delta.newValues != null,
          delta.oldRowid,
          delta.newRowid,
          delta.oldValues,
          delta.newValues,
        );
      }
      if (!ok) return _bail();
    }

    if (!mutated) return IvmOutcome.unchanged;
    rows = workRows;
    keys = workKeys;
    return IvmOutcome.applied;
  }

  IvmOutcome _bail() {
    rows = null;
    keys = null;
    return IvmOutcome.bail;
  }

  /// Build an emitted row from table-indexed [values] via the projection.
  /// Returns null when the pk cell is not an int (unprovable).
  Map<String, Object?>? _projectRow(List<Object?> values) {
    if (values[shape.pkColumnIndex] is! int) return null;
    final row = <String, Object?>{};
    for (final (name, cid) in shape.projection) {
      row[name] = values[cid];
    }
    return row;
  }

  /// Whether two projected rows are provably identical. Non-primitive
  /// values (blobs) compare by identity, which can only produce a false
  /// "changed" — never a false "unchanged".
  bool _projectedEquals(Map<String, Object?> a, Map<String, Object?> b) {
    for (final (name, _) in shape.projection) {
      if (a[name] != b[name]) return false;
    }
    return true;
  }
}

/// Standard binary search: index when found, `-(insertion point) - 1`
/// when absent.
int _binarySearch(List<int> keys, int key) {
  var lo = 0;
  var hi = keys.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final v = keys[mid];
    if (v < key) {
      lo = mid + 1;
    } else if (v > key) {
      hi = mid - 1;
    } else {
      return mid;
    }
  }
  return -(lo + 1);
}
