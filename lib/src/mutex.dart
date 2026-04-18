import 'dart:async';

class Mutex {
  Completer? _completer;

  /// `true` while any caller holds the lock. Useful for opportunistic
  /// "is a writer busy?" probes (e.g. [StreamEngine] uses it to skip
  /// emissions that are about to be superseded by an in-flight write).
  /// Strictly an informational peek — callers must not treat this as
  /// a synchronization primitive.
  bool get isLocked => _completer != null;

  Future<void> lock() async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
  }

  void unlock() {
    _completer?.complete();
    _completer = null;
  }

  Future<T> run<T>(Future<T> Function() body) async {
    try {
      await lock();
      return await body();
    } finally {
      unlock();
    }
  }
}
