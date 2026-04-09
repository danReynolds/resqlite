// Benchmark: compare the legacy SQLite autocheckpoint policy against a coarse
// manual PASSIVE checkpoint policy using the current resqlite runtime.

import 'dart:io';

import 'package:resqlite/resqlite.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_checkpoint_');

  print('=== WAL checkpoint policy experiment ===\n');

  final baseline = await _runPolicy(
    dir.path,
    name: 'baseline-autocheckpoint-10000',
    prepare: (db) => db.execute('PRAGMA wal_autocheckpoint = 10000'),
  );
  final manual = await _runPolicy(
    dir.path,
    name: 'manual-passive-every-500',
    prepare: (db) => db.execute('PRAGMA wal_autocheckpoint = 0'),
    checkpointEvery: 500,
  );

  _printComparison(baseline, manual);

  await dir.delete(recursive: true);
  exit(0);
}

const _createSql = '''
  CREATE TABLE events(
    id INTEGER PRIMARY KEY,
    payload TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )
''';

const _insertSql = 'INSERT INTO events(payload, created_at) VALUES (?, ?)';
final _payload = 'x' * 8192;

Future<_PolicyResult> _runPolicy(
  String dirPath, {
  required String name,
  Future<void> Function(Database db)? prepare,
  int? checkpointEvery,
}) async {
  final dbPath = '$dirPath/$name.db';
  final db = await Database.open(dbPath);
  await db.execute(_createSql);
  if (prepare != null) await prepare(db);

  final latenciesUs = <int>[];
  final checkpointUs = <int>[];
  final readLatenciesUs = <int>[];
  const writes = 6000;

  for (var i = 0; i < writes; i++) {
    final writeSw = Stopwatch()..start();
    await db.execute(_insertSql, [_payload, i]);
    writeSw.stop();
    latenciesUs.add(writeSw.elapsedMicroseconds);

    if (checkpointEvery != null && (i + 1) % checkpointEvery == 0) {
      final checkpointSw = Stopwatch()..start();
      await db.execute('PRAGMA wal_checkpoint(PASSIVE)');
      checkpointSw.stop();
      checkpointUs.add(checkpointSw.elapsedMicroseconds);
    }

    if ((i + 1) % 200 == 0) {
      final readSw = Stopwatch()..start();
      await db.select('SELECT count(*) AS count FROM events WHERE id > ?', [i - 100]);
      readSw.stop();
      readLatenciesUs.add(readSw.elapsedMicroseconds);
    }
  }

  final walStats = await db.select('PRAGMA wal_checkpoint(NOOP)');
  await db.close();

  return _PolicyResult(
    name: name,
    writes: writes,
    writeP50Ms: _percentileMs(latenciesUs, 0.50),
    writeP95Ms: _percentileMs(latenciesUs, 0.95),
    writeP99Ms: _percentileMs(latenciesUs, 0.99),
    writeMaxMs: _percentileMs(latenciesUs, 1.0),
    readP95Ms: readLatenciesUs.isEmpty ? 0 : _percentileMs(readLatenciesUs, 0.95),
    checkpointP95Ms: checkpointUs.isEmpty ? null : _percentileMs(checkpointUs, 0.95),
    walStats: walStats.first,
  );
}

void _printComparison(_PolicyResult baseline, _PolicyResult manual) {
  print('| Policy | Write p50 | Write p95 | Write p99 | Write max | Read p95 | Checkpoint p95 | WAL noop |');
  print('|---|---:|---:|---:|---:|---:|---:|---|');
  for (final result in [baseline, manual]) {
    final walBusy = result.walStats['busy'];
    final walLog = result.walStats['log'];
    final walCheckpointed = result.walStats['checkpointed'];
    print(
      '| ${result.name} '
      '| ${result.writeP50Ms.toStringAsFixed(2)} ms '
      '| ${result.writeP95Ms.toStringAsFixed(2)} ms '
      '| ${result.writeP99Ms.toStringAsFixed(2)} ms '
      '| ${result.writeMaxMs.toStringAsFixed(2)} ms '
      '| ${result.readP95Ms.toStringAsFixed(2)} ms '
      '| ${result.checkpointP95Ms?.toStringAsFixed(2) ?? 'n/a'} ms '
      '| busy=$walBusy log=$walLog ckpt=$walCheckpointed |',
    );
  }
}

double _percentileMs(List<int> valuesUs, double percentile) {
  final sorted = [...valuesUs]..sort();
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index] / 1000;
}

final class _PolicyResult {
  const _PolicyResult({
    required this.name,
    required this.writes,
    required this.writeP50Ms,
    required this.writeP95Ms,
    required this.writeP99Ms,
    required this.writeMaxMs,
    required this.readP95Ms,
    required this.checkpointP95Ms,
    required this.walStats,
  });

  final String name;
  final int writes;
  final double writeP50Ms;
  final double writeP95Ms;
  final double writeP99Ms;
  final double writeMaxMs;
  final double readP95Ms;
  final double? checkpointP95Ms;
  final Map<String, Object?> walStats;
}
