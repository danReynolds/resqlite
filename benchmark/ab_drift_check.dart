// ignore_for_file: avoid_print
//
// Order-flipped A/B drift discriminator.
//
// Mechanizes the JOURNAL.md lesson "Phase-ordered A/B gates confound code
// deltas with time-correlated drift": when a phase-ordered A/B (the
// tracelite wrapper, or any baseline-then-candidate harness) flags a
// regression, you are supposed to (a) check the flagged phase's within-run
// CV against the clean phase, and (b) re-run with the collection order
// flipped and see whether the flag reproduces. Runners have been doing both
// steps by hand in every recent `benchmark/profile/results/*-aggregate.md`
// (exp 159, 167, 171, 173). This tool applies that exact reasoning by rule
// so the call is reproducible and not eyeballed.
//
// It changes no runtime code and is not part of the release suite — it is a
// methodology guardrail, the same class as exp 161 (release coverage) and
// exp 169 (insight guard).
//
// Input is a small JSON file describing one or more flagged scenarios, each
// with two order-flipped passes of per-run values:
//
//   {
//     "scenarios": [
//       {
//         "label": "high-cardinality-fanout",
//         "pass1": { "baseline": [..ms..], "candidate": [..ms..] },
//         "pass2": { "baseline": [..ms..], "candidate": [..ms..] }
//       }
//     ]
//   }
//
// pass1 is the standard order (baseline phase first) that produced the
// flag; pass2 is the order-flipped confirmation (candidate phase first).
// Per-run units are arbitrary but must be consistent within a scenario.
//
// Usage:
//   dart run benchmark/ab_drift_check.dart --input=flagged.json
//   dart run benchmark/ab_drift_check.dart --input=flagged.json --markdown
//   dart run benchmark/ab_drift_check.dart --self-check   # built-in demo
//
// Exit code is 0 unless --fail-on-reproduced is passed and at least one
// scenario classifies as `reproduced` (a real regression), which lets the
// tool gate a CI or local check.

import 'dart:convert';
import 'dart:io';

import 'shared/stats.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.showHelp) {
    _usage(exitCode: 0);
  }

  final List<_ScenarioInput> scenarios;
  if (options.selfCheck) {
    scenarios = _selfCheckScenarios();
  } else if (options.inputPath != null) {
    scenarios = _readScenarios(options.inputPath!);
  } else {
    stderr.writeln('error: pass --input=<file>.json or --self-check');
    _usage();
  }

  final classifications = <_ScenarioInput, DriftClassification>{};
  for (final scenario in scenarios) {
    classifications[scenario] = classifyDriftFlag(
      scenario.pass1,
      scenario.pass2,
      thresholds: options.thresholds,
    );
  }

  if (options.markdown) {
    _printMarkdown(classifications);
  } else {
    _printText(classifications);
  }

  final reproduced = classifications.values
      .where((c) => c.verdict == DriftVerdict.reproduced)
      .length;
  if (options.failOnReproduced && reproduced > 0) {
    stderr.writeln(
      '\n$reproduced scenario(s) classified as reproduced (real effect); '
      'failing as requested by --fail-on-reproduced.',
    );
    exitCode = 1;
  }
}

List<_ScenarioInput> _readScenarios(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('error: input file not found: $path');
    exit(66);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('error: $path is not valid JSON: ${e.message}');
    exit(65);
  }
  if (decoded is! Map || decoded['scenarios'] is! List) {
    stderr.writeln('error: expected {"scenarios": [...]} in $path');
    exit(65);
  }
  final out = <_ScenarioInput>[];
  for (final raw in decoded['scenarios'] as List) {
    out.add(_ScenarioInput.fromJson(raw as Map<String, Object?>));
  }
  if (out.isEmpty) {
    stderr.writeln('error: no scenarios in $path');
    exit(65);
  }
  return out;
}

void _printText(Map<_ScenarioInput, DriftClassification> classifications) {
  print('# Order-flipped A/B drift check');
  print('');
  print(
    'Reads a flagged phase-ordered A/B and decides, by the JOURNAL rule, '
    'whether the flag is a real code effect or time-correlated drift.',
  );
  print('');
  classifications.forEach((scenario, c) {
    print('## ${scenario.label}');
    print('  verdict:        ${_verdictLabel(c.verdict)}');
    print(
      '  pass 1 delta:   ${c.pass1DeltaPct.toStringAsFixed(1)}% '
      '(flagged CV ${scenario.pass1.flaggedSideCvPct.toStringAsFixed(1)}%, '
      'clean CV ${scenario.pass1.cleanSideCvPct.toStringAsFixed(1)}%)',
    );
    print(
      '  pass 2 delta:   ${c.pass2DeltaPct.toStringAsFixed(1)}% '
      '(flagged CV ${scenario.pass2.flaggedSideCvPct.toStringAsFixed(1)}%, '
      'clean CV ${scenario.pass2.cleanSideCvPct.toStringAsFixed(1)}%)',
    );
    print('  worst flagged CV: ${c.worstFlaggedCvPct.toStringAsFixed(1)}%');
    print('  reason:         ${c.reason}');
    print('');
  });
}

void _printMarkdown(Map<_ScenarioInput, DriftClassification> classifications) {
  print('### Order-flipped A/B drift check');
  print('');
  print(
    '| scenario | verdict | pass 1 Δ | pass 2 Δ | worst flagged CV | reason |',
  );
  print('|---|---|---:|---:|---:|---|');
  classifications.forEach((scenario, c) {
    print(
      '| ${scenario.label} '
      '| ${_verdictLabel(c.verdict)} '
      '| ${c.pass1DeltaPct.toStringAsFixed(1)}% '
      '| ${c.pass2DeltaPct.toStringAsFixed(1)}% '
      '| ${c.worstFlaggedCvPct.toStringAsFixed(1)}% '
      '| ${c.reason} |',
    );
  });
  print('');
}

String _verdictLabel(DriftVerdict v) => switch (v) {
  DriftVerdict.reproduced => 'REPRODUCED (real effect)',
  DriftVerdict.driftSuspected => 'drift-suspected',
  DriftVerdict.inconclusive => 'inconclusive / neutral',
};

/// Reproduces the two canonical recorded cases from the aggregates so
/// `--self-check` demonstrates both verdict directions without a fixture
/// file. Numbers approximate exp 159 (pass-1 flag dissolved by the flip)
/// and a synthetic reproduced case.
List<_ScenarioInput> _selfCheckScenarios() => [
  // exp 159 high-cardinality-fanout: pass 1 flagged +19% with a noisy
  // candidate phase (CV ~0.30), pass 2 order-flipped neutral (CV ~0.02).
  _ScenarioInput(
    label: 'exp159-high-card-fanout (drift)',
    pass1: AbPass(
      baseline: [100, 101, 99, 100, 102],
      candidate: [119, 165, 88, 140, 95],
    ),
    pass2: AbPass(
      baseline: [100, 101, 99, 100, 102],
      candidate: [101, 102, 100, 101, 100],
    ),
  ),
  // A synthetic real regression: same-direction +12% in both order-flipped
  // passes, comparable low CVs on every side.
  _ScenarioInput(
    label: 'synthetic-real-regression (reproduced)',
    pass1: AbPass(
      baseline: [100, 101, 99, 100, 102],
      candidate: [112, 113, 111, 112, 113],
    ),
    pass2: AbPass(
      baseline: [100, 99, 101, 100, 100],
      candidate: [113, 112, 112, 111, 113],
    ),
  ),
];

final class _ScenarioInput {
  _ScenarioInput({
    required this.label,
    required this.pass1,
    required this.pass2,
  });

  factory _ScenarioInput.fromJson(Map<String, Object?> json) {
    final label = (json['label'] as String?) ?? 'scenario';
    final pass1 = json['pass1'];
    final pass2 = json['pass2'];
    if (pass1 is! Map || pass2 is! Map) {
      stderr.writeln('error: scenario "$label" needs pass1 and pass2 objects');
      exit(65);
    }
    return _ScenarioInput(
      label: label,
      pass1: _passFromJson(label, 'pass1', pass1.cast<String, Object?>()),
      pass2: _passFromJson(label, 'pass2', pass2.cast<String, Object?>()),
    );
  }

  final String label;
  final AbPass pass1;
  final AbPass pass2;
}

AbPass _passFromJson(String label, String which, Map<String, Object?> json) {
  return AbPass(
    label: '$label/$which',
    baseline: _numList(label, '$which.baseline', json['baseline']),
    candidate: _numList(label, '$which.candidate', json['candidate']),
  );
}

List<double> _numList(String label, String field, Object? raw) {
  if (raw is! List) {
    stderr.writeln('error: $label.$field must be a JSON array of numbers');
    exit(65);
  }
  return [
    for (final v in raw)
      if (v is num)
        v.toDouble()
      else
        () {
          stderr.writeln('error: $label.$field contains a non-number: $v');
          exit(65);
        }(),
  ];
}

final class _Options {
  const _Options({
    required this.inputPath,
    required this.markdown,
    required this.selfCheck,
    required this.failOnReproduced,
    required this.thresholds,
    required this.showHelp,
  });

  final String? inputPath;
  final bool markdown;
  final bool selfCheck;
  final bool failOnReproduced;
  final DriftFlagThresholds thresholds;
  final bool showHelp;

  static _Options parse(List<String> args) {
    String? input;
    var markdown = false;
    var selfCheck = false;
    var failOnReproduced = false;
    var showHelp = false;
    var cvAsymmetry = 4.0;
    var cleanCv = 8.0;
    var floor = 3.0;

    for (final arg in args) {
      if (arg == '--help' || arg == '-h') {
        showHelp = true;
      } else if (arg == '--markdown') {
        markdown = true;
      } else if (arg == '--self-check') {
        selfCheck = true;
      } else if (arg == '--fail-on-reproduced') {
        failOnReproduced = true;
      } else if (arg.startsWith('--input=')) {
        input = arg.substring('--input='.length);
      } else if (arg.startsWith('--cv-asymmetry-ratio=')) {
        cvAsymmetry = _parseDouble(arg, cvAsymmetry);
      } else if (arg.startsWith('--clean-cv-pct=')) {
        cleanCv = _parseDouble(arg, cleanCv);
      } else if (arg.startsWith('--effect-floor-pct=')) {
        floor = _parseDouble(arg, floor);
      } else {
        stderr.writeln('error: unknown argument: $arg');
        _usage();
      }
    }

    return _Options(
      inputPath: input,
      markdown: markdown,
      selfCheck: selfCheck,
      failOnReproduced: failOnReproduced,
      thresholds: DriftFlagThresholds(
        cvAsymmetryRatio: cvAsymmetry,
        cleanCvPct: cleanCv,
        effectFloorPct: floor,
      ),
      showHelp: showHelp,
    );
  }
}

double _parseDouble(String arg, double fallback) {
  final value = double.tryParse(arg.substring(arg.indexOf('=') + 1));
  if (value == null) {
    stderr.writeln('error: $arg is not a number');
    exit(64);
  }
  return value;
}

Never _usage({int exitCode = 64}) {
  final sink = exitCode == 0 ? stdout : stderr;
  sink.writeln('''
Order-flipped A/B drift discriminator.

Decides whether a phase-ordered A/B regression flag is a real code effect
or time-correlated drift, by the JOURNAL.md order-flip + CV-asymmetry rule.

Usage:
  dart run benchmark/ab_drift_check.dart --input=<file>.json [--markdown]
  dart run benchmark/ab_drift_check.dart --self-check [--markdown]

Options:
  --input=PATH              JSON file: {"scenarios":[{label,pass1,pass2}]}
                            where pass1/pass2 each have baseline[] and
                            candidate[] per-run values. pass1 is the
                            standard order that flagged; pass2 is the
                            order-flipped confirmation.
  --self-check              Run on built-in exp-159-shaped demo scenarios.
  --markdown                Emit a markdown table instead of plain text.
  --fail-on-reproduced      Exit 1 if any scenario classifies as reproduced.
  --cv-asymmetry-ratio=N    Flagged/clean CV ratio that condemns a pass (4.0).
  --clean-cv-pct=N          CV at/below which a flagged side is "clean" (8.0).
  --effect-floor-pct=N      Median deltas below this are "no effect" (3.0).
  -h, --help                Show this help.
''');
  exit(exitCode);
}
