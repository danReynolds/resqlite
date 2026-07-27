// Focused A/B harness for exp 252: merge cached writer dirty-column
// dependencies once per executeBatch call.
//
// The product row mirrors Dune's identity sync:
//   * UPDATE devices SET ip, last_seen_at, online ... (one batch)
//   * UPDATE peers SET last_seen_at, online ...       (one batch)
//
// Dune performs the pair every 2 seconds for the first 20 seconds after
// connect, then every 5 seconds. Parameter lists are built outside the timed
// region. The wide UPDATE is a mechanism ceiling, not a product gate.
//
// Usage:
//   dart run benchmark/experiments/dirty_column_batch_merge.dart
//   dart run benchmark/experiments/dirty_column_batch_merge.dart \
//     --warmup=10 --samples=31 --sizes=1,10,100,1000 --wide-rows=10000

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _defaultWarmup = 8;
const _defaultSamples = 21;
const _defaultSizes = [1, 10, 100, 1000];
const _defaultWideRows = 10000;
const _wideColumns = 20;

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  print(
    'dirty-column batch merge: warmup=${options.warmup} '
    'samples=${options.samples}',
  );

  for (final rowsPerTable in options.sizes) {
    final result = await _measureDuneShape(
      rowsPerTable: rowsPerTable,
      warmup: options.warmup,
      samples: options.samples,
    );
    _printResult('dune-${rowsPerTable}x2', result);
  }

  final miss = await _measureDuneShape(
    rowsPerTable: 100,
    warmup: options.warmup,
    samples: options.samples,
    matchRows: false,
  );
  _printResult('dune-miss-100x2', miss);

  if (options.wideRows > 0) {
    final wide = await _measureWideShape(
      rows: options.wideRows,
      warmup: options.warmup,
      samples: options.samples,
    );
    _printResult('wide-${options.wideRows}x$_wideColumns', wide);
  }
}

Future<List<int>> _measureDuneShape({
  required int rowsPerTable,
  required int warmup,
  required int samples,
  bool matchRows = true,
}) async {
  final temp = await Directory.systemTemp.createTemp('resqlite_exp252_dune_');
  try {
    final db = await Database.open('${temp.path}/dune.db');
    try {
      await db.execute(
        'CREATE TABLE devices('
        'signing_key TEXT PRIMARY KEY, '
        'encryption_key TEXT, peer_key TEXT, ip TEXT, name TEXT, '
        'last_seen_at INTEGER, created_at INTEGER, updated_at INTEGER, '
        'online INTEGER, revoked_at INTEGER, node_id TEXT NOT NULL, '
        'verified INTEGER NOT NULL DEFAULT 0, verified_at INTEGER)',
      );
      await db.execute(
        'CREATE TABLE peers('
        'key TEXT PRIMARY KEY, name TEXT, bio TEXT, '
        'last_seen_at INTEGER, created_at INTEGER, updated_at INTEGER, '
        'image TEXT, online INTEGER, revoked_at INTEGER)',
      );
      await db.executeBatch(
        'INSERT INTO devices('
        'signing_key, encryption_key, peer_key, ip, name, last_seen_at, '
        'created_at, updated_at, online, revoked_at, node_id, verified, '
        'verified_at'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          for (var i = 0; i < rowsPerTable; i++)
            [
              'device-$i',
              'encryption-$i',
              'peer-$i',
              '100.64.0.$i',
              'Device $i',
              0,
              900000,
              900000,
              0,
              null,
              'node-$i',
              1,
              900000,
            ],
        ],
      );
      await db.executeBatch(
        'INSERT INTO peers('
        'key, name, bio, last_seen_at, created_at, updated_at, image, '
        'online, revoked_at'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          for (var i = 0; i < rowsPerTable; i++)
            [
              'peer-$i',
              'Peer $i',
              'Bio $i',
              0,
              900000,
              900000,
              'image-$i',
              0,
              null,
            ],
        ],
      );

      const updateDevices =
          'UPDATE devices '
          'SET ip = ?, last_seen_at = ?, online = ? '
          'WHERE signing_key = ?';
      const updatePeers =
          'UPDATE peers '
          'SET last_seen_at = ?, online = ? '
          'WHERE key = ?';
      final deviceRows = [
        for (var phase = 0; phase < 2; phase++)
          [
            for (var i = 0; i < rowsPerTable; i++)
              [
                '100.65.$phase.$i',
                1000000 + phase,
                phase,
                matchRows ? 'device-$i' : 'missing-device-$i',
              ],
          ],
      ];
      final peerRows = [
        for (var phase = 0; phase < 2; phase++)
          [
            for (var i = 0; i < rowsPerTable; i++)
              [
                1000000 + phase,
                phase,
                matchRows ? 'peer-$i' : 'missing-peer-$i',
              ],
          ],
      ];

      for (var i = 0; i < warmup; i++) {
        final phase = i & 1;
        await db.executeBatch(updateDevices, deviceRows[phase]);
        await db.executeBatch(updatePeers, peerRows[phase]);
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      }

      final timings = <int>[];
      for (var i = 0; i < samples; i++) {
        final phase = (i + warmup) & 1;
        final stopwatch = Stopwatch()..start();
        await db.executeBatch(updateDevices, deviceRows[phase]);
        await db.executeBatch(updatePeers, peerRows[phase]);
        stopwatch.stop();
        timings.add(stopwatch.elapsedMicroseconds);
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      }
      final finalPhase = (samples - 1 + warmup) & 1;
      final device = await db.select(
        'SELECT ip, online FROM devices WHERE signing_key = ?',
        ['device-0'],
      );
      final peer = await db.select('SELECT online FROM peers WHERE key = ?', [
        'peer-0',
      ]);
      if (matchRows) {
        if (device.single['ip'] != '100.65.$finalPhase.0' ||
            device.single['online'] != finalPhase ||
            peer.single['online'] != finalPhase) {
          throw StateError('Dune-shaped updates did not reach sentinel rows');
        }
      } else if (device.single['ip'] != '100.64.0.0' ||
          device.single['online'] != 0 ||
          peer.single['online'] != 0) {
        throw StateError('Missing-key control unexpectedly modified a row');
      }
      return timings;
    } finally {
      await db.close();
    }
  } finally {
    await temp.delete(recursive: true);
  }
}

Future<List<int>> _measureWideShape({
  required int rows,
  required int warmup,
  required int samples,
}) async {
  final temp = await Directory.systemTemp.createTemp('resqlite_exp252_wide_');
  try {
    final db = await Database.open('${temp.path}/wide.db');
    try {
      final definitions = [
        for (var i = 0; i < _wideColumns; i++) 'c$i INTEGER NOT NULL',
      ].join(', ');
      await db.execute(
        'CREATE TABLE wide(id INTEGER PRIMARY KEY, $definitions)',
      );
      final insertColumns = [
        'id',
        for (var i = 0; i < _wideColumns; i++) 'c$i',
      ].join(', ');
      final insertParams = List.filled(_wideColumns + 1, '?').join(', ');
      await db.executeBatch(
        'INSERT INTO wide($insertColumns) VALUES ($insertParams)',
        [
          for (var row = 0; row < rows; row++)
            [row, for (var column = 0; column < _wideColumns; column++) 0],
        ],
      );

      final assignments = [
        for (var i = 0; i < _wideColumns; i++) 'c$i = ?',
      ].join(', ');
      final updateSql = 'UPDATE wide SET $assignments WHERE id = ?';
      final parameterRows = [
        for (var phase = 0; phase < 2; phase++)
          [
            for (var row = 0; row < rows; row++)
              [
                for (var column = 0; column < _wideColumns; column++)
                  phase + column,
                row,
              ],
          ],
      ];

      for (var i = 0; i < warmup; i++) {
        await db.executeBatch(updateSql, parameterRows[i & 1]);
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      }

      final timings = <int>[];
      for (var i = 0; i < samples; i++) {
        final stopwatch = Stopwatch()..start();
        await db.executeBatch(updateSql, parameterRows[(i + warmup) & 1]);
        stopwatch.stop();
        timings.add(stopwatch.elapsedMicroseconds);
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      }
      final finalPhase = (samples - 1 + warmup) & 1;
      final sentinel = await db.select(
        'SELECT c0, c19 FROM wide WHERE id = ?',
        [rows - 1],
      );
      if (sentinel.single['c0'] != finalPhase ||
          sentinel.single['c19'] != finalPhase + 19) {
        throw StateError('Wide updates did not reach sentinel row');
      }
      return timings;
    } finally {
      await db.close();
    }
  } finally {
    await temp.delete(recursive: true);
  }
}

void _printResult(String shape, List<int> samples) {
  final sorted = [...samples]..sort();
  final median = _percentile(sorted, 0.50);
  final p10 = _percentile(sorted, 0.10);
  final p90 = _percentile(sorted, 0.90);
  print(
    'shape=$shape median_us=$median p10_us=$p10 p90_us=$p90 '
    'samples_us=${samples.join(',')}',
  );
}

int _percentile(List<int> sorted, double percentile) {
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index];
}

final class _Options {
  const _Options({
    required this.warmup,
    required this.samples,
    required this.sizes,
    required this.wideRows,
  });

  final int warmup;
  final int samples;
  final List<int> sizes;
  final int wideRows;

  static _Options parse(List<String> args) {
    var warmup = _defaultWarmup;
    var samples = _defaultSamples;
    var sizes = _defaultSizes;
    var wideRows = _defaultWideRows;

    for (final arg in args) {
      if (arg.startsWith('--warmup=')) {
        warmup = int.parse(arg.substring('--warmup='.length));
      } else if (arg.startsWith('--samples=')) {
        samples = int.parse(arg.substring('--samples='.length));
      } else if (arg.startsWith('--sizes=')) {
        sizes = arg
            .substring('--sizes='.length)
            .split(',')
            .map(int.parse)
            .toList(growable: false);
      } else if (arg.startsWith('--wide-rows=')) {
        wideRows = int.parse(arg.substring('--wide-rows='.length));
      } else {
        throw ArgumentError('Unknown option: $arg');
      }
    }

    if (warmup < 0 || samples < 1 || sizes.any((size) => size < 1)) {
      throw ArgumentError('warmup >= 0, samples >= 1, sizes >= 1 required');
    }
    return _Options(
      warmup: warmup,
      samples: samples,
      sizes: sizes,
      wideRows: wideRows,
    );
  }
}
