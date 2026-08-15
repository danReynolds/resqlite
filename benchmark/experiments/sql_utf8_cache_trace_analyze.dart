import 'dart:convert';
import 'dart:io';

const _traceMarker = 'RESQLITE_SQL_CACHE_TRACE';
const _sanitizedHeader =
    'scenario\tgroup\tsequence\tsql_id\tutf8_bytes\tactual_hit\treuse_rank';

void main(List<String> arguments) {
  final args = [...arguments];
  String? sanitizedOut;
  for (final arg in [...args]) {
    if (arg.startsWith('--sanitized-out=')) {
      sanitizedOut = arg.substring('--sanitized-out='.length);
      args.remove(arg);
    }
  }

  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run benchmark/experiments/'
      'sql_utf8_cache_trace_analyze.dart '
      '[--sanitized-out=PATH] LABEL=RAW_LOG [...] | SANITIZED_TSV',
    );
    exitCode = 64;
    return;
  }

  final events = args.length == 1 && args.single.endsWith('.tsv')
      ? _readSanitized(File(args.single))
      : _readRaw(args);
  final analysis = _analyze(events);

  if (sanitizedOut != null) {
    File(sanitizedOut).writeAsStringSync(_renderSanitized(analysis.events));
  }

  stdout.writeln(
    'scenario\tgroups\tcalls\tcold\td1_32\td33_128\td129p\t'
    'misses32\tmisses128\trescued\trescued_bytes_incl_nul\t'
    'actual_matches',
  );
  for (final summary in [...analysis.byScenario.values, analysis.total]) {
    stdout.writeln(summary.toTsv());
  }
}

List<_Event> _readRaw(List<String> specs) {
  final events = <_Event>[];
  for (final spec in specs) {
    final separator = spec.indexOf('=');
    if (separator <= 0 || separator == spec.length - 1) {
      throw FormatException('raw input must be LABEL=PATH: $spec');
    }
    final scenario = spec.substring(0, separator);
    final file = File(spec.substring(separator + 1));
    final groupNames = <String, String>{};
    final roleCounts = <String, int>{};
    final sqlIds = <String, Map<String, String>>{};

    for (final line in file.readAsLinesSync()) {
      if (!line.startsWith('$_traceMarker\t')) continue;
      final fields = line.split('\t');
      if (fields.length != 9) {
        throw FormatException('${file.path}: malformed trace line: $line');
      }
      final rawGroup = '${fields[1]}/${fields[2]}/${fields[3]}';
      final role = fields[2].replaceFirst('Entrypoint', '');
      final group = groupNames.putIfAbsent(rawGroup, () {
        final ordinal = (roleCounts[role] ?? 0) + 1;
        roleCounts[role] = ordinal;
        return '$role$ordinal';
      });
      final identities = sqlIds.putIfAbsent(group, () => <String, String>{});
      final utf8Bytes = int.parse(fields[7]);
      final decodedSql = base64Url.decode(fields[8]);
      if (decodedSql.length != utf8Bytes) {
        throw StateError(
          '${file.path}: recorded $utf8Bytes SQL bytes, '
          'decoded ${decodedSql.length}',
        );
      }
      final sqlId = identities.putIfAbsent(
        fields[8],
        () => 'q${identities.length + 1}',
      );
      events.add(
        _Event(
          scenario: scenario,
          group: group,
          sequence: int.parse(fields[4]),
          sqlId: sqlId,
          utf8Bytes: utf8Bytes,
          actualHit: _parseBit(fields[6], file.path),
        ),
      );
    }
  }
  return events;
}

List<_Event> _readSanitized(File file) {
  final lines = file.readAsLinesSync();
  if (lines.isEmpty || lines.first != _sanitizedHeader) {
    throw FormatException('${file.path}: missing sanitized trace header');
  }
  return [
    for (final line in lines.skip(1))
      if (line.isNotEmpty) _Event.fromSanitized(line, file.path),
  ];
}

_Analysis _analyze(List<_Event> events) {
  final states = <String, _GroupState>{};
  final byScenario = <String, _Summary>{};
  final total = _Summary('TOTAL');
  final analyzed = <_Event>[];

  for (final event in events) {
    final groupKey = '${event.scenario}/${event.group}';
    final state = states.putIfAbsent(groupKey, _GroupState.new);
    final expectedSequence = state.lastSequence + 1;
    if (event.sequence != expectedSequence) {
      throw StateError(
        '$groupKey: expected sequence $expectedSequence, '
        'got ${event.sequence}',
      );
    }
    state.lastSequence = event.sequence;

    final index = state.lru.indexOf(event.sqlId);
    final reuseRank = index < 0 ? null : index + 1;
    if (event.hasReportedReuseRank && event.reportedReuseRank != reuseRank) {
      throw StateError(
        '$groupKey/${event.sequence}: reported reuse rank '
        '${event.reportedReuseRank}, replayed $reuseRank',
      );
    }
    final expectedHit = reuseRank != null && reuseRank <= 32;
    if (event.actualHit != expectedHit) {
      throw StateError(
        '$groupKey/${event.sequence}: actual hit ${event.actualHit}, '
        'replay expected $expectedHit',
      );
    }

    if (index >= 0) state.lru.removeAt(index);
    state.lru.insert(0, event.sqlId);

    final resolved = event.withReuseRank(reuseRank);
    analyzed.add(resolved);
    final scenario = byScenario.putIfAbsent(
      event.scenario,
      () => _Summary(event.scenario),
    );
    scenario.add(groupKey, reuseRank, event.utf8Bytes);
    total.add(groupKey, reuseRank, event.utf8Bytes);
  }

  return _Analysis(events: analyzed, byScenario: byScenario, total: total);
}

String _renderSanitized(List<_Event> events) {
  final buffer = StringBuffer()..writeln(_sanitizedHeader);
  for (final event in events) {
    buffer.writeln(event.toSanitized());
  }
  return buffer.toString();
}

final class _Event {
  const _Event({
    required this.scenario,
    required this.group,
    required this.sequence,
    required this.sqlId,
    required this.utf8Bytes,
    required this.actualHit,
    this.reportedReuseRank,
    this.hasReportedReuseRank = false,
  });

  factory _Event.fromSanitized(String line, String path) {
    final fields = line.split('\t');
    if (fields.length != 7) {
      throw FormatException('$path: malformed sanitized line: $line');
    }
    return _Event(
      scenario: fields[0],
      group: fields[1],
      sequence: int.parse(fields[2]),
      sqlId: fields[3],
      utf8Bytes: int.parse(fields[4]),
      actualHit: _parseBit(fields[5], path),
      reportedReuseRank: fields[6] == 'cold' ? null : int.parse(fields[6]),
      hasReportedReuseRank: true,
    );
  }

  final String scenario;
  final String group;
  final int sequence;
  final String sqlId;
  final int utf8Bytes;
  final bool actualHit;
  final int? reportedReuseRank;
  final bool hasReportedReuseRank;

  _Event withReuseRank(int? reuseRank) => _Event(
    scenario: scenario,
    group: group,
    sequence: sequence,
    sqlId: sqlId,
    utf8Bytes: utf8Bytes,
    actualHit: actualHit,
    reportedReuseRank: reuseRank,
    hasReportedReuseRank: true,
  );

  String toSanitized() => [
    scenario,
    group,
    sequence,
    sqlId,
    utf8Bytes,
    actualHit ? 1 : 0,
    reportedReuseRank ?? 'cold',
  ].join('\t');
}

bool _parseBit(String value, String source) {
  if (value == '0') return false;
  if (value == '1') return true;
  throw FormatException('$source: expected hit bit 0 or 1, got $value');
}

final class _GroupState {
  final List<String> lru = [];
  int lastSequence = -1;
}

final class _Summary {
  _Summary(this.name);

  final String name;
  final Set<String> groups = {};
  int calls = 0;
  int cold = 0;
  int d1To32 = 0;
  int d33To128 = 0;
  int d129Plus = 0;
  int rescuedBytesIncludingNul = 0;

  void add(String group, int? rank, int utf8Bytes) {
    groups.add(group);
    calls++;
    if (rank == null) {
      cold++;
    } else if (rank <= 32) {
      d1To32++;
    } else if (rank <= 128) {
      d33To128++;
      rescuedBytesIncludingNul += utf8Bytes + 1;
    } else {
      d129Plus++;
    }
  }

  String toTsv() {
    final misses32 = cold + d33To128 + d129Plus;
    final misses128 = cold + d129Plus;
    return [
      name,
      groups.length,
      calls,
      cold,
      d1To32,
      d33To128,
      d129Plus,
      misses32,
      misses128,
      misses32 - misses128,
      rescuedBytesIncludingNul,
      '$calls/$calls',
    ].join('\t');
  }
}

final class _Analysis {
  const _Analysis({
    required this.events,
    required this.byScenario,
    required this.total,
  });

  final List<_Event> events;
  final Map<String, _Summary> byScenario;
  final _Summary total;
}
