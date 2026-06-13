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

  /// Acquires the mutex synchronously when uncontended.
  ///
  /// Returns `null` when the lock was acquired without waiting (the
  /// caller now owns it and must [unlock]). Returns a `Future<void>`
  /// the caller must `await` otherwise; once that future resolves the
  /// lock is held and [unlock] is required exactly as with [lock].
  ///
  /// Lets hot standalone-write callers skip the microtask hop that
  /// `await lock()` always pays — even uncontended, the implicit
  /// `Future` an `async` function returns yields once before the body
  /// resumes. Dart is single-threaded, so checking the completer and
  /// claiming the slot inside one synchronous call is safe.
  Future<void>? lockSync() {
    if (_completer == null) {
      _completer = Completer<void>();
      return null;
    }
    return lock();
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
