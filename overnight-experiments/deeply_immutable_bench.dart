// Benchmark: @pragma('vm:deeply-immutable') wrapper vs raw list vs string

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

@pragma('vm:deeply-immutable')
final class ImmutableResult {
  final String payload;    // JSON-encoded rows
  final int rowCount;
  final int columnCount;
  final String columnNames;

  ImmutableResult(this.payload, this.rowCount, this.columnCount, this.columnNames);
}

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

Future<int> _measureTransferAndDecode(String json, int rows, int cols) async {
  final port = RawReceivePort();
  final completer = Completer<Object?>();
  port.handler = (Object? msg) {
    port.close();
    completer.complete(msg);
  };
  final sw = Stopwatch()..start();
  await Isolate.spawn(_exitWithValue, [port.sendPort, json]);
  final result = await completer.future as String;
  // Simulate decoding on main isolate.
  final decoded = jsonDecode(result) as List;
  // Access first 15 rows (ListView.builder visible rows).
  for (var i = 0; i < 15 && i < decoded.length; i++) {
    final row = decoded[i] as Map;
    row.values.toList(); // force access
  }
  sw.stop();
  return sw.elapsedMicroseconds;
}

String _fmt(int us) => '${(us / 1000).toStringAsFixed(2)} ms';

Future<void> main() async {
  print('=== Deeply Immutable Transfer Benchmark ===\n');

  for (final rows in [1000, 5000, 10000]) {
    const cols = 6;
    final elementCount = rows * cols;

    // Build mutable list (current approach).
    final mutableList = List<Object?>.generate(elementCount, (i) {
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

    // Build JSON equivalent.
    final jsonRows = List.generate(rows, (r) => {
      'id': r,
      'name': 'Name $r',
      'score': r * 1.5,
      'email': 'email$r@example.com',
      'status': r % 3 == 0 ? null : 'active',
      'value': r * 100,
    });
    final jsonString = jsonEncode(jsonRows);

    // Build ImmutableResult.
    final immutableResult = ImmutableResult(
      jsonString, rows, cols, 'id,name,score,email,status,value',
    );

    // Warm up.
    for (var i = 0; i < 5; i++) {
      await _measureTransfer(List<Object?>.from(mutableList));
      await _measureTransfer(immutableResult);
    }

    // Measure: mutable list (current approach).
    final listTimes = <int>[];
    for (var i = 0; i < 30; i++) {
      listTimes.add(await _measureTransfer(List<Object?>.from(mutableList)));
    }

    // Measure: ImmutableResult wrapper (transfer only).
    final immutableTimes = <int>[];
    for (var i = 0; i < 30; i++) {
      immutableTimes.add(await _measureTransfer(immutableResult));
    }

    // Measure: ImmutableResult + decode 15 rows on main (realistic Flutter use).
    final decodePartialTimes = <int>[];
    for (var i = 0; i < 30; i++) {
      decodePartialTimes.add(await _measureTransferAndDecode(jsonString, rows, cols));
    }

    // Measure: ImmutableResult + decode ALL rows on main (worst case).
    final decodeAllTimes = <int>[];
    for (var i = 0; i < 30; i++) {
      final port = RawReceivePort();
      final completer = Completer<Object?>();
      port.handler = (Object? msg) {
        port.close();
        completer.complete(msg);
      };
      final sw = Stopwatch()..start();
      await Isolate.spawn(_exitWithValue, [port.sendPort, jsonString]);
      final result = await completer.future as String;
      jsonDecode(result); // full decode
      sw.stop();
      decodeAllTimes.add(sw.elapsedMicroseconds);
    }

    listTimes.sort();
    immutableTimes.sort();
    decodePartialTimes.sort();
    decodeAllTimes.sort();

    final listMed = listTimes[listTimes.length ~/ 2];
    final immutableMed = immutableTimes[immutableTimes.length ~/ 2];
    final partialMed = decodePartialTimes[decodePartialTimes.length ~/ 2];
    final allMed = decodeAllTimes[decodeAllTimes.length ~/ 2];

    print('$rows rows ($elementCount elements, ${(jsonString.length / 1024).toStringAsFixed(0)} KB JSON):');
    print('  List<Object?> (current):           ${_fmt(listMed)}');
    print('  ImmutableResult (transfer only):   ${_fmt(immutableMed)}');
    print('  Immutable + decode 15 rows:        ${_fmt(partialMed)}');
    print('  Immutable + decode ALL rows:       ${_fmt(allMed)}');
    print('  Transfer speedup:                  ${(listMed / immutableMed).toStringAsFixed(1)}x');
    print('  Partial decode vs list:            ${((partialMed - listMed) / listMed * 100).toStringAsFixed(0)}%');
    print('');
  }
}
