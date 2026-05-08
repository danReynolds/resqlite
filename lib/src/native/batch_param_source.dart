import 'dart:collection';

/// List-shaped source for a batch whose public rows are packed into larger
/// native statement parameter sets.
///
/// Generic callers can still treat this as `List<List<Object?>>`, but the
/// native parameter encoder recognizes the concrete type and walks
/// [paramSets] directly to avoid building temporary flattened Dart lists.
final class ChunkedBatchParamSets extends ListBase<List<Object?>> {
  ChunkedBatchParamSets({
    required this.paramSets,
    required this.paramCount,
    required this.rowsPerStep,
    required this.startRow,
    required int chunkCount,
  }) : _length = chunkCount;

  final List<List<Object?>> paramSets;
  final int paramCount;
  final int rowsPerStep;
  final int startRow;
  final int _length;

  int get chunkParamCount => paramCount * rowsPerStep;

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('read-only param view');

  @override
  List<Object?> operator [](int index) {
    return ChunkedBatchParamSet(
      paramSets: paramSets,
      paramCount: paramCount,
      rowsPerStep: rowsPerStep,
      startRow: startRow + index * rowsPerStep,
    );
  }

  @override
  void operator []=(int index, List<Object?> value) {
    throw UnsupportedError('read-only param view');
  }
}

final class ChunkedBatchParamSet extends ListBase<Object?> {
  ChunkedBatchParamSet({
    required this.paramSets,
    required this.paramCount,
    required this.rowsPerStep,
    required this.startRow,
  });

  final List<List<Object?>> paramSets;
  final int paramCount;
  final int rowsPerStep;
  final int startRow;

  @override
  int get length => paramCount * rowsPerStep;

  @override
  set length(int value) => throw UnsupportedError('read-only param view');

  @override
  Object? operator [](int index) {
    return paramSets[startRow + index ~/ paramCount][index % paramCount];
  }

  @override
  void operator []=(int index, Object? value) {
    throw UnsupportedError('read-only param view');
  }
}
