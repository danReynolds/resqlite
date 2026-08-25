// ignore_for_file: avoid_print
//
// Prices Dart's async plumbing, so a candidate that removes some of it can be
// costed before it is built ([EXP-278]).
//
// resqlite's call paths are layered coroutines: a public `Database` method
// awaits the one-shot `_runtime` future, then forwards to a pool or writer
// method, which forwards again. Every layer is an `async` frame, and the
// `_runtime` await is an await on a future that has been resolved since
// `open()` returned. Removing those layers is a recurring candidate shape —
// exps 145, 148, 151, 159, 171 and 278 are all in that family — and it has
// repeatedly been costed by intuition. Exp 171 estimated "~1-2 us per call"
// and derived 6-12% of headroom from it; the real figure is more than an
// order of magnitude smaller, which is the whole reason its measured result
// came back empty.
//
// This harness answers the question that should be asked first: how many
// nanoseconds is one layer actually worth? It uses no SQLite, no isolates and
// no resqlite code, because the point is to price the language machinery on
// its own, against which a per-read wall time can then be divided.
//
// Four shapes, each timed as "N of these end to end", with the completion
// driven from a separate microtask so every arm genuinely suspends the way a
// worker reply does:
//
//   direct     the caller awaits a sync-completer future with nothing between
//   resolved   one already-resolved future is awaited first, then that future
//              — the `await _runtime` shape on its own
//   frame1     one `async` function forwards the future to the caller
//   frame3     an already-resolved await plus three nested `async` forwarders
//              — the shape `Database.select` -> `ReaderPool.select` ->
//              `ReaderPool._dispatch` -> `_WorkerSlot.request` had before
//              exp 278
//
// Read `frame3 - frame1` for what exp 278's candidate removed, and
// `frame1 - direct` for what one more layer would be worth after it. Divide
// either by the wall time of the operation the layers wrap: a resqlite point
// read is ~5.9 us, so a difference of 100 ns is 1.7% and no amount of tuning
// makes it more.
//
// Usage:
//   dart run benchmark/experiments/async_prologue_price.dart [--samples=15]
//
// Build it AOT for a figure that matches shipped code; the JIT numbers are
// not comparable.
import 'dart:async';

const _iterations = 200000;
const _warmup = 20000;

Future<Object?> _leaf(Completer<Object?> completer) => completer.future;

Future<Object?> _forward(Completer<Object?> completer) async => _leaf(completer);

Future<Object?> _forward2(Completer<Object?> completer) async =>
    _forward(completer);

Future<Object?> _resolvedThenForward2(
  Future<void> resolved,
  Completer<Object?> completer,
) async {
  await resolved;
  return _forward2(completer);
}

Future<int> _run(String shape, Future<void> resolved, int n) async {
  var accumulator = 0;
  for (var i = 0; i < n; i++) {
    final completer = Completer<Object?>.sync();
    final Future<Object?> future;
    switch (shape) {
      case 'direct':
        future = _leaf(completer);
      case 'resolved':
        future = resolved.then((_) => _leaf(completer));
      case 'frame1':
        future = _forward(completer);
      default:
        future = _resolvedThenForward2(resolved, completer);
    }
    scheduleMicrotask(() => completer.complete(i));
    accumulator += (await future) as int;
  }
  return accumulator;
}

Future<void> main(List<String> args) async {
  var samples = 15;
  for (final arg in args) {
    if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  final resolved = Future<void>.value();
  await resolved;

  print('=== async prologue price ===');
  print('iterations=$_iterations samples=$samples');
  for (final shape in ['direct', 'resolved', 'frame1', 'frame3']) {
    await _run(shape, resolved, _warmup);
    final perCall = <double>[];
    for (var s = 0; s < samples; s++) {
      final stopwatch = Stopwatch()..start();
      await _run(shape, resolved, _iterations);
      stopwatch.stop();
      perCall.add(stopwatch.elapsedMicroseconds * 1000 / _iterations);
    }
    perCall.sort();
    print(
      'shape=$shape ns_per_call=${perCall[perCall.length ~/ 2].toStringAsFixed(1)} '
      'min_ns=${perCall.first.toStringAsFixed(1)} '
      'max_ns=${perCall.last.toStringAsFixed(1)}',
    );
  }
}
