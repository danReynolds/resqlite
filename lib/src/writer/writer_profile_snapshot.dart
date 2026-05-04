/// Public value type returned by `Database.writerProfileSnapshot()`.
///
/// Carries the four writer-isolate counters defined by exp 123 — see
/// `experiments/123-writer-dispatch-step-split.md` and
/// [`ProfileCounters.writerHandlerUs`] / friends. Values are plain
/// ints, not references to the writer's mutable static fields, so the
/// snapshot is stable for the caller's lifetime.
///
/// Outside `-DRESQLITE_PROFILE=true` builds the writer-side timing
/// instrumentation tree-shakes away and every counter stays at zero;
/// the snapshot is harmlessly meaningless in that mode.
final class WriterProfileSnapshot {
  const WriterProfileSnapshot({
    required this.handlerUs,
    required this.handlerCount,
    required this.nativeUs,
    required this.nativeCount,
  });

  /// Cumulative wall-clock microseconds spent inside the writer
  /// isolate's `_handleExecute` and `_handleBatch` bodies — message
  /// receive through reply send. Includes parameter encoding, the
  /// FFI write call, dirty-table extraction, and reply marshalling.
  final int handlerUs;

  /// Number of `_handleExecute` + `_handleBatch` invocations captured
  /// in [handlerUs].
  final int handlerCount;

  /// Cumulative wall-clock microseconds spent specifically inside the
  /// FFI write call (`resqliteExecute`, `resqliteRunBatch`, or
  /// `resqliteRunBatchNested`) — i.e. the SQLite-side prepare / bind /
  /// step / reset / commit work plus the FFI crossing itself.
  final int nativeUs;

  /// Number of FFI write calls captured in [nativeUs]. Diverges from
  /// [handlerCount] whenever a handler exits before its FFI call runs
  /// (for example, parameter allocation throwing before
  /// `resqliteExecute` is invoked).
  final int nativeCount;

  @override
  String toString() =>
      'WriterProfileSnapshot('
      'handlerUs: $handlerUs, '
      'handlerCount: $handlerCount, '
      'nativeUs: $nativeUs, '
      'nativeCount: $nativeCount'
      ')';
}
