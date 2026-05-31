import 'dart:io';

import 'package:path/path.dart' as p;

const pinnedTraceliteRepository = 'https://github.com/danReynolds/tracelite';
const pinnedTraceliteRevision = 'bcb3f3f419a09aa682948595fdb8ab002af637dc';
const pinnedTraceliteTag = 'resqlite-profiling-gate-2026-05-31';

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
  final revisionMatches =
      revision != null && revision == policy.expectedRevision;
  final sourceOk = !policy.requiresPin ||
      (revisionMatches && (dirty != true || policy.allowDirty));

  return {
    'path': traceliteRoot,
    'pinned_repository': pinnedTraceliteRepository,
    'pinned_revision': policy.expectedRevision,
    'pinned_tag': pinnedTraceliteTag,
    'pin_required': policy.requiresPin,
    'allow_dirty': policy.allowDirty,
    ...gitState,
    if (policy.requiresPin) 'revision_matches_pin': revisionMatches,
    'source_ok': sourceOk,
  };
}

Future<Map<String, Object?>> resqliteSourceState(String resqliteRoot) async {
  final root = Directory(resqliteRoot).absolute.path;
  final pubspec = File(p.join(root, 'pubspec.yaml'));
  return {
    'path': root,
    if (pubspec.existsSync()) ...{
      'package_name': _readPubspecScalar(pubspec, 'name'),
      'version': _readPubspecScalar(pubspec, 'version'),
    },
    ...await _gitSourceState(root),
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
  final allowUnpinned = flags.contains('allow-unpinned-tracelite') ||
      Platform.environment['TRACELITE_ALLOW_UNPINNED'] == 'true';
  final allowDirty = flags.contains('allow-dirty-tracelite') ||
      Platform.environment['TRACELITE_ALLOW_DIRTY'] == 'true';
  return TraceliteSourcePolicy(
    expectedRevision: revision ??
        Platform.environment['TRACELITE_REVISION'] ??
        pinnedTraceliteRevision,
    allowUnpinned: allowUnpinned,
    allowDirty: allowDirty,
  );
}
