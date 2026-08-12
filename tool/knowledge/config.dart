/// Loads `knowledge.yaml` — the project wiring the pin system reads.
///
/// The wiring used to be four `const`s in verify.dart plus a hardcoded root
/// list inside resolvers.dart, while both files' headers told the reader it
/// lived in a `knowledge.yaml` that did not exist. Splitting it out is what
/// makes the portability claim true rather than aspirational: a different repo
/// now edits one YAML file and one resolver file, exactly as documented.
///
/// Missing or malformed config is fatal. A verifier that silently falls back to
/// defaults would check the wrong trees and report a confident pass over prose
/// it never read — the same class of failure as `unknown` reading as success.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

class KnowledgeConfig {
  const KnowledgeConfig({
    required this.docDirs,
    required this.claimEntries,
    required this.history,
    required this.testResults,
    required this.codeRoots,
    required this.minStrongPinsPerChapter,
    required this.groundednessExempt,
  });

  /// Directories whose top-level `.md` files are scanned for pins.
  final List<String> docDirs;

  /// Directory of per-experiment signal fragments backing `claim:` and `was:`.
  final String claimEntries;

  /// Published benchmark history backing `bench:`.
  final String history;

  /// Passing-test names backing `test:`. A CI artifact.
  final String testResults;

  /// Trees `code:` searches for declarations.
  final List<String> codeRoots;

  /// Minimum `test:`/`bench:`/`code:` pins a non-exempt chapter must carry.
  final int minStrongPinsPerChapter;

  /// Chapter basename -> why it is exempt from the floor.
  final Map<String, String> groundednessExempt;

  static const defaultPath = 'tool/knowledge/knowledge.yaml';

  factory KnowledgeConfig.load(Directory root, {String? path}) {
    final file = File('${root.path}/${path ?? defaultPath}');
    if (!file.existsSync()) {
      throw StateError(
        'No knowledge config at ${file.path}. The pin system reads its wiring '
        'from there; without it there is nothing to verify against.',
      );
    }
    final doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) {
      throw StateError('${file.path} must be a YAML mapping.');
    }
    final sources = _require<YamlMap>(doc, 'sources', file.path);
    final grounded = doc['groundedness'];
    return KnowledgeConfig(
      docDirs: _stringList(_require<YamlList>(doc, 'docs', file.path)),
      claimEntries: _requireString(sources, 'claims', '${file.path}.sources'),
      history: _requireString(sources, 'benchmarks', '${file.path}.sources'),
      testResults: _requireString(
        sources,
        'testResults',
        '${file.path}.sources',
      ),
      codeRoots: _stringList(_require<YamlList>(doc, 'codeRoots', file.path)),
      minStrongPinsPerChapter: grounded is YamlMap
          ? _optionalInt(
              grounded,
              'minStrongPinsPerChapter',
              '${file.path}.groundedness',
            )
          : 0,
      groundednessExempt: grounded is YamlMap && grounded['exempt'] is YamlMap
          ? {
              for (final e in (grounded['exempt'] as YamlMap).entries)
                e.key.toString(): e.value.toString(),
            }
          : const {},
    );
  }

  static T _require<T>(YamlMap map, String key, String where) {
    final value = map[key];
    if (value is! T) {
      throw StateError('$where: "$key" is required and must be a $T.');
    }
    return value;
  }

  static String _requireString(YamlMap map, String key, String where) {
    final value = map[key];
    if (value is! String || value.isEmpty) {
      throw StateError('$where: "$key" is required and must be a string.');
    }
    return value;
  }

  static List<String> _stringList(YamlList list) =>
      list.map((e) => e.toString()).toList();

  /// An optional integer, defaulting to 0, that refuses to be anything else.
  ///
  /// A bare `as int?` throws [TypeError] on `"two"` or `2.0`, and the caller
  /// catches only [StateError] — so a one-character config typo came out as an
  /// unhandled cast error and a stack trace, in the class whose whole job is
  /// making configuration failures legible.
  static int _optionalInt(YamlMap map, String key, String where) {
    final value = map[key];
    if (value == null) return 0;
    if (value is! int) {
      throw StateError(
        '$where: "$key" must be an integer, got ${value.runtimeType} '
        '($value).',
      );
    }
    return value;
  }
}
