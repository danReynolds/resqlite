final class BaselineCompatibility {
  const BaselineCompatibility({
    required this.compatible,
    required this.reasons,
  });

  final bool compatible;
  final List<String> reasons;
}

BaselineCompatibility evaluateBaselineCompatibility({
  required Map<String, Object?> current,
  required Map<String, Object?>? baseline,
}) {
  if (baseline == null || baseline.isEmpty) {
    return const BaselineCompatibility(
      compatible: false,
      reasons: ['baseline sidecar is missing environment metadata'],
    );
  }

  final reasons = <String>[];
  _requireSame(reasons, current, baseline, 'benchmarkMode');
  _requireSame(reasons, current, baseline, 'os');
  _requireSame(reasons, current, baseline, 'runtime');
  _requireSameBoolDefaultFalse(reasons, current, baseline, 'ci');
  _requireSameBoolDefaultFalse(reasons, current, baseline, 'githubActions');
  _requireSame(reasons, current, baseline, 'githubRunnerOs');

  final currentCi = _boolValue(current['ci']);
  final baselineCi = _boolValue(baseline['ci']);
  final currentGithubActions = _boolValue(current['githubActions']);
  final baselineGithubActions = _boolValue(baseline['githubActions']);

  if (currentCi == true || baselineCi == true) {
    _requireSameDartMinor(reasons, current, baseline);
  } else if (currentGithubActions == true || baselineGithubActions == true) {
    _requireSameDartMinor(reasons, current, baseline);
  } else {
    _requireSame(reasons, current, baseline, 'hostname');
    _requireSame(reasons, current, baseline, 'processors');
    _requireSame(reasons, current, baseline, 'osVersion');
    _requireSameDartMinor(reasons, current, baseline);
  }

  return BaselineCompatibility(
    compatible: reasons.isEmpty,
    reasons: List.unmodifiable(reasons),
  );
}

void _requireSame(
  List<String> reasons,
  Map<String, Object?> current,
  Map<String, Object?> baseline,
  String field,
) {
  final currentValue = current[field];
  final baselineValue = baseline[field];
  if (currentValue == null && baselineValue == null) return;
  if (currentValue == baselineValue) return;
  reasons.add(
    '$field differs: current `${_display(currentValue)}` vs baseline `${_display(baselineValue)}`',
  );
}

void _requireSameBoolDefaultFalse(
  List<String> reasons,
  Map<String, Object?> current,
  Map<String, Object?> baseline,
  String field,
) {
  final currentValue = _boolValue(current[field]) ?? false;
  final baselineValue = _boolValue(baseline[field]) ?? false;
  if (currentValue == baselineValue) return;
  reasons.add(
    '$field differs: current `$currentValue` vs baseline `$baselineValue`',
  );
}

void _requireSameDartMinor(
  List<String> reasons,
  Map<String, Object?> current,
  Map<String, Object?> baseline,
) {
  final currentVersion = _dartMajorMinor(current['dartVersion']);
  final baselineVersion = _dartMajorMinor(baseline['dartVersion']);
  if (currentVersion == null && baselineVersion == null) return;
  if (currentVersion == baselineVersion) return;
  reasons.add(
    'dartVersion differs: current `${_display(current['dartVersion'])}` vs baseline `${_display(baseline['dartVersion'])}`',
  );
}

String? _dartMajorMinor(Object? value) {
  if (value == null) return null;
  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(value.toString());
  if (match == null) return value.toString();
  return '${match.group(1)}.${match.group(2)}';
}

bool? _boolValue(Object? value) {
  if (value is bool) return value;
  return null;
}

String _display(Object? value) => value?.toString() ?? 'missing';
