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

  /// Attempts to acquire the mutex without waiting.
  ///
  /// Returns `true` if the lock was acquired (the caller now owns it
  /// and must [unlock] exactly as with [lock]); `false` if it is
  /// already held. Matches the `tryLock` convention from
  /// `java.util.concurrent.locks.Lock`, Rust's `Mutex::try_lock`,
  /// Python's `Lock.acquire(blocking=False)`, and Go 1.18+
  /// `sync.Mutex.TryLock`.
  ///
  /// Lets hot standalone-write callers skip the microtask hop that
  /// `await lock()` always pays — even uncontended, the implicit
  /// `Future` an `async` function returns yields once before the body
  /// resumes. Dart is single-threaded, so checking the completer and
  /// claiming the slot inside one synchronous call is safe.
  bool tryLock() {
    if (_completer == null) {
      _completer = Completer<void>();
      return true;
    }
    return false;
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
