// ignore_for_file: avoid_print
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:resqlite/src/native/resqlite_bindings.dart';

import '../shared/seeder.dart';

/// Micro-benchmark: measures the raw cost of FFI calls in the query hot loop.
///
/// Validates the hypothesis that per-cell FFI overhead is a significant
/// portion of select() wall time, and that batching would help.
///
/// Approach: use the direct native `queryBytes()` helper (C does all query work
/// in one leaf FFI call) vs `select()` / `selectBytes()`. The difference shows
/// the overhead from isolate hops and Dart-side materialization.

const _warmup = 10;
const _iterations = 50;
const _rowCounts = [1000, 5000, 10000];

Future<void> main() async {
  print('');
  print('=== FFI Overhead Analysis ===');
  print('');
  print('Compares C-does-everything (one FFI call) vs Dart per-cell FFI.');
  print('The gap shows how much overhead the FFI boundary + Dart objects add.');
  print('');

  for (final rowCount in _rowCounts) {
    final tempDir = await Directory.systemTemp.createTemp('bench_ffi_');
    try {
      final db = await resqlite.Database.open('${tempDir.path}/test.db');
      await seedResqlite(db, rowCount);

      final handleAddr = db.handle.address;
      const sql = standardSelectSql;

      // Warmup.
      for (var i = 0; i < _warmup; i++) {
        await db.select(sql);
        await db.selectBytes(sql);
      }

      // --- A: Full select() — per-cell FFI + Dart map construction + Isolate.exit ---
      final timingsSelect = <int>[];
      for (var i = 0; i < _iterations; i++) {
        final sw = Stopwatch()..start();
        await db.select(sql);
        sw.stop();
        timingsSelect.add(sw.elapsedMicroseconds);
      }

      // --- B: selectBytes() — one FFI call, C does everything ---
      final timingsBytes = <int>[];
      for (var i = 0; i < _iterations; i++) {
        final sw = Stopwatch()..start();
        await db.selectBytes(sql);
        sw.stop();
        timingsBytes.add(sw.elapsedMicroseconds);
      }

      // --- C: direct queryBytes() leaf FFI call ---
      // Measures: C reads all columns + native encoding in one direct call.
      final timingsCBulk = <int>[];
      for (var i = 0; i < _iterations; i++) {
        final sw = Stopwatch()..start();
        final h = ffi.Pointer<ffi.Void>.fromAddress(handleAddr);
        final result = queryBytes(h, 0, sql, const []);
        result.length; // force a read so the call is not optimized away
        resqliteFree(result.ptr.cast());
        sw.stop();
        timingsCBulk.add(sw.elapsedMicroseconds);
      }

      await db.close();

      timingsSelect.sort();
      timingsBytes.sort();
      timingsCBulk.sort();

      final medSelect = timingsSelect[timingsSelect.length ~/ 2] / 1000.0;
      final medBytes = timingsBytes[timingsBytes.length ~/ 2] / 1000.0;
      final medCBulk = timingsCBulk[timingsCBulk.length ~/ 2] / 1000.0;

      // select() includes: isolate spawn + row materialization + Isolate.exit
      // selectBytes() includes: isolate spawn + one FFI call + memcpy + Isolate.exit
      // direct queryBytes(): one leaf FFI call — no isolate, no Dart decode
      //
      // The difference between select()/selectBytes() and direct queryBytes()
      // shows the total cost of isolate hops and Dart-side handling.

      final ffiCalls = rowCount * 16; // approximate
      final overheadMs = medSelect - medCBulk;
      final overheadPerRow = overheadMs / rowCount * 1000; // microseconds

      print('--- $rowCount rows ---');
      print('  select() (maps + isolate):          ${medSelect.toStringAsFixed(2)} ms');
      print('  selectBytes() (bytes + isolate):    ${medBytes.toStringAsFixed(2)} ms');
      print('  direct queryBytes() (leaf FFI):     ${medCBulk.toStringAsFixed(2)} ms');
      print('');
      print('  select() overhead vs direct bytes:  ${overheadMs.toStringAsFixed(2)} ms');
      print('  Per-row overhead:                   ${overheadPerRow.toStringAsFixed(1)} us');
      print('  Estimated row/cell work in select(): ~$ffiCalls');
      print('  Direct native query floor:          ${medCBulk.toStringAsFixed(2)} ms');
      print('');
    } finally {
      await tempDir.delete(recursive: true);
    }
  }
}
