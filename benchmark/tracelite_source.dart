import 'dart:io';

import 'package:path/path.dart' as p;

const pinnedTraceliteRepository = 'https://github.com/danReynolds/tracelite';
const pinnedTraceliteRevision = 'b92ec4fa8410b074f77bea840c2fa53cfdf759b4';
const pinnedTraceliteTag = 'resqlite-profiling-gate-2026-06-04-r12';

final class TraceliteSourcePolicy {
  const TraceliteSourcePolicy({
    required this.expectedRevision,
    required this.allowUnpinned,
    required this.allowDirty,
  });

  final String expectedRevision;
  final bool allowUnpinned;
  final bool allowDirty;

  bool get requiresPin => !allowUnpinned && expectedRevision.isNotEmpty;
}

Future<Map<String, Object?>> traceliteSourceState(
  String traceliteRoot, {
  required TraceliteSourcePolicy policy,
}) async {
  final gitState = await _gitSourceState(traceliteRoot);
  final revision = gitState['revision'] as String?;
  final dirty = gitState['dirty'] as bool?;
  final remote = gitState['remote'] as String?;
  final normalizedRemote = _normalizeGitRemote(remote);
  final normalizedPinnedRepository = _normalizeGitRemote(
    pinnedTraceliteRepository,
  );
  final repositoryMatches =
      normalizedRemote != null &&
      normalizedRemote == normalizedPinnedRepository;
  final revisionMatches =
      revision != null && revision == policy.expectedRevision;
  final sourceOk =
      !policy.requiresPin ||
      (revisionMatches &&
          (remote == null || repositoryMatches) &&
          (dirty != true || policy.allowDirty));

  return {
    'path': traceliteRoot,
    'pinned_repository': pinnedTraceliteRepository,
    'pinned_revision': policy.expectedRevision,
    'pinned_tag': pinnedTraceliteTag,
    'pin_required': policy.requiresPin,
    'allow_dirty': policy.allowDirty,
    ...gitState,
    if (normalizedRemote != null) 'remote_normalized': normalizedRemote,
    if (policy.requiresPin && remote != null)
      'repository_matches_pin': repositoryMatches,
    if (policy.requiresPin) 'revision_matches_pin': revisionMatches,
    'source_ok': sourceOk,
  };
}

Future<Map<String, Object?>> resqliteSourceState(
  String resqliteRoot, {
  Map<String, String>? environment,
}) async {
  final root = Directory(resqliteRoot).absolute.path;
  final pubspec = File(p.join(root, 'pubspec.yaml'));
  final gitState = await _gitSourceState(root);
  final githubActions = _githubActionsSourceState(
    environment ?? Platform.environment,
    checkoutRevision: gitState['revision'] as String?,
  );
  return {
    'path': root,
    if (pubspec.existsSync()) ...{
      'package_name': _readPubspecScalar(pubspec, 'name'),
      'version': _readPubspecScalar(pubspec, 'version'),
    },
    ...gitState,
    if (githubActions != null && githubActions.isNotEmpty)
      'github_actions': githubActions,
  };
}

Future<Map<String, Object?>> _gitSourceState(String root) async {
  Future<String?> git(List<String> args) async {
    final result = await Process.run('git', ['-C', root, ...args]);
    if (result.exitCode != 0) return null;
    return result.stdout.toString().trim();
  }

  final revision = await git(['rev-parse', 'HEAD']);
  final branch = await git(['rev-parse', '--abbrev-ref', 'HEAD']);
  final status = await git(['status', '--porcelain']);
  final remote = await git(['config', '--get', 'remote.origin.url']);
  final tagsText = await git(['tag', '--points-at', 'HEAD']);
  final tags = tagsText == null || tagsText.isEmpty
      ? <String>[]
      : tagsText
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList();
  final dirty = status == null ? null : status.isNotEmpty;

  return {
    'git_available': revision != null,
    if (remote != null) 'remote': remote,
    if (revision != null) 'revision': revision,
    if (branch != null) 'branch': branch,
    if (tags.isNotEmpty) 'tags': tags,
    if (dirty != null) 'dirty': dirty,
  };
}

Map<String, Object?>? _githubActionsSourceState(
  Map<String, String> environment, {
  required String? checkoutRevision,
}) {
  final isGitHubActions =
      environment['GITHUB_ACTIONS'] == 'true' ||
      environment.containsKey('GITHUB_SHA');
  if (!isGitHubActions) return null;

  String? value(String key) {
    final raw = environment[key]?.trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  final githubSha = value('GITHUB_SHA');
  final headSha = value('RESQLITE_SOURCE_HEAD_SHA');
  final baseSha = value('RESQLITE_SOURCE_BASE_SHA');
  return {
    'event_name': value('GITHUB_EVENT_NAME'),
    'repository': value('GITHUB_REPOSITORY'),
    'workflow': value('GITHUB_WORKFLOW'),
    'run_id': value('GITHUB_RUN_ID'),
    'run_attempt': value('GITHUB_RUN_ATTEMPT'),
    'ref': value('GITHUB_REF'),
    'ref_name': value('GITHUB_REF_NAME'),
    'head_ref': value('GITHUB_HEAD_REF'),
    'base_ref': value('GITHUB_BASE_REF'),
    'checkout_sha': githubSha,
    'head_sha': headSha,
    'base_sha': baseSha,
    if (checkoutRevision != null && githubSha != null)
      'checkout_matches_github_sha': checkoutRevision == githubSha,
    if (checkoutRevision != null && headSha != null)
      'checkout_matches_head_sha': checkoutRevision == headSha,
  }..removeWhere((_, value) => value == null);
}

String? _readPubspecScalar(File pubspec, String key) {
  final prefix = '$key:';
  for (final line in pubspec.readAsLinesSync()) {
    final trimmed = line.trim();
    if (!trimmed.startsWith(prefix)) continue;
    return trimmed.substring(prefix.length).trim();
  }
  return null;
}

void printTraceliteSource(Map<String, Object?> source) {
  if (source['pin_required'] == true) {
    print('tracelite_pinned_repository: ${source['pinned_repository']}');
    print('tracelite_pinned_revision: ${source['pinned_revision']}');
    print('tracelite_pinned_tag: ${source['pinned_tag']}');
  } else {
    print('tracelite_pin: disabled');
  }

  if (source['git_available'] != true) {
    print('tracelite_git: unavailable');
    return;
  }
  print('tracelite_remote: ${source['remote']}');
  if (source['remote_normalized'] != null) {
    print('tracelite_remote_normalized: ${source['remote_normalized']}');
  }
  if (source['repository_matches_pin'] != null) {
    print(
      'tracelite_repository_matches_pin: '
      '${source['repository_matches_pin']}',
    );
  }
  print('tracelite_revision: ${source['revision']}');
  print('tracelite_branch: ${source['branch']}');
  print('tracelite_dirty: ${source['dirty']}');
  print('tracelite_source_ok: ${source['source_ok']}');
}

void printResqliteSource(Map<String, Object?> source) {
  print('resqlite_root: ${source['path']}');
  if (source['package_name'] != null) {
    print('resqlite_package: ${source['package_name']}');
  }
  if (source['version'] != null) {
    print('resqlite_version: ${source['version']}');
  }
  if (source['git_available'] != true) {
    print('resqlite_git: unavailable');
    return;
  }
  print('resqlite_remote: ${source['remote']}');
  print('resqlite_revision: ${source['revision']}');
  print('resqlite_branch: ${source['branch']}');
  print('resqlite_dirty: ${source['dirty']}');
  final githubActions = source['github_actions'];
  if (githubActions is Map<String, Object?>) {
    print('resqlite_github_event: ${githubActions['event_name']}');
    print('resqlite_github_checkout_sha: ${githubActions['checkout_sha']}');
    if (githubActions['head_sha'] != null) {
      print('resqlite_github_head_sha: ${githubActions['head_sha']}');
    }
    if (githubActions['base_sha'] != null) {
      print('resqlite_github_base_sha: ${githubActions['base_sha']}');
    }
    if (githubActions['checkout_matches_head_sha'] != null) {
      print(
        'resqlite_github_checkout_matches_head_sha: '
        '${githubActions['checkout_matches_head_sha']}',
      );
    }
  }
}

void validateTraceliteSource(Map<String, Object?> source) {
  if (source['pin_required'] != true) return;

  if (source['git_available'] != true) {
    stderr.writeln(
      'tracelite source pin cannot be verified because the checkout is not a '
      'git repository. Use a checkout of $pinnedTraceliteRepository at '
      '${source['pinned_revision']}, or pass --allow-unpinned-tracelite for '
      'local development only.',
    );
    exit(64);
  }

  if (source['revision_matches_pin'] != true) {
    stderr.writeln(
      'tracelite checkout is not at the pinned production revision.',
    );
    stderr.writeln('expected: ${source['pinned_revision']}');
    stderr.writeln('actual:   ${source['revision']}');
    stderr.writeln(
      'Use $pinnedTraceliteRepository at tag $pinnedTraceliteTag, or pass '
      '--allow-unpinned-tracelite for local development only.',
    );
    exit(64);
  }

  if (source['repository_matches_pin'] == false) {
    stderr.writeln(
      'tracelite checkout remote does not match the pinned production '
      'repository.',
    );
    stderr.writeln('expected: ${source['pinned_repository']}');
    stderr.writeln('actual:   ${source['remote']}');
    stderr.writeln(
      'Use $pinnedTraceliteRepository at tag $pinnedTraceliteTag, or pass '
      '--allow-unpinned-tracelite for local development only.',
    );
    exit(64);
  }

  if (source['dirty'] == true && source['allow_dirty'] != true) {
    stderr.writeln(
      'tracelite checkout is dirty at the pinned revision. Commit or stash '
      'local changes, or pass --allow-dirty-tracelite for local experiments.',
    );
    exit(64);
  }
}

TraceliteSourcePolicy traceliteSourcePolicyFromOptions({
  required String? revision,
  required Set<String> flags,
}) {
  final allowUnpinned =
      flags.contains('allow-unpinned-tracelite') ||
      Platform.environment['TRACELITE_ALLOW_UNPINNED'] == 'true';
  final allowDirty =
      flags.contains('allow-dirty-tracelite') ||
      Platform.environment['TRACELITE_ALLOW_DIRTY'] == 'true';
  return TraceliteSourcePolicy(
    expectedRevision:
        revision ??
        Platform.environment['TRACELITE_REVISION'] ??
        pinnedTraceliteRevision,
    allowUnpinned: allowUnpinned,
    allowDirty: allowDirty,
  );
}

String? _normalizeGitRemote(String? remote) {
  if (remote == null) return null;
  var value = remote.trim();
  if (value.isEmpty) return null;

  final sshMatch = RegExp(
    r'^git@github\.com:([^/]+)/(.+?)(?:\.git)?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (sshMatch != null) {
    value = 'https://github.com/${sshMatch.group(1)}/${sshMatch.group(2)}';
  }

  final sshUrlMatch = RegExp(
    r'^ssh://git@github\.com/([^/]+)/(.+?)(?:\.git)?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (sshUrlMatch != null) {
    value =
        'https://github.com/${sshUrlMatch.group(1)}/${sshUrlMatch.group(2)}';
  }

  value = value.replaceFirst(RegExp(r'\.git$'), '');
  value = value.replaceFirst(RegExp(r'/+$'), '');
  if (value.toLowerCase().startsWith('https://github.com/')) {
    final suffix = value.substring('https://github.com/'.length);
    return 'https://github.com/${suffix.toLowerCase()}';
  }
  return value;
}
