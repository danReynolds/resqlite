import 'dart:async';

class Mutex {
  Completer? _completer;

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
