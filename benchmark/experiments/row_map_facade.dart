// ignore_for_file: avoid_print
import 'dart:collection';

import '../../lib/resqlite.dart';

import '../shared/config.dart';
import '../shared/stats.dart';

int _sink = 0;

final class _Case {
  const _Case(this.label, this.innerLoops);

  final String label;
  final int innerLoops;
}

void main() {
  final schema = RowSchema([
    'id',
    'name',
    'email',
    'device_id',
    'is_active',
    'updated_at',
    'city',
    'country',
  ]);
  final values = <Object?>[
    42,
    'Ada',
    'ada@example.com',
    'device_123',
    1,
    1712345678,
    'Toronto',
    'Canada',
  ];
  final row = ResultSet(values, schema, 1)[0];
  final map = LinkedHashMap<String, Object?>.fromIterables(schema.names, values);

  final cases = <_Case>[
    _Case('hot lookup', 200000),
    _Case('containsKey', 500000),
    _Case('iterate keys + lookup', 75000),
    _Case('forEach', 100000),
    _Case('entries iteration', 75000),
    _Case('values iteration', 100000),
    _Case('Map.from clone', 15000),
  ];

  print('');
  print('=== Row Map Facade ===');
  print('Compares Row/Map-like operations on resqlite Row vs LinkedHashMap');
  print('');
  print('| Case | Row median (ms) | Map median (ms) | Delta (ms) |');
  print('|---|---:|---:|---:|');

  for (final testCase in cases) {
    final rowTiming = BenchmarkTiming('${testCase.label} row');
    final mapTiming = BenchmarkTiming('${testCase.label} map');

    for (var i = 0; i < defaultWarmup; i++) {
      _runInner(testCase.innerLoops, () => _runRowCase(testCase.label, row));
      _runInner(testCase.innerLoops, () => _runMapCase(testCase.label, map));
    }

    for (var i = 0; i < defaultIterations; i++) {
      final swRow = Stopwatch()..start();
      _runInner(
        testCase.innerLoops,
        () => _runRowCase(testCase.label, row),
      );
      swRow.stop();
      rowTiming.recordWallOnly(swRow.elapsedMicroseconds);

      final swMap = Stopwatch()..start();
      _runInner(
        testCase.innerLoops,
        () => _runMapCase(testCase.label, map),
      );
      swMap.stop();
      mapTiming.recordWallOnly(swMap.elapsedMicroseconds);
    }

    final delta = rowTiming.wall.medianMs - mapTiming.wall.medianMs;
    print(
      '| ${testCase.label} '
      '| ${rowTiming.wall.medianMs.toStringAsFixed(3)} '
      '| ${mapTiming.wall.medianMs.toStringAsFixed(3)} '
      '| ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(3)} |',
    );
  }

  if (_sink == 0x7fffffff) {
    print('ignore $_sink');
  }
}

void _runInner(int iterations, void Function() body) {
  for (var i = 0; i < iterations; i++) {
    body();
  }
}

void _runRowCase(String label, Row row) {
  switch (label) {
    case 'hot lookup':
      _sink ^= row['id'] as int;
      _sink ^= row['updated_at'] as int;
    case 'containsKey':
      if (row.containsKey('updated_at')) _sink++;
    case 'iterate keys + lookup':
      for (final key in row.keys) {
        final value = row[key];
        if (value is int) _sink ^= value;
      }
    case 'forEach':
      row.forEach((key, value) {
        if (value is int) _sink ^= value;
      });
    case 'entries iteration':
      for (final entry in row.entries) {
        if (entry.value is int) _sink ^= entry.value as int;
      }
    case 'values iteration':
      for (final value in row.values) {
        if (value is int) _sink ^= value;
      }
    case 'Map.from clone':
      _sink ^= Map<String, Object?>.from(row).length;
  }
}

void _runMapCase(String label, Map<String, Object?> map) {
  switch (label) {
    case 'hot lookup':
      _sink ^= map['id'] as int;
      _sink ^= map['updated_at'] as int;
    case 'containsKey':
      if (map.containsKey('updated_at')) _sink++;
    case 'iterate keys + lookup':
      for (final key in map.keys) {
        final value = map[key];
        if (value is int) _sink ^= value;
      }
    case 'forEach':
      map.forEach((key, value) {
        if (value is int) _sink ^= value;
      });
    case 'entries iteration':
      for (final entry in map.entries) {
        if (entry.value is int) _sink ^= entry.value as int;
      }
    case 'values iteration':
      for (final value in map.values) {
        if (value is int) _sink ^= value;
      }
    case 'Map.from clone':
      _sink ^= Map<String, Object?>.from(map).length;
  }
}
