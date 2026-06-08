import 'dart:io';

Future<Map<String, Object?>> collectBenchmarkEnvironment({
  Map<String, Object?> extra = const {},
}) async {
  final gitSha = await _gitValue(['rev-parse', 'HEAD']);
  final gitBranch = await _gitValue(['rev-parse', '--abbrev-ref', 'HEAD']);
  final gitDirty = await _gitDirty();

  return {
    'cwd': Directory.current.path,
    'hostname': _safeHostname(),
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'dartVersion': Platform.version.split(' ').first,
    'runtime': _detectRuntimeFlavor(),
    'executable': Platform.executable,
    'resolvedExecutable': Platform.resolvedExecutable,
    'script': Platform.script.toString(),
    'processors': Platform.numberOfProcessors,
    'ci': Platform.environment['CI'] == 'true',
    'githubActions': Platform.environment['GITHUB_ACTIONS'] == 'true',
    if (Platform.environment['RUNNER_OS'] != null)
      'githubRunnerOs': Platform.environment['RUNNER_OS'],
    if (Platform.environment['GITHUB_RUN_ID'] != null)
      'githubRunId': Platform.environment['GITHUB_RUN_ID'],
    if (Platform.environment['GITHUB_RUN_ATTEMPT'] != null)
      'githubRunAttempt': Platform.environment['GITHUB_RUN_ATTEMPT'],
    if (Platform.environment['GITHUB_SHA'] != null)
      'githubSha': Platform.environment['GITHUB_SHA'],
    if (Platform.environment['GITHUB_REF'] != null)
      'githubRef': Platform.environment['GITHUB_REF'],
    if (gitSha != null) 'gitSha': gitSha,
    if (gitBranch != null) 'gitBranch': gitBranch,
    if (gitDirty != null) 'gitDirty': gitDirty,
    ...extra,
  };
}

String _detectRuntimeFlavor() {
  final exec = Platform.executable.toLowerCase();
  if (exec.contains('dartaotruntime')) return 'dart-aot';
  if (exec.endsWith('/dart') || exec.endsWith('\\dart.exe')) return 'dart-vm';
  return 'dart-runtime';
}

String? _safeHostname() {
  try {
    return Platform.localHostname;
  } catch (_) {
    return null;
  }
}

Future<String?> _gitValue(List<String> args) async {
  try {
    final result = await Process.run('git', args, runInShell: false);
    if (result.exitCode != 0) return null;
    final value = (result.stdout as String).trim();
    return value.isEmpty ? null : value;
  } catch (_) {
    return null;
  }
}

Future<bool?> _gitDirty() async {
  try {
    final result = await Process.run('git', [
      'status',
      '--porcelain',
    ], runInShell: false);
    if (result.exitCode != 0) return null;
    final value = (result.stdout as String).trim();
    return value.isNotEmpty;
  } catch (_) {
    return null;
  }
}
