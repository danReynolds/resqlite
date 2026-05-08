import 'dart:collection';
import 'dart:math' as math;

import '../native/batch_param_source.dart';

/// A conservative internal rewrite for simple batch inserts.
///
/// The public API remains `executeBatch(sql, paramSets)`. When the SQL is a
/// guarded positional `INSERT ... VALUES (?, ...)`, the writer can execute
/// fewer SQLite steps by binding multiple user rows per native batch set.
final class BatchInsertPlan {
  const BatchInsertPlan(this.segments);

  final List<BatchInsertSegment> segments;
}

final class BatchInsertSegment {
  const BatchInsertSegment({
    required this.sql,
    required this.paramSets,
    required this.rowsPerStep,
  });

  final String sql;
  final List<List<Object?>> paramSets;
  final int rowsPerStep;
}

const _targetRowsPerStep = 100;
const _minRowsPerStep = 8;
const _minBatchRows = 2000;
// Bundled SQLite/sqlite3mc default; the 100-row cap keeps actual usage much
// lower for normal schemas while allowing 20-param wide batches to chunk well.
const _maxSqlVariables = 32766;

BatchInsertPlan? chunkSimpleInsertBatch(
  String sql,
  List<List<Object?>> paramSets,
) {
  if (paramSets.length < _minBatchRows) return null;

  final paramCount = paramSets.first.length;
  if (paramCount == 0) return null;

  final maxRowsByVariables = _maxSqlVariables ~/ paramCount;
  final maxRowsPerStep = math.min(_targetRowsPerStep, maxRowsByVariables);
  if (maxRowsPerStep < _minRowsPerStep) return null;

  final shape = _parseSimpleInsertValues(sql, paramCount);
  if (shape == null) return null;

  final fullChunkCount = paramSets.length ~/ maxRowsPerStep;
  if (fullChunkCount == 0) return null;

  final fullChunkRows = fullChunkCount * maxRowsPerStep;
  final remainder = paramSets.length - fullChunkRows;
  final segments = <BatchInsertSegment>[
    BatchInsertSegment(
      sql: _buildMultiRowInsert(shape, maxRowsPerStep),
      paramSets: ChunkedBatchParamSets(
        paramSets: paramSets,
        paramCount: paramCount,
        rowsPerStep: maxRowsPerStep,
        startRow: 0,
        chunkCount: fullChunkCount,
      ),
      rowsPerStep: maxRowsPerStep,
    ),
  ];

  if (remainder >= _minRowsPerStep) {
    segments.add(
      BatchInsertSegment(
        sql: _buildMultiRowInsert(shape, remainder),
        paramSets: ChunkedBatchParamSets(
          paramSets: paramSets,
          paramCount: paramCount,
          rowsPerStep: remainder,
          startRow: fullChunkRows,
          chunkCount: 1,
        ),
        rowsPerStep: remainder,
      ),
    );
  } else if (remainder > 0) {
    segments.add(
      BatchInsertSegment(
        sql: sql,
        paramSets: _ParamSetsSlice(
          paramSets: paramSets,
          startRow: fullChunkRows,
          rowCount: remainder,
        ),
        rowsPerStep: 1,
      ),
    );
  }

  return BatchInsertPlan(List<BatchInsertSegment>.unmodifiable(segments));
}

final class _InsertValuesShape {
  const _InsertValuesShape({required this.prefix, required this.tuple});

  final String prefix;
  final String tuple;
}

_InsertValuesShape? _parseSimpleInsertValues(String sql, int paramCount) {
  var source = sql.trim();
  if (source.endsWith(';')) {
    source = source.substring(0, source.length - 1).trimRight();
  }
  if (source.isEmpty) return null;

  final lower = source.toLowerCase();
  if (!lower.startsWith('insert ')) return null;
  if (_containsUnsupportedSqlSyntax(source)) return null;

  final valuesKeyword = _findSingleValuesKeyword(source);
  if (valuesKeyword == null) return null;

  final prefix = source.substring(0, valuesKeyword.end).trimRight();
  final valuesBody = source.substring(valuesKeyword.end).trim();
  if (!valuesBody.startsWith('(') || !valuesBody.endsWith(')')) return null;

  final tuple = valuesBody.substring(1, valuesBody.length - 1).trim();
  if (tuple.isEmpty || tuple.contains('(') || tuple.contains(')')) return null;

  final placeholders = tuple.split(',');
  if (placeholders.length != paramCount) return null;
  for (final placeholder in placeholders) {
    if (placeholder.trim() != '?') return null;
  }

  return _InsertValuesShape(prefix: prefix, tuple: tuple);
}

bool _containsUnsupportedSqlSyntax(String source) {
  return source.contains("'") ||
      source.contains('--') ||
      source.contains('/*') ||
      source.contains('*/');
}

({int start, int end})? _findSingleValuesKeyword(String source) {
  ({int start, int end})? found;

  for (var i = 0; i < source.length;) {
    final codeUnit = source.codeUnitAt(i);
    final skipTo = switch (codeUnit) {
      0x22 => _skipDelimitedIdentifier(source, i, 0x22, 0x22),
      0x60 => _skipDelimitedIdentifier(source, i, 0x60, 0x60),
      0x5b => _skipDelimitedIdentifier(source, i, 0x5b, 0x5d),
      _ => null,
    };
    if (skipTo == -1) return null;
    if (skipTo != null) {
      i = skipTo;
      continue;
    }

    if (_startsWithValuesKeyword(source, i)) {
      if (found != null) return null;
      found = (start: i, end: i + 'values'.length);
      i = found.end;
    } else {
      i++;
    }
  }

  return found;
}

int? _skipDelimitedIdentifier(String source, int start, int open, int close) {
  for (var i = start + 1; i < source.length; i++) {
    if (source.codeUnitAt(i) != close) continue;
    if (open == close &&
        i + 1 < source.length &&
        source.codeUnitAt(i + 1) == close) {
      i++;
      continue;
    }
    return i + 1;
  }
  return -1;
}

bool _startsWithValuesKeyword(String source, int offset) {
  if (offset + 'values'.length > source.length) return false;
  if (offset > 0 && _isSqlWord(source.codeUnitAt(offset - 1))) return false;
  const values = 'values';
  for (var i = 0; i < values.length; i++) {
    final actual = source.codeUnitAt(offset + i);
    final expected = values.codeUnitAt(i);
    if (actual != expected && actual != expected - 0x20) return false;
  }
  final end = offset + values.length;
  return end == source.length || !_isSqlWord(source.codeUnitAt(end));
}

bool _isSqlWord(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
      codeUnit == 0x5f;
}

String _buildMultiRowInsert(_InsertValuesShape shape, int rowsPerStep) {
  final buffer = StringBuffer(shape.prefix)..write(' ');
  for (var i = 0; i < rowsPerStep; i++) {
    if (i > 0) buffer.write(', ');
    buffer
      ..write('(')
      ..write(shape.tuple)
      ..write(')');
  }
  return buffer.toString();
}

final class _ParamSetsSlice extends ListBase<List<Object?>> {
  _ParamSetsSlice({
    required this.paramSets,
    required this.startRow,
    required int rowCount,
  }) : _length = rowCount;

  final List<List<Object?>> paramSets;
  final int startRow;
  final int _length;

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('read-only param view');

  @override
  List<Object?> operator [](int index) => paramSets[startRow + index];

  @override
  void operator []=(int index, List<Object?> value) {
    throw UnsupportedError('read-only param view');
  }
}
