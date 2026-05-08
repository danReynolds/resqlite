import 'dart:math' as math;

/// A conservative internal rewrite for simple batch inserts.
///
/// The public API remains `executeBatch(sql, paramSets)`. When the SQL is a
/// plain positional `INSERT ... VALUES (?, ...)` and the batch length can be
/// represented by one repeated VALUES shape, the writer can execute fewer
/// SQLite steps by binding multiple user rows per native batch set.
final class BatchInsertChunk {
  const BatchInsertChunk({
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

final _valuesKeyword = RegExp(r'\bvalues\b', caseSensitive: false);

BatchInsertChunk? chunkSimpleInsertBatch(
  String sql,
  List<List<Object?>> paramSets,
) {
  if (paramSets.length < _minBatchRows) return null;

  final paramCount = paramSets.first.length;
  if (paramCount == 0) return null;

  final maxRowsByVariables = _maxSqlVariables ~/ paramCount;
  final maxRowsPerStep = math.min(_targetRowsPerStep, maxRowsByVariables);
  if (maxRowsPerStep < _minRowsPerStep) return null;

  final rowsPerStep = _largestDivisorAtMost(paramSets.length, maxRowsPerStep);
  if (rowsPerStep == null) return null;

  final shape = _parseSimpleInsertValues(sql, paramCount);
  if (shape == null) return null;

  return BatchInsertChunk(
    sql: _buildMultiRowInsert(shape, rowsPerStep),
    paramSets: _chunkParamSets(paramSets, paramCount, rowsPerStep),
    rowsPerStep: rowsPerStep,
  );
}

int? _largestDivisorAtMost(int value, int maxDivisor) {
  for (var candidate = maxDivisor; candidate >= _minRowsPerStep; candidate--) {
    if (value % candidate == 0) return candidate;
  }
  return null;
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

  final matches = _valuesKeyword.allMatches(source).toList(growable: false);
  if (matches.length != 1) return null;

  final match = matches.single;
  final prefix = source.substring(0, match.end).trimRight();
  final valuesBody = source.substring(match.end).trim();
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
      source.contains('"') ||
      source.contains('`') ||
      source.contains('[') ||
      source.contains(']') ||
      source.contains('--') ||
      source.contains('/*') ||
      source.contains('*/');
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

List<List<Object?>> _chunkParamSets(
  List<List<Object?>> paramSets,
  int paramCount,
  int rowsPerStep,
) {
  final chunkCount = paramSets.length ~/ rowsPerStep;
  final chunkParamCount = paramCount * rowsPerStep;
  final chunks = List<List<Object?>>.generate(
    chunkCount,
    (_) => const <Object?>[],
    growable: false,
  );

  var chunkIndex = 0;
  for (var rowOffset = 0; rowOffset < paramSets.length;) {
    final chunk = List<Object?>.filled(chunkParamCount, null, growable: false);
    var writeIndex = 0;
    for (var row = 0; row < rowsPerStep; row++) {
      final source = paramSets[rowOffset++];
      for (var param = 0; param < paramCount; param++) {
        chunk[writeIndex++] = source[param];
      }
    }
    chunks[chunkIndex++] = chunk;
  }

  return chunks;
}
