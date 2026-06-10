import 'dart:async';

class Mutex {
  Completer? _completer;

  /// Whether the mutex is currently held (by anyone — ownership is not
  /// tracked). Used by debug assertions on methods whose precondition is
  /// "caller holds the lock".
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
