// Quick benchmark: does List.unmodifiable affect Isolate.exit validation cost?

import 'dart:async';
import 'dart:isolate';

// Entry points must be top-level to avoid capturing non-sendable objects.
void _exitWithValue(List<Object?> args) {
  final sendPort = args[0] as SendPort;
  final value = args[1];
  Isolate.exit(sendPort, value);
}

Future<int> _measureTransfer(Object? value) async {
  final port = RawReceivePort();
  final completer = Completer<Object?>();
  port.handler = (Object? msg) {
    port.close();
    completer.complete(msg);
  };
  final sw = Stopwatch()..start();
  await Isolate.spawn(_exitWithValue, [port.sendPort, value]);
  await completer.future;
  sw.stop();
  return sw.elapsedMicroseconds;
}

String _fmt(int us) => '${(us / 1000).toStringAsFixed(2)} ms';

Future<void> main() async {
  print('=== Isolate.exit: List.unmodifiable vs mutable ===\n');

  for (final rows in [1000, 5000, 10000, 50000]) {
    const cols = 6;
    final elementCount = rows * cols;

    // Build source data (mixed types like a real query result).
    final source = List<Object?>.generate(elementCount, (i) {
      final col = i % cols;
      return switch (col) {
        0 => i ~/ cols,
        1 => 'Name ${i ~/ cols}',
        2 => (i ~/ cols) * 1.5,
        3 => 'email${i ~/ cols}@example.com',
        4 => i % 3 == 0 ? null : 'active',
        _ => i ~/ cols * 100,
      };
    });

    final jsonString = 'x' * (rows * 60);

    // Warm up.
    for (var i = 0; i < 5; i++) {
      await _measureTransfer(List<Object?>.from(source));
      await _measureTransfer(List<Object?>.unmodifiable(source));
      await _measureTransfer(jsonString);
    }

    // Measure mutable.
    final mutableTimes = <int>[];
    for (var i = 0; i < 50; i++) {
      mutableTimes.add(await _measureTransfer(List<Object?>.from(source)));
    }

    // Measure unmodifiable.
    final unmodTimes = <int>[];
    for (var i = 0; i < 50; i++) {
      unmodTimes.add(await _measureTransfer(List<Object?>.unmodifiable(source)));
    }

    // Measure string (deeply immutable baseline).
    final stringTimes = <int>[];
    for (var i = 0; i < 50; i++) {
      stringTimes.add(await _measureTransfer(jsonString));
    }

    mutableTimes.sort();
    unmodTimes.sort();
    stringTimes.sort();

    final mutableMed = mutableTimes[mutableTimes.length ~/ 2];
    final unmodMed = unmodTimes[unmodTimes.length ~/ 2];
    final stringMed = stringTimes[stringTimes.length ~/ 2];

    print('$rows rows ($elementCount elements):');
    print('  Mutable List<Object?>:     ${_fmt(mutableMed)}');
    print('  List.unmodifiable:         ${_fmt(unmodMed)}');
    print('  Single String (baseline):  ${_fmt(stringMed)}');
    final delta = ((unmodMed - mutableMed) / mutableMed * 100).toStringAsFixed(1);
    print('  Unmod vs Mutable:          $delta%');
    print('');
  }
}
