/// Tiered incremental view maintenance for streams (exp 160).
///
/// A stream query is classified once, at registration, into one of three
/// admission modes — each strictly fail-closed (a classifier miss or an
/// unprovable condition at apply time costs a re-query, never
/// correctness):
///
/// **Full maintenance** ([IvmFullShape]): single-table SELECT of bare
/// columns whose result order is fully determined (`ORDER BY pk`,
/// `ORDER BY intCol [DESC], pk [DESC]`, or a pk-equality pin), optionally
/// windowed by `LIMIT K`. The engine maintains the materialized result
/// from row deltas: proven misses skip the reader pool entirely,
/// in-window changes patch clone-on-write and emit.
///
/// **Skip-only** ([IvmSkipShape], tier 1.5): shapes whose *results* cannot
/// be maintained (DESC without a pk tiebreak, OFFSET, DISTINCT, free
/// ORDER BY, aggregate mixes) but whose WHERE clause is still a
/// conjunction of evaluable comparisons. Deltas that fail the predicate
/// before and after the write are proven misses — no re-query; any hit or
/// unprovable cell falls back to the normal re-query path.
///
/// **Aggregates** ([IvmAggregateShape], tier 3): projections consisting
/// solely of `COUNT(*) / COUNT(col) / SUM(col) / MIN(col) / MAX(col) /
/// AVG(col) AS alias` over an evaluable (possibly empty) predicate. State
/// is seeded exactly by a one-time snapshot query at admission and then
/// maintained per delta; a departing MIN/MAX extremum falls back.
///
/// Comparison semantics are mirrored only where provably exact: INTEGER
/// cells against integer constants, and TEXT equality against string
/// constants when the table's CREATE statement contains no COLLATE clause
/// (BINARY collation; the delta decoder's strict UTF-8 decode rejects
/// malformed text upstream). Everything else stays on re-query.
library;

import 'row_deltas.dart';

// ---------------------------------------------------------------------------
// Predicates
// ---------------------------------------------------------------------------

final class IvmPredicate {
  const IvmPredicate(this.columnIndex, this.op, this.value);

  /// Table column index (cid from `PRAGMA table_info`).
  final int columnIndex;

  /// One of `=`, `<`, `<=`, `>`, `>=` (`==` normalizes to `=`; only `=`
  /// is admitted for TEXT values).
  final String op;

  /// Comparison constant: an [int], or a [String] (TEXT equality under
  /// verified BINARY collation). Resolved from a literal or the stream's
  /// fixed bind parameters at classification time.
  final Object value;

  /// Evaluates the predicate against a delta cell. Returns null when the
  /// comparison is unprovable (type mismatch with the admitted constant).
  /// A NULL cell never matches, mirroring SQL comparison semantics.
  bool? evaluate(Object? cell) {
    if (cell == null) return false;
    final value = this.value;
    if (value is int) {
      if (cell is! int) return null;
      return switch (op) {
        '=' => cell == value,
        '<' => cell < value,
        '<=' => cell <= value,
        '>' => cell > value,
        '>=' => cell >= value,
        _ => null,
      };
    }
    // TEXT equality (admission guarantees op == '=').
    if (cell is! String) return null;
    return cell == value as String;
  }
}

/// Evaluates a predicate conjunction against table-indexed [values].
/// Returns null when any term is unprovable.
bool? evaluatePredicates(List<IvmPredicate> predicates, List<Object?> values) {
  for (final pred in predicates) {
    final match = pred.evaluate(values[pred.columnIndex]);
    if (match == null) return null;
    if (!match) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Admission shapes
// ---------------------------------------------------------------------------

sealed class IvmAdmission {
  const IvmAdmission({
    required this.table,
    required this.predicates,
    required this.tableColumnCount,
  });

  final String table;
  final List<IvmPredicate> predicates;

  /// `PRAGMA table_info` row count at classification time. A delta whose
  /// column count differs means the schema changed under us — demote.
  final int tableColumnCount;
}

/// Fully-maintained result, optionally windowed by `LIMIT K`.
final class IvmFullShape extends IvmAdmission {
  const IvmFullShape({
    required super.table,
    required super.predicates,
    required super.tableColumnCount,
    required this.projection,
    required this.pkColumnIndex,
    required this.pkOutputName,
    required this.orderColumnIndex,
    required this.orderOutputName,
    required this.orderDesc,
    required this.pkDesc,
    required this.limit,
  });

  /// Output column name → table column index, in projection order.
  final List<(String, int)> projection;

  /// Table column index of the INTEGER PRIMARY KEY (rowid alias) and its
  /// name in emitted row maps.
  final int pkColumnIndex;
  final String pkOutputName;

  /// Primary order key (table cid + output name); equals the pk for
  /// `ORDER BY pk` and pk-equality shapes.
  final int orderColumnIndex;
  final String orderOutputName;
  final bool orderDesc;

  /// Tiebreak direction for the pk term.
  final bool pkDesc;

  /// Window size, or null for an unwindowed (complete) result.
  final int? limit;

  /// Compares composite sort keys per the admitted ORDER BY.
  int compareKeys((int, int) a, (int, int) b) {
    var c = a.$1.compareTo(b.$1);
    if (orderDesc) c = -c;
    if (c != 0) return c;
    c = a.$2.compareTo(b.$2);
    return pkDesc ? -c : c;
  }
}

/// Tier 1.5: predicates are evaluable but the result is not maintainable.
final class IvmSkipShape extends IvmAdmission {
  const IvmSkipShape({
    required super.table,
    required super.predicates,
    required super.tableColumnCount,
  });
}

enum IvmAggregateKind { countStar, count, sum, min, max, avg }

final class IvmAggregate {
  const IvmAggregate(this.kind, this.columnIndex, this.outputName);

  final IvmAggregateKind kind;

  /// Table column index; -1 for `COUNT(*)`.
  final int columnIndex;

  /// The `AS` alias the value is emitted under.
  final String outputName;
}

/// Tier 3: an aggregates-only projection maintained from deltas.
final class IvmAggregateShape extends IvmAdmission {
  const IvmAggregateShape({
    required super.table,
    required super.predicates,
    required super.tableColumnCount,
    required this.aggregates,
  });

  final List<IvmAggregate> aggregates;

  /// Whether exact seeding needs a snapshot query (anything beyond
  /// COUNT(*) tracks per-column non-null counts and extrema).
  bool get needsSnapshot =>
      aggregates.any((a) => a.kind != IvmAggregateKind.countStar);

  /// Distinct non-`*` aggregate column indexes, in first-seen order.
  List<int> get aggregateColumns {
    final seen = <int>{};
    final out = <int>[];
    for (final agg in aggregates) {
      if (agg.columnIndex >= 0 && seen.add(agg.columnIndex)) {
        out.add(agg.columnIndex);
      }
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Classifier
// ---------------------------------------------------------------------------

const _aggregateNames = {'count', 'sum', 'min', 'max', 'avg'};

/// Classify a stream query.
///
/// [tableInfo] is the result of `PRAGMA table_info(table)`. [createSql]
/// is the table's CREATE statement from `sqlite_master`; TEXT equality
/// predicates are admitted only when it is present and contains no
/// COLLATE clause (so every column provably uses BINARY collation).
/// Returns null when the query is not admissible in any mode.
IvmAdmission? classifyIvmQuery(
  String sql,
  List<Object?> params,
  String table,
  List<Map<String, Object?>> tableInfo, {
  String? createSql,
}) {
  if (tableInfo.isEmpty || tableInfo.length > 64) return null;
  final cidByLowerName = <String, int>{};
  final declaredNameByCid = <int, String>{};
  final typeByCid = <int, String>{};
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
    typeByCid[cid] = type is String ? type.toUpperCase() : '';
    if (pk > 0) {
      pkCount++;
      if (pk == 1 && typeByCid[cid] == 'INTEGER') {
        pkCid = cid;
      }
    }
  }
  // The pk requirements only gate full maintenance; skip/aggregate modes
  // work without a usable rowid alias.
  final hasIntPk = pkCount == 1 && pkCid >= 0;

  final allowText =
      createSql != null && !createSql.toLowerCase().contains('collate');

  final tokens = _tokenize(sql);
  if (tokens == null) return null;
  final cursor = _Cursor(tokens);

  if (!cursor.takeKeyword('select')) return null;
  final distinct = cursor.takeKeyword('distinct');

  // ---- Projection --------------------------------------------------------
  // Parsed into bare columns and/or aggregate calls. `fullEligible` decays
  // as soon as anything beyond bare projected columns appears.
  final projection = <(String, int)>[];
  final aggregates = <IvmAggregate>[];
  var sawBareColumn = false;
  var sawStar = false;

  if (cursor.takeSymbol('*')) {
    sawStar = true;
    for (var cid = 0; cid < tableInfo.length; cid++) {
      final name = declaredNameByCid[cid];
      if (name == null) return null;
      projection.add((name, cid));
    }
  } else {
    while (true) {
      final ident = cursor.takeIdent();
      if (ident == null) return null;
      if (cursor.takeSymbol('(')) {
        // Aggregate call.
        if (!_aggregateNames.contains(ident.toLowerCase())) return null;
        final IvmAggregateKind kind;
        int columnIndex;
        if (cursor.takeSymbol('*')) {
          if (ident.toLowerCase() != 'count') return null;
          kind = IvmAggregateKind.countStar;
          columnIndex = -1;
        } else {
          final argIdent = cursor.takeIdent();
          if (argIdent == null) return null;
          final cid = cidByLowerName[argIdent.toLowerCase()];
          if (cid == null) return null;
          columnIndex = cid;
          kind = switch (ident.toLowerCase()) {
            'count' => IvmAggregateKind.count,
            'sum' => IvmAggregateKind.sum,
            'min' => IvmAggregateKind.min,
            'max' => IvmAggregateKind.max,
            'avg' => IvmAggregateKind.avg,
            _ => IvmAggregateKind.count, // unreachable
          };
          // Numeric aggregates only over INTEGER-declared columns; the
          // apply path additionally bails on any non-int runtime cell.
          if (kind != IvmAggregateKind.count &&
              typeByCid[cid] != 'INTEGER') {
            return null;
          }
        }
        if (!cursor.takeSymbol(')')) return null;
        // Require an explicit alias so emitted names never depend on
        // SQLite's expression-naming rules.
        if (!cursor.takeKeyword('as')) return null;
        final alias = cursor.takeIdent();
        if (alias == null) return null;
        aggregates.add(IvmAggregate(kind, columnIndex, alias));
      } else {
        final cid = cidByLowerName[ident.toLowerCase()];
        if (cid == null) return null;
        sawBareColumn = true;
        if (cursor.takeKeyword('as')) {
          final alias = cursor.takeIdent();
          if (alias == null) return null;
          projection.add((alias, cid));
        } else {
          // Bare column reference: SQLite names the result column as
          // written.
          projection.add((ident, cid));
        }
      }
      if (!cursor.takeSymbol(',')) break;
    }
  }

  if (!cursor.takeKeyword('from')) return null;
  final fromIdent = cursor.takeIdent();
  if (fromIdent == null || fromIdent.toLowerCase() != table.toLowerCase()) {
    return null;
  }

  // ---- WHERE -------------------------------------------------------------
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
      final Object value;
      if (cursor.takeSymbol('?')) {
        if (paramIndex >= params.length) return null;
        final param = params[paramIndex++];
        if (param is int) {
          value = param;
        } else if (param is String) {
          if (!allowText || op != '=') return null;
          value = param;
        } else {
          return null;
        }
      } else {
        final literal = cursor.takeIntLiteral();
        if (literal != null) {
          value = literal;
        } else {
          final text = cursor.takeStringLiteral();
          if (text == null) return null;
          if (!allowText || op != '=') return null;
          value = text;
        }
      }
      predicates.add(IvmPredicate(cid, op, value));
      if (op == '=' && cid == pkCid && value is int) hasPkEquality = true;
      if (!cursor.takeKeyword('and')) break;
    }
  }

  // ---- ORDER BY ----------------------------------------------------------
  final orderColumns = <(int, bool)>[]; // (cid, desc)
  if (cursor.takeKeyword('order')) {
    if (!cursor.takeKeyword('by')) return null;
    while (true) {
      final ident = cursor.takeIdent();
      if (ident == null) return null;
      final cid = cidByLowerName[ident.toLowerCase()];
      if (cid == null) return null;
      var desc = false;
      if (cursor.takeKeyword('desc')) {
        desc = true;
      } else {
        cursor.takeKeyword('asc');
      }
      orderColumns.add((cid, desc));
      if (!cursor.takeSymbol(',')) break;
    }
  }

  // ---- LIMIT / OFFSET ----------------------------------------------------
  int? limit;
  var sawLimit = false;
  var sawOffset = false;
  if (cursor.takeKeyword('limit')) {
    sawLimit = true;
    if (cursor.takeSymbol('?')) {
      if (paramIndex >= params.length) return null;
      final param = params[paramIndex++];
      if (param is! int) return null;
      limit = param;
    } else {
      limit = cursor.takeIntLiteral();
      if (limit == null) return null;
    }
    if (cursor.takeKeyword('offset')) {
      sawOffset = true;
      if (cursor.takeSymbol('?')) {
        if (paramIndex >= params.length) return null;
        paramIndex++;
      } else if (cursor.takeIntLiteral() == null) {
        return null;
      }
    }
  }

  cursor.takeSymbol(';');
  if (!cursor.atEnd) return null;
  // Every bind parameter must have been consumed by a position we model.
  if (paramIndex != params.length) return null;

  IvmSkipShape? skipShape() => predicates.isEmpty
      ? null
      : IvmSkipShape(
          table: table,
          predicates: predicates,
          tableColumnCount: tableInfo.length,
        );

  // ---- Aggregate admission ----------------------------------------------
  if (aggregates.isNotEmpty) {
    final aggregateAdmissible =
        !sawBareColumn &&
        !sawStar &&
        !distinct &&
        orderColumns.isEmpty &&
        !sawLimit;
    if (aggregateAdmissible) {
      return IvmAggregateShape(
        table: table,
        predicates: predicates,
        tableColumnCount: tableInfo.length,
        aggregates: aggregates,
      );
    }
    return skipShape();
  }

  // ---- Full-maintenance admission ----------------------------------------
  var fullEligible = hasIntPk && !distinct && !sawOffset;
  // Every predicate value must be provable; TEXT values were already
  // gated, so nothing further here.

  int orderCid = pkCid;
  var orderDesc = false;
  var pkDesc = false;
  if (fullEligible) {
    switch (orderColumns) {
      case []:
        // No ORDER BY: result order is only determined when pinned to at
        // most one row.
        if (!hasPkEquality) fullEligible = false;
      case [(final cid, final desc)] when cid == pkCid:
        orderCid = pkCid;
        orderDesc = desc;
        pkDesc = desc;
      case [(final cid, final desc), (final cid2, final desc2)]
          when cid2 == pkCid && cid != pkCid:
        if (typeByCid[cid] != 'INTEGER') {
          fullEligible = false;
        } else {
          orderCid = cid;
          orderDesc = desc;
          pkDesc = desc2;
        }
      default:
        fullEligible = false;
    }
  }

  // The pk (and a non-pk order column) must be projected so cached rows
  // can be keyed and re-sorted.
  String? pkOutputName;
  String? orderOutputName;
  if (fullEligible) {
    for (final (name, cid) in projection) {
      if (cid == pkCid) pkOutputName ??= name;
      if (cid == orderCid) orderOutputName ??= name;
    }
    if (pkOutputName == null || orderOutputName == null) {
      fullEligible = false;
    }
  }

  if (fullEligible && sawLimit) {
    final k = limit!;
    if (hasPkEquality) {
      // LIMIT over a ≤1-row pin is a no-op; treat as unwindowed.
      limit = null;
    } else if (k <= 0 || k > 1024 || orderColumns.isEmpty) {
      fullEligible = false;
    }
  }

  if (fullEligible) {
    return IvmFullShape(
      table: table,
      predicates: predicates,
      tableColumnCount: tableInfo.length,
      projection: projection,
      pkColumnIndex: pkCid,
      pkOutputName: pkOutputName!,
      orderColumnIndex: orderCid,
      orderOutputName: orderOutputName!,
      orderDesc: orderDesc,
      pkDesc: pkDesc,
      limit: sawLimit ? limit : null,
    );
  }
  return skipShape();
}

// ---------------------------------------------------------------------------
// Tokenizer — strict by construction: any unexpected character rejects.
// ---------------------------------------------------------------------------

final class _Token {
  const _Token(this.kind, this.text, [this.intValue = 0]);
  final int kind; // 0 ident/keyword, 1 int literal, 2 symbol/op, 3 string
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
    // Single-quoted string literal with '' escaping.
    if (c == 0x27) {
      i++;
      final buf = StringBuffer();
      var closed = false;
      while (i < sql.length) {
        final ch = sql.codeUnitAt(i);
        if (ch == 0x27) {
          if (i + 1 < sql.length && sql.codeUnitAt(i + 1) == 0x27) {
            buf.writeCharCode(0x27);
            i += 2;
            continue;
          }
          i++;
          closed = true;
          break;
        }
        buf.writeCharCode(ch);
        i++;
      }
      if (!closed) return null;
      tokens.add(_Token(3, buf.toString()));
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
      case 0x28: // (
        tokens.add(const _Token(2, '('));
        i++;
      case 0x29: // )
        tokens.add(const _Token(2, ')'));
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
        // Anything else (double quotes, dots, arithmetic, ...) is outside
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
  'over',
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

  String? takeStringLiteral() {
    if (atEnd) return null;
    final t = tokens[pos];
    if (t.kind != 3) return null;
    pos++;
    return t.text;
  }
}

// ---------------------------------------------------------------------------
// Maintained state
// ---------------------------------------------------------------------------

enum IvmOutcome {
  /// All deltas were proven irrelevant — nothing to emit, no re-query.
  unchanged,

  /// The cached state was patched; the caller should emit.
  applied,

  /// Something was unprovable or inconsistent — fall back to re-query.
  bail,
}

sealed class IvmState {
  IvmAdmission get shape;
}

/// Tier 1.5 state: nothing cached; only proves misses.
final class IvmSkipState extends IvmState {
  IvmSkipState(this.shape);

  @override
  final IvmSkipShape shape;

  /// [IvmOutcome.unchanged] when every delta row fails the predicate both
  /// before and after the write; [IvmOutcome.bail] otherwise (a hit or an
  /// unprovable cell — the caller re-queries; there is no cache to drop).
  IvmOutcome apply(List<RowDelta> deltas) {
    for (final delta in deltas) {
      final values = delta.newValues ?? delta.oldValues;
      if (values == null || values.length != shape.tableColumnCount) {
        return IvmOutcome.bail;
      }
      final oldMatch = delta.oldValues == null
          ? false
          : evaluatePredicates(shape.predicates, delta.oldValues!);
      final newMatch = delta.newValues == null
          ? false
          : evaluatePredicates(shape.predicates, delta.newValues!);
      if (oldMatch != false || newMatch != false) return IvmOutcome.bail;
    }
    return IvmOutcome.unchanged;
  }
}

/// Fully-maintained rows (optionally a top-K window).
final class IvmFullState extends IvmState {
  IvmFullState(this.shape);

  @override
  final IvmFullShape shape;

  /// Maintained rows in admitted order. For windowed shapes this is the
  /// top-K (or the complete filtered set when it is smaller). `null`
  /// until built from the entry's last result, and after any bail.
  List<Map<String, Object?>>? rows;

  /// Composite (orderKey, pk) sort keys parallel to [rows].
  List<(int, int)>? keys;

  /// Windowed only: whether [rows] holds the *entire* filtered set (so
  /// departures never need a re-query). Unwindowed shapes are always
  /// complete by construction.
  bool complete = true;

  /// Build the maintained cache from the last emitted result. Returns
  /// false (leaving the cache unset) when the rows cannot be keyed or
  /// are not in admitted order.
  bool rebuild(List<Map<String, Object?>> lastResult) {
    final newRows = List<Map<String, Object?>>.generate(
      lastResult.length,
      (i) => Map<String, Object?>.of(lastResult[i]),
      growable: true,
    );
    final newKeys = <(int, int)>[];
    for (final row in newRows) {
      final pk = row[shape.pkOutputName];
      final orderKey = row[shape.orderOutputName];
      if (pk is! int || orderKey is! int) return false;
      final key = (orderKey, pk);
      if (newKeys.isNotEmpty && shape.compareKeys(newKeys.last, key) >= 0) {
        // Not strictly ascending in admitted order — never patch it.
        return false;
      }
      newKeys.add(key);
    }
    final limit = shape.limit;
    if (limit != null && newRows.length > limit) return false;
    rows = newRows;
    keys = newKeys;
    complete = limit == null || newRows.length < limit;
    return true;
  }

  /// Apply [deltas] (already filtered to this shape's table).
  IvmOutcome apply(List<RowDelta> deltas) {
    var currentRows = rows;
    var currentKeys = keys;
    if (currentRows == null || currentKeys == null) return _bail();

    var mutated = false;
    List<Map<String, Object?>> workRows = currentRows;
    List<(int, int)> workKeys = currentKeys;
    final limit = shape.limit;

    void ensureMutable() {
      if (!mutated) {
        workRows = List<Map<String, Object?>>.of(workRows);
        workKeys = List<(int, int)>.of(workKeys);
        mutated = true;
      }
    }

    bool applyOne(
      bool hasOld,
      bool hasNew,
      int oldPk,
      int newPk,
      List<Object?>? oldValues,
      List<Object?>? newValues,
    ) {
      final pOldOrNull = hasOld
          ? evaluatePredicates(shape.predicates, oldValues!)
          : false;
      final pNewOrNull = hasNew
          ? evaluatePredicates(shape.predicates, newValues!)
          : false;
      if (pOldOrNull == null || pNewOrNull == null) return false;
      final pOld = pOldOrNull;
      final pNew = pNewOrNull;

      (int, int)? oldKey;
      if (hasOld && pOld) {
        final cell = oldValues[shape.orderColumnIndex];
        if (cell is! int) return false;
        oldKey = (cell, oldPk);
      }
      (int, int)? newKey;
      if (hasNew && pNew) {
        final cell = newValues[shape.orderColumnIndex];
        if (cell is! int) return false;
        newKey = (cell, newPk);
      }

      final oldIdx = oldKey == null ? null : _search(workKeys, oldKey);
      // For diagnostics on misses, locate the row by pk regardless of the
      // (possibly changed) order key.
      if (!pOld && !pNew) {
        // Proven miss — but a cached row with this pk means the cache is
        // out of sync with reality.
        if (hasOld && _pkPresent(workRows, oldPk)) return false;
        return true;
      }

      if (pOld && pNew) {
        // The row stays in the filtered set; it may move or patch.
        final foundIdx = oldIdx != null && oldIdx >= 0
            ? oldIdx
            : _pkIndex(workRows, oldPk);
        if (foundIdx < 0) {
          // Below an incomplete window before the write.
          if (limit == null || complete) return false;
          // It may enter the window now.
          final lastKey = workKeys.isEmpty ? null : workKeys.last;
          if (workKeys.length >= limit &&
              lastKey != null &&
              shape.compareKeys(newKey!, lastKey) >= 0) {
            return true; // still below the window
          }
          return _insertRow(
            ensureMutable,
            () => workRows,
            () => workKeys,
            newKey!,
            newValues,
            limit,
          );
        }
        final patched = _projectRow(newValues);
        if (patched == null) return false;
        final keyChanged = workKeys[foundIdx] != newKey;
        if (!keyChanged && _projectedEquals(workRows[foundIdx], patched)) {
          return true;
        }
        ensureMutable();
        workRows.removeAt(foundIdx);
        workKeys.removeAt(foundIdx);
        if (limit != null &&
            !complete &&
            workKeys.isNotEmpty &&
            shape.compareKeys(newKey!, workKeys.last) >= 0 &&
            workKeys.length + 1 >= limit) {
          // Moving to/past the boundary of an incomplete window — the true
          // occupant of the freed slot is unknown.
          return false;
        }
        final insertAt = _insertionPoint(workKeys, newKey!);
        workRows.insert(insertAt, patched);
        workKeys.insert(insertAt, newKey);
        return true;
      }

      if (pOld) {
        // Row leaves the filtered set.
        final foundIdx = oldIdx != null && oldIdx >= 0
            ? oldIdx
            : _pkIndex(workRows, oldPk);
        if (foundIdx < 0) {
          // Below the window of an incomplete windowed cache: invisible.
          if (limit != null && !complete) return true;
          return false;
        }
        ensureMutable();
        workRows.removeAt(foundIdx);
        workKeys.removeAt(foundIdx);
        if (limit != null && !complete && workRows.length < limit) {
          // The window lost a member and the replacement is unknown.
          return false;
        }
        return true;
      }

      // Row enters the filtered set.
      if (_pkPresent(workRows, newPk)) return false;
      if (limit != null && !complete) {
        final lastKey = workKeys.isEmpty ? null : workKeys.last;
        if (workKeys.length >= limit &&
            lastKey != null &&
            shape.compareKeys(newKey!, lastKey) >= 0) {
          return true; // enters below the window — invisible
        }
      }
      return _insertRow(
        ensureMutable,
        () => workRows,
        () => workKeys,
        newKey!,
        newValues!,
        limit,
      );
    }

    for (final delta in deltas) {
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

    // Complete windowed caches may grow past the window; keep them bounded.
    if (limit != null && complete && workRows.length > limit + 64) {
      workRows = workRows.sublist(0, limit);
      workKeys = workKeys.sublist(0, limit);
      complete = false;
    }

    rows = workRows;
    keys = workKeys;
    return IvmOutcome.applied;
  }

  /// The result to emit: the visible window of the maintained rows.
  List<Map<String, Object?>> visibleRows() {
    final limit = shape.limit;
    final all = rows!;
    if (limit == null || all.length <= limit) return all;
    return all.sublist(0, limit);
  }

  bool _insertRow(
    void Function() ensureMutable,
    List<Map<String, Object?>> Function() getRows,
    List<(int, int)> Function() getKeys,
    (int, int) key,
    List<Object?> values,
    int? limit,
  ) {
    final inserted = _projectRow(values);
    if (inserted == null) return false;
    ensureMutable();
    final rows = getRows();
    final keys = getKeys();
    final insertAt = _insertionPoint(keys, key);
    rows.insert(insertAt, inserted);
    keys.insert(insertAt, key);
    if (limit != null && !complete && rows.length > limit) {
      // The displaced row is no longer the window's business.
      rows.removeLast();
      keys.removeLast();
    }
    return true;
  }

  IvmOutcome _bail() {
    rows = null;
    keys = null;
    return IvmOutcome.bail;
  }

  Map<String, Object?>? _projectRow(List<Object?> values) {
    if (values[shape.pkColumnIndex] is! int) return null;
    if (values[shape.orderColumnIndex] is! int) return null;
    final row = <String, Object?>{};
    for (final (name, cid) in shape.projection) {
      row[name] = values[cid];
    }
    return row;
  }

  bool _projectedEquals(Map<String, Object?> a, Map<String, Object?> b) {
    for (final (name, _) in shape.projection) {
      if (a[name] != b[name]) return false;
    }
    return true;
  }

  int _search(List<(int, int)> keys, (int, int) key) {
    var lo = 0;
    var hi = keys.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final c = shape.compareKeys(keys[mid], key);
      if (c < 0) {
        lo = mid + 1;
      } else if (c > 0) {
        hi = mid - 1;
      } else {
        return mid;
      }
    }
    return -(lo + 1);
  }

  int _insertionPoint(List<(int, int)> keys, (int, int) key) {
    final idx = _search(keys, key);
    return idx >= 0 ? idx : -(idx + 1);
  }

  bool _pkPresent(List<Map<String, Object?>> rows, int pk) =>
      _pkIndex(rows, pk) >= 0;

  int _pkIndex(List<Map<String, Object?>> rows, int pk) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i][shape.pkOutputName] == pk) return i;
    }
    return -1;
  }
}

/// Tier 3 state: exact aggregate values maintained from deltas.
final class IvmAggregateState extends IvmState {
  IvmAggregateState(this.shape);

  @override
  final IvmAggregateShape shape;

  /// Whether the state has been seeded (from the entry's first result for
  /// COUNT(*)-only shapes, otherwise from the admission snapshot query).
  bool seeded = false;

  /// Guards concurrent re-seed scheduling after a bail.
  bool reseedInFlight = false;

  /// Total rows matching the predicate.
  int rowCount = 0;

  /// Per aggregate column (by cid): non-null count, exact integer sum,
  /// and current extrema.
  final Map<int, int> nonNullCount = {};
  final Map<int, int> sum = {};
  final Map<int, int?> minValue = {};
  final Map<int, int?> maxValue = {};

  /// Seed from the admission snapshot row (see
  /// `buildAggregateSnapshotSql`). Returns false when the snapshot has an
  /// unusable shape.
  bool seedFromSnapshot(Map<String, Object?> snapshot) {
    final count = snapshot['__rows'];
    if (count is! int) return false;
    rowCount = count;
    for (final cid in shape.aggregateColumns) {
      final n = snapshot['__n$cid'];
      if (n is! int) return false;
      nonNullCount[cid] = n;
      final s = snapshot['__s$cid'];
      if (s is int) {
        sum[cid] = s;
      } else if (s == null) {
        sum[cid] = 0;
      } else {
        return false; // non-integer sum (REAL cells present)
      }
      final lo = snapshot['__lo$cid'];
      final hi = snapshot['__hi$cid'];
      if ((lo is! int && lo != null) || (hi is! int && hi != null)) {
        return false;
      }
      minValue[cid] = lo as int?;
      maxValue[cid] = hi as int?;
    }
    seeded = true;
    return true;
  }

  IvmOutcome apply(List<RowDelta> deltas) {
    if (!seeded) return IvmOutcome.bail;

    // Work on copies so a mid-batch bail leaves the state unseeded
    // rather than torn.
    var newRowCount = rowCount;
    final newNonNull = Map<int, int>.of(nonNullCount);
    final newSum = Map<int, int>.of(sum);
    final newMin = Map<int, int?>.of(minValue);
    final newMax = Map<int, int?>.of(maxValue);
    var mutated = false;

    bool contribute(List<Object?> values, int sign) {
      newRowCount += sign;
      mutated = true;
      for (final cid in shape.aggregateColumns) {
        final cell = values[cid];
        if (cell == null) continue;
        if (cell is! int) return false;
        newNonNull[cid] = newNonNull[cid]! + sign;
        newSum[cid] = newSum[cid]! + sign * cell;
        final lo = newMin[cid];
        final hi = newMax[cid];
        if (sign > 0) {
          if (lo == null || cell < lo) newMin[cid] = cell;
          if (hi == null || cell > hi) newMax[cid] = cell;
        } else {
          if (newNonNull[cid] == 0) {
            newMin[cid] = null;
            newMax[cid] = null;
          } else if (cell == lo || cell == hi) {
            // The departing cell was an extremum; the next one is unknown.
            return false;
          }
        }
      }
      return true;
    }

    for (final delta in deltas) {
      final values = delta.newValues ?? delta.oldValues;
      if (values == null || values.length != shape.tableColumnCount) {
        return _bail();
      }
      if (delta.oldValues != null &&
          delta.oldValues!.length != shape.tableColumnCount) {
        return _bail();
      }
      final oldMatch = delta.oldValues == null
          ? false
          : evaluatePredicates(shape.predicates, delta.oldValues!);
      final newMatch = delta.newValues == null
          ? false
          : evaluatePredicates(shape.predicates, delta.newValues!);
      if (oldMatch == null || newMatch == null) return _bail();
      if (oldMatch && !contribute(delta.oldValues!, -1)) return _bail();
      if (newMatch && !contribute(delta.newValues!, 1)) return _bail();
    }

    if (!mutated) return IvmOutcome.unchanged;
    rowCount = newRowCount;
    nonNullCount
      ..clear()
      ..addAll(newNonNull);
    sum
      ..clear()
      ..addAll(newSum);
    minValue
      ..clear()
      ..addAll(newMin);
    maxValue
      ..clear()
      ..addAll(newMax);
    return IvmOutcome.applied;
  }

  /// The single-row result to emit.
  Map<String, Object?> visibleRow() {
    final row = <String, Object?>{};
    for (final agg in shape.aggregates) {
      final cid = agg.columnIndex;
      row[agg.outputName] = switch (agg.kind) {
        IvmAggregateKind.countStar => rowCount,
        IvmAggregateKind.count => nonNullCount[cid],
        IvmAggregateKind.sum =>
          (nonNullCount[cid] ?? 0) == 0 ? null : sum[cid],
        IvmAggregateKind.min => minValue[cid],
        IvmAggregateKind.max => maxValue[cid],
        IvmAggregateKind.avg =>
          (nonNullCount[cid] ?? 0) == 0
              ? null
              : sum[cid]! / nonNullCount[cid]!,
      };
    }
    return row;
  }

  IvmOutcome _bail() {
    seeded = false;
    return IvmOutcome.bail;
  }
}

/// Build the internal snapshot query that seeds an aggregate state
/// exactly. All identifiers come from `PRAGMA table_info` and all values
/// from the validated predicate constants, quoted defensively.
String buildAggregateSnapshotSql(
  IvmAggregateShape shape,
  List<Map<String, Object?>> tableInfo,
) {
  String quoteIdent(String name) => '"${name.replaceAll('"', '""')}"';
  final nameByCid = <int, String>{
    for (final col in tableInfo)
      if (col['cid'] is int && col['name'] is String)
        col['cid'] as int: col['name'] as String,
  };

  final selects = <String>['COUNT(*) AS __rows'];
  for (final cid in shape.aggregateColumns) {
    final col = quoteIdent(nameByCid[cid]!);
    selects.add('COUNT($col) AS __n$cid');
    selects.add('SUM($col) AS __s$cid');
    selects.add('MIN($col) AS __lo$cid');
    selects.add('MAX($col) AS __hi$cid');
  }

  final where = shape.predicates.isEmpty
      ? ''
      : ' WHERE ${shape.predicates.map((p) {
          final col = quoteIdent(nameByCid[p.columnIndex]!);
          final value = p.value;
          final lit = value is int
              ? '$value'
              : "'${(value as String).replaceAll("'", "''")}'";
          return '$col ${p.op} $lit';
        }).join(' AND ')}';

  return 'SELECT ${selects.join(', ')} FROM ${quoteIdent(shape.table)}$where';
}
