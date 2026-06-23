import 'dart:convert';
import 'dart:io';

import 'generate_signals.dart' as generate_signals;

const _experimentsDir = 'experiments';
const _readmePath = '$_experimentsDir/README.md';
const _signalsPath = '$_experimentsDir/signals.json';
final _outcomeClassPattern = RegExp(
  r'^(accepted(_.+)?|rejected(_.+)?|in_review(_.+)?|watch|benchmark_gap|deferred)$',
);

void main() {
  final errors = <_ValidationError>[];
  final experimentIdErrorCount = errors.length;
  final experimentIndex = _readExperimentIndex(errors);
  final hasExperimentIdErrors = errors.length > experimentIdErrorCount;
  final signals = _readSignals(errors);

  if (signals != null && !hasExperimentIdErrors) {
    _checkSignals(signals, experimentIndex, errors);
  }

  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln('::error file=${error.file}::${error.message}');
    }
    exitCode = 1;
    return;
  }

  print('Experiment signal map is valid.');
}

/// Builds the experiment index from the per-experiment fragments
/// (`experiments/index/NNN.json`). README.md is generated from these, so the
/// fragments are the fresh source on a branch that hasn't regenerated it. A
/// fragment is one row object, or a list of rows for a split experiment.
Map<String, _ExperimentEntry> _readExperimentIndex(
  List<_ValidationError> errors,
) {
  final indexDir = Directory('$_experimentsDir/index');
  if (!indexDir.existsSync()) {
    _signalError(errors, 'Missing ${indexDir.path}/ (experiment index fragments).');
    return const {};
  }

  final entries = <String, _ExperimentEntry>{};
  for (final file in indexDir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    final id = file.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), '');
    Object? decoded;
    try {
      decoded = json.decode(file.readAsStringSync());
    } on FormatException catch (error) {
      _signalError(errors, '${file.path} is not valid JSON: ${error.message}');
      continue;
    }
    final rows = decoded is List ? decoded : [decoded];
    for (final row in rows) {
      if (row is! Map) continue;
      entries[id] = _ExperimentEntry(
        id: id,
        filename: row['file']?.toString() ?? '$id.md',
        status: row['status']?.toString() ?? 'accepted',
      );
    }
  }
  if (entries.isEmpty) {
    _signalError(errors, 'No experiment fragments found in ${indexDir.path}/.');
  }
  return entries;
}

Map<String, List<String>> _discoverExperimentFiles() {
  final dir = Directory(_experimentsDir);
  if (!dir.existsSync()) return const {};

  final files = <String, List<String>>{};
  final filePattern = RegExp(r'^(\d+\w?)-.+\.md$');
  for (final file in dir.listSync().whereType<File>()) {
    final filename = file.uri.pathSegments.last;
    final match = filePattern.firstMatch(filename);
    if (match == null) continue;
    (files[match.group(1)!] ??= []).add(filename);
  }
  return files;
}

void _checkExperimentFilesIndexed(
  Map<String, _ExperimentEntry> experimentIndex,
  Map<String, List<String>> discoveredExperimentFiles,
  int? experimentEntriesRequiredFrom,
  List<_ValidationError> errors,
) {
  if (experimentEntriesRequiredFrom == null) return;

  final indexedFilenames = experimentIndex.values
      .map((entry) => entry.filename)
      .toSet();
  for (final entry in discoveredExperimentFiles.entries) {
    final number = _numericExperimentId(entry.key);
    if (number == null || number < experimentEntriesRequiredFrom) continue;
    for (final filename in entry.value) {
      if (indexedFilenames.contains(filename)) continue;
      _fileError(
        errors,
        '$_experimentsDir/$filename',
        'Experiment file for id ${entry.key} must be listed in $_readmePath '
            'because coverage.experimentEntriesRequiredFrom is '
            '$experimentEntriesRequiredFrom.',
      );
    }
  }
}

int? _numericExperimentId(String id) {
  final match = RegExp(r'^\d+').firstMatch(id);
  return match == null ? null : int.tryParse(match.group(0)!);
}

/// Assembles the signal map from its sources (`experiments/signals/base.json` +
/// `experiments/signals/entries/NNN.json`) and validates that, rather than the
/// committed `signals.json` — which is a generated, bot-owned aggregate that an
/// experiment branch never has to keep fresh. A malformed fragment surfaces
/// here as an assembly failure.
Map<Object?, Object?>? _readSignals(List<_ValidationError> errors) {
  try {
    final data = generate_signals.buildSignalsData(
      signalsSourceDir: Directory('$_experimentsDir/signals'),
    );
    return data.cast<Object?, Object?>();
  } catch (error) {
    _signalError(errors, 'signals sources do not assemble: $error');
    return null;
  }
}

void _checkSignals(
  Map<Object?, Object?> root,
  Map<String, _ExperimentEntry> experimentIndex,
  List<_ValidationError> errors,
) {
  if (root['schemaVersion'] is! int) {
    _signalError(errors, 'schemaVersion must be an integer.');
  }
  _requireString(root, 'purpose', 'root', errors);
  final experimentIds = experimentIndex.keys.toSet();
  final coverage = _map(root['coverage'], 'coverage', errors);
  final experimentEntriesRequiredFrom = coverage == null
      ? null
      : _intField(
          coverage,
          'experimentEntriesRequiredFrom',
          'coverage',
          errors,
        );
  final directionFieldRequiredFrom = coverage == null
      ? null
      : _intField(coverage, 'directionFieldRequiredFrom', 'coverage', errors);
  final discoveredExperimentFiles = _discoverExperimentFiles();
  _checkExperimentFilesIndexed(
    experimentIndex,
    discoveredExperimentFiles,
    experimentEntriesRequiredFrom,
    errors,
  );
  final statusDefinitions = _stringMap(
    root,
    'statusDefinitions',
    'root',
    errors,
    required: true,
  );
  final allowedStatuses = statusDefinitions.keys.toSet();

  final directionIds = <String>{};
  final directions = _list(root, 'directions', 'root', errors, required: true);
  for (var i = 0; i < directions.length; i++) {
    final path = 'directions[$i]';
    final direction = _map(directions[i], path, errors);
    if (direction == null) continue;

    final id = _requireString(direction, 'id', path, errors);
    if (id != null) {
      if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(id)) {
        _signalError(errors, '$path.id must be lowercase kebab-case.');
      }
      if (!directionIds.add(id)) {
        _signalError(errors, 'Duplicate direction id "$id".');
      }
    }

    final status = _requireString(direction, 'status', path, errors);
    if (status != null &&
        allowedStatuses.isNotEmpty &&
        !allowedStatuses.contains(status)) {
      _signalError(
        errors,
        '$path.status "$status" must be one of: '
        '${allowedStatuses.join(', ')}.',
      );
    }

    _requireString(direction, 'currentRead', path, errors);
    _stringList(
      direction,
      'subsystems',
      path,
      errors,
      required: true,
      nonEmpty: true,
    );
    final keyPriors = _stringList(
      direction,
      'keyPriors',
      path,
      errors,
      required: true,
      nonEmpty: true,
    );
    _checkExperimentRefs(keyPriors, experimentIds, '$path.keyPriors', errors);
    if (keyPriors.length > 6) {
      _signalError(
        errors,
        '$path.keyPriors should hold at most 6 entries; archive older priors '
        'instead. Current length: ${keyPriors.length}.',
      );
    }
    final archive = _stringList(direction, 'archive', path, errors);
    _checkExperimentRefs(archive, experimentIds, '$path.archive', errors);
    final keyPriorSet = keyPriors.toSet();
    for (final id in archive) {
      if (keyPriorSet.contains(id)) {
        _signalError(
          errors,
          '$path: experiment "$id" appears in both keyPriors and archive.',
        );
      }
    }
    _stringList(direction, 'interestingIf', path, errors);
    _stringList(direction, 'openQuestions', path, errors);
    _checkOpenCandidates(direction, path, experimentIds, errors);
    _stringList(direction, 'blockedOnMeasurement', path, errors);
    _requireString(direction, 'notesForExperimenters', path, errors);
  }

  final experiments = root['experiments'];
  if (experiments == null) {
    _signalError(errors, 'root.experiments is required.');
    return;
  }
  final experimentMap = _map(experiments, 'experiments', errors);
  if (experimentMap == null) return;

  for (final entry in experimentMap.entries) {
    final expId = entry.key?.toString();
    final path = 'experiments.$expId';
    final experiment = expId == null ? null : experimentIndex[expId];
    if (expId == null || experiment == null) {
      _signalError(
        errors,
        '$path references an experiment not listed in README.md.',
      );
      continue;
    }

    final note = _map(entry.value, path, errors);
    if (note == null) continue;

    final referencedDirections = _stringList(
      note,
      'directions',
      path,
      errors,
      required: true,
      nonEmpty: true,
    );
    for (final direction in referencedDirections) {
      if (!directionIds.contains(direction)) {
        _signalError(
          errors,
          '$path.directions references unknown direction "$direction".',
        );
      }
    }
    final outcomeClass = _requireString(note, 'outcomeClass', path, errors);
    _checkOutcomeConsistency(experiment, outcomeClass, path, errors);
    _stringList(note, 'changedBeliefs', path, errors);
    _stringList(note, 'nextSignals', path, errors);
  }

  _checkFutureCoverage(
    experimentIndex,
    experimentMap,
    directionIds,
    experimentEntriesRequiredFrom,
    directionFieldRequiredFrom,
    errors,
  );
}

Map<Object?, Object?>? _map(
  Object? value,
  String path,
  List<_ValidationError> errors,
) {
  if (value is Map) return value.cast<Object?, Object?>();
  _signalError(errors, '$path must be an object.');
  return null;
}

List<Object?> _list(
  Map<Object?, Object?> map,
  String key,
  String path,
  List<_ValidationError> errors, {
  bool required = false,
}) {
  final value = map[key];
  if (value == null) {
    if (required) _signalError(errors, '$path.$key is required.');
    return const [];
  }
  if (value is List) return value.cast<Object?>();
  _signalError(errors, '$path.$key must be a list.');
  return const [];
}

String? _requireString(
  Map<Object?, Object?> map,
  String key,
  String path,
  List<_ValidationError> errors,
) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) return value;
  _signalError(errors, '$path.$key must be a non-empty string.');
  return null;
}

List<String> _stringList(
  Map<Object?, Object?> map,
  String key,
  String path,
  List<_ValidationError> errors, {
  bool required = false,
  bool nonEmpty = false,
}) {
  final value = map[key];
  if (value == null) {
    if (required) _signalError(errors, '$path.$key is required.');
    return const [];
  }
  if (value is! List) {
    _signalError(errors, '$path.$key must be a list of strings.');
    return const [];
  }

  final result = <String>[];
  for (var i = 0; i < value.length; i++) {
    final item = value[i];
    if (item is String && item.trim().isNotEmpty) {
      result.add(item);
    } else {
      _signalError(errors, '$path.$key[$i] must be a non-empty string.');
    }
  }
  if (nonEmpty && result.isEmpty) {
    _signalError(errors, '$path.$key must not be empty.');
  }
  return result;
}

Map<String, String> _stringMap(
  Map<Object?, Object?> map,
  String key,
  String path,
  List<_ValidationError> errors, {
  bool required = false,
}) {
  final value = map[key];
  if (value == null) {
    if (required) _signalError(errors, '$path.$key is required.');
    return const {};
  }
  if (value is! Map) {
    _signalError(errors, '$path.$key must be an object of strings.');
    return const {};
  }

  final result = <String, String>{};
  for (final entry in value.entries) {
    final entryKey = entry.key;
    final entryValue = entry.value;
    if (entryKey is! String || entryKey.trim().isEmpty) {
      _signalError(errors, '$path.$key contains a non-string or empty key.');
      continue;
    }
    if (entryValue is! String || entryValue.trim().isEmpty) {
      _signalError(errors, '$path.$key.$entryKey must be a non-empty string.');
      continue;
    }
    result[entryKey] = entryValue;
  }
  return result;
}

int? _intField(
  Map<Object?, Object?> map,
  String key,
  String path,
  List<_ValidationError> errors,
) {
  final value = map[key];
  if (value is int) return value;
  _signalError(errors, '$path.$key must be an integer.');
  return null;
}

void _checkOutcomeConsistency(
  _ExperimentEntry experiment,
  String? outcomeClass,
  String path,
  List<_ValidationError> errors,
) {
  if (outcomeClass == null) return;
  final normalized = outcomeClass.toLowerCase();
  if (!_outcomeClassPattern.hasMatch(normalized)) {
    _signalError(
      errors,
      '$path.outcomeClass "$outcomeClass" must match '
      'accepted(_...), rejected(_...), in_review(_...), watch, '
      'benchmark_gap, or deferred.',
    );
  }
  if (experiment.status == 'accepted' && !normalized.startsWith('accepted')) {
    _signalError(
      errors,
      '$path.outcomeClass "$outcomeClass" must start with accepted for an '
      'accepted README entry.',
    );
  }
  if (experiment.status == 'rejected' &&
      (normalized.startsWith('accepted') ||
          normalized.startsWith('in_review'))) {
    _signalError(
      errors,
      '$path.outcomeClass "$outcomeClass" contradicts rejected README status.',
    );
  }
  if (experiment.status == 'in_review' &&
      (normalized.startsWith('accepted') ||
          normalized.startsWith('rejected'))) {
    _signalError(
      errors,
      '$path.outcomeClass "$outcomeClass" contradicts in-review README status.',
    );
  }
}

void _checkFutureCoverage(
  Map<String, _ExperimentEntry> experimentIndex,
  Map<Object?, Object?> experimentSignals,
  Set<String> directionIds,
  int? experimentEntriesRequiredFrom,
  int? directionFieldRequiredFrom,
  List<_ValidationError> errors,
) {
  for (final experiment in experimentIndex.values) {
    final number = experiment.numericId;
    if (number == null) continue;

    final signal = experimentSignals[experiment.id];
    if (experimentEntriesRequiredFrom != null &&
        number >= experimentEntriesRequiredFrom &&
        signal == null) {
      _signalError(
        errors,
        'experiments.${experiment.id} is required because '
        'coverage.experimentEntriesRequiredFrom is '
        '$experimentEntriesRequiredFrom.',
      );
    }

    if (directionFieldRequiredFrom != null &&
        number >= directionFieldRequiredFrom) {
      final docDirections = _readExperimentDirections(experiment, errors);
      if (docDirections.isEmpty) {
        _fileError(
          errors,
          experiment.path,
          'Experiment ${experiment.id} must include a Direction header '
          'such as **Direction:** `direction-id` because '
          'coverage.directionFieldRequiredFrom is '
          '$directionFieldRequiredFrom.',
        );
        continue;
      }
      for (final direction in docDirections) {
        if (!directionIds.contains(direction)) {
          _fileError(
            errors,
            experiment.path,
            'Experiment ${experiment.id} references unknown direction '
            '"$direction".',
          );
        }
      }

      final signalMap = signal is Map ? signal.cast<Object?, Object?>() : null;
      if (signalMap == null) continue;
      final signalDirections = _stringList(
        signalMap,
        'directions',
        'experiments.${experiment.id}',
        errors,
      ).toSet();
      final docDirectionSet = docDirections.toSet();
      if (!_sameSet(signalDirections, docDirectionSet)) {
        _signalError(
          errors,
          'experiments.${experiment.id}.directions must match '
          '${experiment.path} Direction field.',
        );
      }
    }
  }
}

List<String> _readExperimentDirections(
  _ExperimentEntry experiment,
  List<_ValidationError> errors,
) {
  final file = File(experiment.path);
  if (!file.existsSync()) {
    _fileError(errors, experiment.path, 'Missing experiment file.');
    return const [];
  }

  final content = file.readAsStringSync();
  final match = RegExp(
    r'^\*\*Direction:\*\*\s*(.+)$',
    multiLine: true,
  ).firstMatch(content);
  if (match == null) return const [];

  final raw = match.group(1)!.trim();
  final directions = RegExp(r'`([^`]+)`')
      .allMatches(raw)
      .map((m) => m.group(1)!.trim())
      .where((v) => v.isNotEmpty)
      .toList();

  if (directions.isEmpty) {
    _fileError(
      errors,
      experiment.path,
      'Experiment ${experiment.id} Direction field must contain one or more '
      'backticked direction ids.',
    );
  }
  return directions;
}

bool _sameSet(Set<String> left, Set<String> right) {
  if (left.length != right.length) return false;
  return left.containsAll(right);
}

void _checkExperimentRefs(
  List<String> refs,
  Set<String> experimentIds,
  String path,
  List<_ValidationError> errors,
) {
  for (final ref in refs) {
    if (!experimentIds.contains(ref)) {
      _signalError(errors, '$path references unknown experiment "$ref".');
    }
  }
}

final _isoDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

void _checkOpenCandidates(
  Map<Object?, Object?> direction,
  String path,
  Set<String> experimentIds,
  List<_ValidationError> errors,
) {
  final value = direction['openCandidates'];
  if (value == null) return;
  if (value is! List) {
    _signalError(errors, '$path.openCandidates must be a list.');
    return;
  }

  for (var i = 0; i < value.length; i++) {
    final itemPath = '$path.openCandidates[$i]';
    final item = value[i];
    if (item is! Map) {
      _signalError(errors, '$itemPath must be an object.');
      continue;
    }
    final asMap = item.cast<Object?, Object?>();
    _requireString(asMap, 'idea', itemPath, errors);
    final dateStr = _requireString(asMap, 'addedDate', itemPath, errors);
    if (dateStr != null && !_isoDatePattern.hasMatch(dateStr)) {
      _signalError(
        errors,
        '$itemPath.addedDate must be an ISO date string (YYYY-MM-DD).',
      );
    }
    final addedAfter = asMap['addedAfter'];
    if (addedAfter != null) {
      if (addedAfter is! String || addedAfter.trim().isEmpty) {
        _signalError(
          errors,
          '$itemPath.addedAfter must be a non-empty string.',
        );
      } else if (!experimentIds.contains(addedAfter)) {
        _signalError(
          errors,
          '$itemPath.addedAfter references unknown experiment "$addedAfter".',
        );
      }
    }
    final blockedOn = asMap['blockedOn'];
    if (blockedOn != null &&
        (blockedOn is! String || blockedOn.trim().isEmpty)) {
      _signalError(errors, '$itemPath.blockedOn must be a non-empty string.');
    }
  }
}

void _signalError(List<_ValidationError> errors, String message) {
  errors.add(_ValidationError(_signalsPath, message));
}

void _fileError(List<_ValidationError> errors, String file, String message) {
  errors.add(_ValidationError(file, message));
}

class _ExperimentEntry {
  const _ExperimentEntry({
    required this.id,
    required this.filename,
    required this.status,
  });

  final String id;
  final String filename;
  final String status;

  String get path => 'experiments/$filename';

  int? get numericId {
    final match = RegExp(r'^\d+').firstMatch(id);
    return match == null ? null : int.tryParse(match.group(0)!);
  }
}

class _ValidationError {
  const _ValidationError(this.file, this.message);

  final String file;
  final String message;
}
