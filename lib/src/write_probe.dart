// TEMPORARY EXPERIMENT SCAFFOLDING — [EXP-284].
//
// In-situ timestamps around the standalone `db.execute()` hop, on both sides
// of the writer boundary. Exp 282's parting lesson (its signal entry,
// nextSignals #3) is that an echo-isolate ladder answers relative questions
// inside itself and cannot size a shipping message, while twenty lines of
// Stopwatch in the real path settle it in one run. This is those twenty lines
// for the write path.
//
// Removed before merge. Nothing here is behind `kProfileMode` on purpose: the
// point is to measure the shipping code path, and the probe's own tax is
// measured by the harness rather than compiled away.
library;

/// Main-isolate side of the decomposition. One sequential awaited write at a
/// time — the harness drives strictly sequential writes, so the scratch
/// timestamps cannot interleave.
final class WriteProbe {
  WriteProbe._();

  static final Stopwatch clock = Stopwatch()..start();

  static bool enabled = false;

  static int _t0 = 0;
  static int _tLocked = 0;
  static int _tBuilt = 0;
  static int _tSent = 0;
  static int _tReply = 0;

  /// Completed writes folded into the accumulators below.
  static int count = 0;

  /// `Writer.execute` entry -> the writer mutex is held.
  static int enqueueTicks = 0;

  /// Mutex held -> the `ExecuteRequest` is built (includes `wrapParams`).
  static int buildTicks = 0;

  /// The `SendPort.send` call itself.
  static int sendTicks = 0;

  /// Send returns -> the reply lands in `_onReply`. Wire + worker + wake.
  static int awayTicks = 0;

  /// `_onReply` entry -> `Database.execute` is ready to return.
  static int finishTicks = 0;

  static void t0() {
    if (!enabled) return;
    _t0 = clock.elapsedTicks;
  }

  static void tLocked() {
    if (!enabled) return;
    _tLocked = clock.elapsedTicks;
  }

  static void tBuilt() {
    if (!enabled) return;
    _tBuilt = clock.elapsedTicks;
  }

  static void tSent() {
    if (!enabled) return;
    _tSent = clock.elapsedTicks;
  }

  static void tReply() {
    if (!enabled) return;
    _tReply = clock.elapsedTicks;
  }

  static void tDone() {
    if (!enabled) return;
    final now = clock.elapsedTicks;
    enqueueTicks += _tLocked - _t0;
    buildTicks += _tBuilt - _tLocked;
    sendTicks += _tSent - _tBuilt;
    awayTicks += _tReply - _tSent;
    finishTicks += now - _tReply;
    count++;
  }

  static void reset() {
    count = 0;
    enqueueTicks = 0;
    buildTicks = 0;
    sendTicks = 0;
    awayTicks = 0;
    finishTicks = 0;
  }
}

/// Writer-isolate side. Separate statics because it is a separate isolate;
/// the totals are printed from the worker when it shuts down.
final class WriterSideProbe {
  WriterSideProbe._();

  static final Stopwatch clock = Stopwatch()..start();

  static bool enabled = false;

  static int _wEntry = 0;
  static int _wUnwrapped = 0;
  static int _wExecuted = 0;
  static int _wHarvested = 0;

  static int count = 0;

  /// Handler entry -> blob params unwrapped (includes the type switch).
  static int unwrapTicks = 0;

  /// -> `executeWrite` returns. SQLite plus the param arena and result buffer.
  static int sqliteTicks = 0;

  /// -> `getDirtyTableDependencies` returns.
  static int harvestTicks = 0;

  /// -> the reply is on the port. `ExecuteResponse` plus the graph copy.
  static int replyTicks = 0;

  static void entry() {
    if (!enabled) return;
    _wEntry = clock.elapsedTicks;
  }

  static void unwrapped() {
    if (!enabled) return;
    _wUnwrapped = clock.elapsedTicks;
  }

  static void executed() {
    if (!enabled) return;
    _wExecuted = clock.elapsedTicks;
  }

  static void harvested() {
    if (!enabled) return;
    _wHarvested = clock.elapsedTicks;
  }

  static void replied() {
    if (!enabled) return;
    final now = clock.elapsedTicks;
    unwrapTicks += _wUnwrapped - _wEntry;
    sqliteTicks += _wExecuted - _wUnwrapped;
    harvestTicks += _wHarvested - _wExecuted;
    replyTicks += now - _wHarvested;
    count++;
  }
}
