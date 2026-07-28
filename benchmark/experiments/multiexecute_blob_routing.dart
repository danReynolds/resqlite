// Focused end-to-end harness for large-BLOB routing in the coalesced
// MultiExecuteRequest path.
//
// Each burst uses the public Future.wait([db.execute(...), ...]) shape. The
// writer pump sends the first request alone; writes accumulated while that
// reply is in flight are sent in the following MultiExecuteRequest. Run this
// harness in separate baseline and candidate processes/worktrees.
//
// Example:
//
//   dart run benchmark/experiments/multiexecute_blob_routing.dart \
//     --shape=distinct --size-kb=256 --samples=7 --bursts=3 --writes=12
//
// Shapes:
//
// - distinct: every write in a burst references a different large blob.
// - shared: every write references the same large blob object.
// - mixed: the first write is distinct; at least two later writes share one
//   blob, and the rest are distinct.
// - control: distinct sub-threshold blobs (size-kb must be below 256).
//
// Timing covers only the public Future.wait write bursts. Database setup,
// payload construction, warmup, result verification, and deletion are outside
// the timed region. The final RESULT line is JSON for machine consumption.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';

const _insertSql = '''
INSERT INTO blob_doc(sample_id, burst_id, write_id, payload, checksum)
VALUES (?, ?, ?, ?, ?)
''';

Future<void> main(List<String> args) async {
  late final _Options options;
  try {
    options = _Options.parse(args);
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}');
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  if (options.help) {
    stdout.writeln(_usage);
    return;
  }

  final workload = _Workload.build(options);
  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite-multiexecute-blob-',
  );
  Database? db;

  try {
    db = await Database.open('${tempDir.path}/routing.db');
    final journalRows = await db.select('PRAGMA journal_mode');
    final journalMode = journalRows.single.values.single
        .toString()
        .toLowerCase();
    if (journalMode != 'wal') {
      throw StateError('Expected WAL journal mode, got $journalMode.');
    }

    await db.execute('''
CREATE TABLE blob_doc(
  sample_id INTEGER NOT NULL,
  burst_id INTEGER NOT NULL,
  write_id INTEGER NOT NULL,
  payload BLOB NOT NULL,
  checksum INTEGER NOT NULL,
  PRIMARY KEY(sample_id, burst_id, write_id)
)
''');

    stdout.writeln(
      'MultiExecute blob routing: '
      'shape=${options.shape.name} '
      'size=${options.sizeKb} KiB '
      'samples=${options.samples} '
      'bursts=${options.bursts} '
      'writes=${options.writes} '
      'pid=$pid',
    );

    await _executeBursts(
      db,
      workload,
      sampleId: -1,
      bursts: options.warmupBursts,
    );
    await _verifyAggregate(
      db,
      workload,
      sampleId: -1,
      bursts: options.warmupBursts,
    );
    await db.execute('DELETE FROM blob_doc');

    final samplesUsPerWrite = <double>[];
    for (var sample = 0; sample < options.samples; sample++) {
      final stopwatch = Stopwatch()..start();
      await _executeBursts(
        db,
        workload,
        sampleId: sample,
        bursts: options.bursts,
      );
      stopwatch.stop();

      final totalWrites = options.bursts * options.writes;
      final usPerWrite = stopwatch.elapsedMicroseconds / totalWrites;
      samplesUsPerWrite.add(usPerWrite);
      stdout.writeln(
        'SAMPLE ${jsonEncode({'shape': options.shape.name, 'size_kb': options.sizeKb, 'sample': sample + 1, 'elapsed_us': stopwatch.elapsedMicroseconds, 'writes': totalWrites, 'us_per_write': usPerWrite})}',
      );

      await _verifyAggregate(
        db,
        workload,
        sampleId: sample,
        bursts: options.bursts,
      );
      if (sample == options.samples - 1) {
        await _verifyPayloads(
          db,
          workload,
          sampleId: sample,
          bursts: options.bursts,
        );
      }
      await db.execute('DELETE FROM blob_doc');
    }

    final medianUsPerWrite = _median(samplesUsPerWrite);
    stdout.writeln(
      'RESULT ${jsonEncode({'shape': options.shape.name, 'size_kb': options.sizeKb, 'samples': options.samples, 'bursts_per_sample': options.bursts, 'writes_per_burst': options.writes, 'total_writes_per_sample': options.bursts * options.writes, 'samples_us_per_write': samplesUsPerWrite, 'median_us_per_write': medianUsPerWrite})}',
    );
  } finally {
    if (db != null) await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<void> _executeBursts(
  Database db,
  _Workload workload, {
  required int sampleId,
  required int bursts,
}) async {
  for (var burst = 0; burst < bursts; burst++) {
    await Future.wait([
      for (var write = 0; write < workload.blobs.length; write++)
        db.execute(_insertSql, [
          sampleId,
          burst,
          write,
          workload.blobs[write],
          workload.checksums[write],
        ]),
    ]);
  }
}

Future<void> _verifyAggregate(
  Database db,
  _Workload workload, {
  required int sampleId,
  required int bursts,
}) async {
  final rows = await db.select(
    '''
SELECT
  COUNT(*) AS row_count,
  COALESCE(SUM(length(payload)), 0) AS payload_bytes,
  COALESCE(SUM(checksum), 0) AS checksum_sum
FROM blob_doc
WHERE sample_id = ?
''',
    [sampleId],
  );
  final row = rows.single;
  final expectedRows = bursts * workload.blobs.length;
  final expectedBytes = bursts * workload.totalBytes;
  final expectedChecksum = bursts * workload.checksumSum;

  if (row['row_count'] != expectedRows ||
      row['payload_bytes'] != expectedBytes ||
      row['checksum_sum'] != expectedChecksum) {
    throw StateError(
      'Aggregate verification failed for sample $sampleId: '
      'got count=${row['row_count']} bytes=${row['payload_bytes']} '
      'checksum=${row['checksum_sum']}; expected count=$expectedRows '
      'bytes=$expectedBytes checksum=$expectedChecksum.',
    );
  }
}

Future<void> _verifyPayloads(
  Database db,
  _Workload workload, {
  required int sampleId,
  required int bursts,
}) async {
  final rows = await db.select(
    '''
SELECT burst_id, write_id, payload, checksum
FROM blob_doc
WHERE sample_id = ?
ORDER BY burst_id, write_id
''',
    [sampleId],
  );
  final expectedRows = bursts * workload.blobs.length;
  if (rows.length != expectedRows) {
    throw StateError(
      'Payload verification expected $expectedRows rows, got ${rows.length}.',
    );
  }

  for (final row in rows) {
    final write = row['write_id'] as int;
    final payload = row['payload'] as Uint8List;
    final expectedChecksum = workload.checksums[write];
    final actualChecksum = _checksum(payload);
    if (payload.length != workload.blobs[write].length ||
        row['checksum'] != expectedChecksum ||
        actualChecksum != expectedChecksum) {
      throw StateError(
        'Payload verification failed at burst=${row['burst_id']} '
        'write=$write: length=${payload.length}, '
        'stored_checksum=${row['checksum']}, '
        'actual_checksum=$actualChecksum, '
        'expected_checksum=$expectedChecksum.',
      );
    }
  }
}

final class _Workload {
  _Workload(this.blobs, this.checksums)
    : totalBytes = blobs.fold(0, (sum, blob) => sum + blob.length),
      checksumSum = checksums.fold(0, (sum, checksum) => sum + checksum);

  factory _Workload.build(_Options options) {
    final sizeBytes = options.sizeKb * 1024;
    final blobs = <Uint8List>[];

    switch (options.shape) {
      case _Shape.distinct:
      case _Shape.control:
        for (var i = 0; i < options.writes; i++) {
          blobs.add(_makeBlob(sizeBytes, seed: i + 1));
        }
      case _Shape.shared:
        final shared = _makeBlob(sizeBytes, seed: 1);
        blobs.addAll(List<Uint8List>.filled(options.writes, shared));
      case _Shape.mixed:
        final shared = _makeBlob(sizeBytes, seed: 0x5a);
        final sharedEnd = options.writes ~/ 2;
        for (var i = 0; i < options.writes; i++) {
          // Keep write 0 distinct because the public pump sends it alone.
          // Writes 1..sharedEnd then exercise aliasing inside MultiExecute.
          blobs.add(
            i >= 1 && i <= sharedEnd
                ? shared
                : _makeBlob(sizeBytes, seed: i + 1),
          );
        }
    }

    return _Workload(blobs, [for (final blob in blobs) _checksum(blob)]);
  }

  final List<Uint8List> blobs;
  final List<int> checksums;
  final int totalBytes;
  final int checksumSum;
}

enum _Shape { distinct, shared, mixed, control }

final class _Options {
  const _Options({
    required this.shape,
    required this.sizeKb,
    required this.samples,
    required this.bursts,
    required this.writes,
    required this.warmupBursts,
    required this.help,
  });

  factory _Options.parse(List<String> args) {
    final values = <String, String>{};
    var help = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--help' || arg == '-h') {
        help = true;
        continue;
      }
      if (!arg.startsWith('--')) {
        throw FormatException('Unexpected positional argument: $arg');
      }

      final equals = arg.indexOf('=');
      late final String key;
      late final String value;
      if (equals >= 0) {
        key = arg.substring(2, equals);
        value = arg.substring(equals + 1);
      } else {
        key = arg.substring(2);
        if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
          throw FormatException('Missing value for --$key.');
        }
        value = args[++i];
      }
      if (!{
        'shape',
        'size-kb',
        'samples',
        'bursts',
        'writes',
        'warmup-bursts',
      }.contains(key)) {
        throw FormatException('Unknown option: --$key');
      }
      values[key] = value;
    }

    final shapeName = values['shape'] ?? 'distinct';
    final shape = _Shape.values
        .where((value) => value.name == shapeName)
        .firstOrNull;
    if (shape == null) {
      throw FormatException(
        'Invalid --shape=$shapeName; expected distinct, shared, mixed, or control.',
      );
    }

    int integer(String key, int defaultValue) {
      final raw = values[key];
      if (raw == null) return defaultValue;
      final parsed = int.tryParse(raw);
      if (parsed == null || parsed <= 0) {
        throw FormatException('--$key must be a positive integer, got "$raw".');
      }
      return parsed;
    }

    final sizeKb = integer('size-kb', shape == _Shape.control ? 128 : 256);
    final samples = integer('samples', 7);
    final bursts = integer('bursts', 3);
    final writes = integer('writes', 12);
    final warmupBursts = integer('warmup-bursts', 2);

    if (writes < 4) {
      throw const FormatException(
        '--writes must be at least 4 so the first request is single and the '
        'remaining group exercises MultiExecute.',
      );
    }
    if (shape == _Shape.control && sizeKb >= 256) {
      throw const FormatException(
        '--shape=control requires --size-kb below the 256 KiB wrap threshold.',
      );
    }
    if (shape != _Shape.control && sizeKb < 256) {
      throw const FormatException(
        'distinct/shared/mixed require --size-kb at least 256; use '
        '--shape=control for a sub-threshold lane.',
      );
    }

    return _Options(
      shape: shape,
      sizeKb: sizeKb,
      samples: samples,
      bursts: bursts,
      writes: writes,
      warmupBursts: warmupBursts,
      help: help,
    );
  }

  final _Shape shape;
  final int sizeKb;
  final int samples;
  final int bursts;
  final int writes;
  final int warmupBursts;
  final bool help;
}

Uint8List _makeBlob(int length, {required int seed}) {
  final blob = Uint8List(length);
  for (var i = 0; i < blob.length; i++) {
    blob[i] = (i * 31 + seed * 17 + 7) & 0xff;
  }
  return blob;
}

int _checksum(Uint8List bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

const _usage = '''
Usage:
  dart run benchmark/experiments/multiexecute_blob_routing.dart [options]

Options:
  --shape=distinct|shared|mixed|control
      Workload identity shape (default: distinct).
  --size-kb=N
      Bytes per blob in KiB (default: 256, or 128 for control).
  --samples=N
      Timed samples (default: 7).
  --bursts=N
      Future.wait bursts per sample (default: 3).
  --writes=N
      Concurrent db.execute calls per burst, minimum 4 (default: 12).
  --warmup-bursts=N
      Untimed warmup bursts (default: 2).
  --help
      Show this help.
''';
