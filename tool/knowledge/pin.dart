/// Portable core of the knowledge-pin system: the pin syntax, the resolver
/// contract, and the verdicts a resolver can return.
///
/// The idea in one line: **a documented assertion should name the thing that
/// makes it true, and that binding should be machine-checkable.**
///
/// Documentation prose carries inline pins:
///
///     ...routes on mutable slot count ([[code:sacrificeSlotThreshold=32768]])
///     ...a stream always emits ([[test:test/stream_test.dart#always emits]])
///     ...large byte reads cost ([[bench:Large payload ~ 0.323 ms +-15%]])
///     ...send cost tracks slot count ([[claim:245.1]])
///
/// Each namespace is resolved by a [PinResolver] against a different source of
/// truth, and each answers a different question:
///
///   test   — is the statement *true right now*?      (strongest: CI proves it)
///   bench  — is the number *current*?                (live metric + tolerance)
///   code   — is the mechanism *unchanged*?           (value or normalized body)
///   claim  — is the belief *not superseded*?         (the experiment graph)
///
/// Nothing here knows about any particular project: resolvers are registered by
/// namespace, and the paths/datasets they read come from `knowledge.yaml`. To
/// port this to another codebase, keep this file and the verifier, and write
/// resolvers for whatever that project treats as ground truth.
library;

/// Where a pin was found, for reporting and for `--fix` rewrites.
class PinSite {
  PinSite(this.file, this.line, this.raw);

  final String file;
  final int line;

  /// The full `[[...]]` text, so `--fix` can replace it verbatim.
  final String raw;

  @override
  String toString() => '$file:$line';
}

/// A parsed pin: a namespace, a target within it, and an optional expectation
/// (a value, hash, or tolerance) that the resolver checks against reality.
class Pin {
  Pin({
    required this.namespace,
    required this.target,
    required this.site,
    this.expected,
    this.tolerance,
  });

  final String namespace;
  final String target;

  /// The pinned expectation, if any: `32768`, a body hash, a metric value.
  /// A pin without one is a pure reference — it only breaks if the target
  /// disappears.
  final String? expected;

  /// Fractional tolerance for numeric expectations (0.15 == +-15%). Benchmarks
  /// are noisy; an exact match would flag every run.
  final double? tolerance;

  final PinSite site;

  /// The verbatim `[[...]]` text, for reporting and for `--fix` rewrites.
  String get raw => site.raw;

  @override
  String toString() => '[[$namespace:$target]] at $site';
}

enum PinStatus {
  /// The expectation matches reality. Nothing to do.
  current,

  /// The target exists but has moved away from the pinned expectation — a
  /// constant changed, a metric drifted, a body was edited. The prose that
  /// depends on it needs a human read.
  drifted,

  /// The target no longer exists, or is no longer a valid source of truth (a
  /// deleted symbol, a removed test, a superseded claim). Always an error.
  broken,

  /// The resolver could not check this pin (dataset absent, test never run).
  /// Reported, never fatal — an unavailable checker must not read as a pass.
  unknown,
}

class PinResult {
  PinResult(this.pin, this.status, this.detail, {this.actual});

  final Pin pin;
  final PinStatus status;
  final String detail;

  /// Reality's current value, used by `--fix` to rewrite the expectation.
  final String? actual;

  bool get isFailure =>
      status == PinStatus.drifted || status == PinStatus.broken;
}

/// Resolves one namespace against its source of truth.
///
/// Implementations are the only project-specific part of the system.
abstract class PinResolver {
  /// The namespace this resolver claims, e.g. `code`.
  String get namespace;

  /// Human-readable description of what a pin in this namespace proves —
  /// surfaced in the groundedness report.
  String get proves;

  /// How strongly a passing pin supports a statement, 0-100. Used to rank
  /// evidence: a green test proves a statement is true; an unchanged code hash
  /// only proves nobody edited it.
  int get strength;

  Future<PinResult> resolve(Pin pin);
}

/// Finds every `[[namespace:target]]` in a document.
///
/// Grammar (deliberately small, so it stays readable inside prose):
///
///     [[ns:target]]                  reference only
///     [[ns:target=value]]            pinned to an exact value
///     [[ns:target@hash]]             pinned to a content hash
///     [[ns:target~value+-tol%]]      pinned to a value within a tolerance
///     [[246.1]]                      bare claim id, equivalent to claim:246.1
///
/// The bare form exists because claim citations came first and read well
/// inline; it is sugar for the `claim` namespace, not a fifth kind of pin.
/// Non-greedy to the first `]]` rather than to the first `]`: benchmark metric
/// names contain brackets (`resqlite select() [main]`), and stopping at a lone
/// `]` silently truncated the pin into something that never resolved. Same
/// class of collision as `~` inside metric names.
final _pinPattern = RegExp(r'\[\[(?:([a-z]+):)?(.+?)\]\]');

List<Pin> parsePins(String path, String content) {
  final pins = <Pin>[];
  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    for (final m in _pinPattern.allMatches(lines[i])) {
      final namespace = m.group(1) ?? 'claim';
      var body = m.group(2)!.trim();
      final site = PinSite(path, i + 1, m.group(0)!);

      String? expected;
      double? tolerance;

      // Tolerance form: `target ~ 0.323 +-15%`
      // Greedy on the target: metric names may themselves contain `~` (e.g.
      // "Large payload (~650KB)"), so the *last* `~` is the separator.
      final tol = RegExp(
        r'^(.*)\s*~\s*([\d.]+)\s*\+-\s*([\d.]+)%$',
      ).firstMatch(body);
      if (tol != null) {
        body = tol.group(1)!.trim();
        expected = tol.group(2)!.trim();
        tolerance = double.parse(tol.group(3)!) / 100.0;
      } else {
        // Hash form: `target@a3f2` — the `@` must be last to allow `@` in names.
        final at = body.lastIndexOf('@');
        final eq = body.indexOf('=');
        if (at > 0 && (eq < 0 || at > eq)) {
          expected = body.substring(at + 1).trim();
          body = body.substring(0, at).trim();
        } else if (eq > 0) {
          expected = body.substring(eq + 1).trim();
          body = body.substring(0, eq).trim();
        }
      }
      pins.add(
        Pin(
          namespace: namespace,
          target: body,
          expected: expected,
          tolerance: tolerance,
          site: site,
        ),
      );
    }
  }
  return pins;
}

/// Short, stable content hash. Truncated because it lives in prose and a human
/// has to look at it; collisions are not a threat model here — the hash exists
/// to detect *drift*, and any change to the source changes the digest.
String contentHash(String s) {
  // FNV-1a 64, then base36-truncated. Chosen over a crypto hash to avoid a
  // dependency and because this is a change detector, not a security boundary.
  var h = 0xcbf29ce484222325;
  for (final unit in s.codeUnits) {
    h ^= unit;
    h = h * 0x100000001b3; // wraps at 64 bits, which is the intent
  }
  // Fold to 63 bits before rendering. Dart ints are signed, so roughly half of
  // all digests are negative and render with a leading '-' — which reads as
  // damage inline and spends one of the four characters this returns on a sign.
  return (h & 0x7FFFFFFFFFFFFFFF)
      .toRadixString(36)
      .padLeft(4, '0')
      .substring(0, 4);
}

/// The brace-balanced `{ … }` block following the first match of [anchor].
///
/// Shared by every resolver that needs "the body of this thing" — a function
/// declaration, or the closure a test case is written inside. A brace walk
/// rather than a parse, deliberately: it has to work for whatever language a
/// project points the pin system at, and the result is only ever fed to a
/// change detector.
String? braceBlockAfter(String source, Pattern anchor) {
  final matches = anchor.allMatches(source);
  if (matches.isEmpty) return null;
  final open = source.indexOf('{', matches.first.end);
  if (open < 0) return null;
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') {
      depth++;
    } else if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  return null;
}

/// Strips comments and collapses whitespace so cosmetic edits — reflowing,
/// renaming a comment, adding a blank line — do not read as semantic drift.
///
/// Deliberately line-based rather than a real parse: this must work for any
/// language a project points it at, and over-normalizing risks hiding a real
/// change. Line comments only; block comments are left alone because their
/// delimiters vary too much to strip safely without a parser.
String normalizeSource(String source, {String lineComment = '//'}) {
  final out = StringBuffer();
  for (final line in source.split('\n')) {
    final idx = line.indexOf(lineComment);
    final code = idx >= 0 ? line.substring(0, idx) : line;
    final trimmed = code.trim();
    if (trimmed.isEmpty) continue;
    out.write(trimmed.replaceAll(RegExp(r'\s+'), ' '));
    out.write('\n');
  }
  return out.toString();
}
