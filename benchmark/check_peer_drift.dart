// ignore_for_file: avoid_print
/// Measures movement in the *peers* — the control side of every headline number.
///
///   dart run benchmark/check_peer_drift.dart              # newest vs previous
///   dart run benchmark/check_peer_drift.dart --since=2026-04-06
///   dart run benchmark/check_peer_drift.dart --history    # every step, ranked
///   dart run benchmark/check_peer_drift.dart --fail       # non-zero on a shift
///
/// Every release run measures resqlite against sqlite3, sqlite_async and drift
/// on identical lanes. The peers are the experiment's control: their numbers
/// should move only when the host, SDK, or peer version moves, so movement in
/// them is movement in the measuring apparatus rather than in resqlite.
///
/// Nothing was watching them. Each run printed the peers into its markdown
/// table and then dropped them — `metrics` in both the sidecar artifact and
/// `history.json` held zero non-resqlite lanes — so a resqlite delta read
/// across two runs silently carried whatever the environment did in between.
///
/// The motivating case: on `Select -> Maps / 1000 rows`, resqlite went 0.51 ms
/// in `2026-04-06T22-05-35-baseline-before-authorizer-hooks.md` to 0.320 ms in
/// `2026-08-09T20-36-47-exp266-headline-refresh.md`, which reads as a 37% win.
/// On the same lane in those same two files, `sqlite3 select()` went 0.74 ms to
/// 1.23 ms — 66% *slower* on work that did not change.
///
/// Run this tool over that window, though, and the verdict is that the
/// apparatus held: median peer movement under 1% with agreement near half. Both
/// readings are true and the difference between them is the point. That lane
/// moved 66% because single peer lanes on this host are extremely noisy across
/// months, not because the environment shifted under it. So the sound
/// conclusion is narrower than "the trend is confounded" and more useful: a
/// *single-lane* cross-time comparison is not evidence of anything here, while
/// the suite as a whole is stable enough to trend. This tool exists to tell
/// those two situations apart, because reading either one off the runs by eye
/// gets it wrong.
///
/// ## Why the median, and not the lanes
///
/// The obvious check — flag any peer lane that moved more than X% — does not
/// work here, and finding that out is most of what this tool knows. At a 15%
/// per-lane threshold it fired on 140 of 143 run-to-run steps. Excluding lanes
/// too small to time reliably only brought it to 131. Peer lanes on this host
/// simply are that noisy between adjacent runs, so "some lane moved" carries no
/// information at all.
///
/// A shift in the apparatus has a signature that noise does not: it moves
/// *many* lanes in the *same direction*. So the statistic is the median of the
/// per-lane deltas — robust to the handful of wild lanes that dominate a mean —
/// paired with the share of lanes agreeing with its sign. A large median with
/// high agreement is the host, the SDK, or a peer bump. A near-zero median with
/// agreement near half is ordinary noise, however violently individual lanes
/// swung. Same discipline the suite already applies with MAD and MDE, one level
/// up.
library;

import 'dart:io';

import 'shared/parse_results.dart';

/// Median peer movement above this is treated as the apparatus having moved.
///
/// Lower than a per-lane threshold would be, because a median over dozens of
/// lanes is a far tighter statistic than any one of them.
const _defaultThreshold = 0.10;

/// Share of lanes that must agree with the median's direction.
///
/// This is what separates a shift from noise. Random movement splits near 0.5;
/// a host or SDK change pushes nearly everything one way.
const _defaultAgreement = 0.70;

/// Lanes below this many milliseconds on either side are excluded.
///
/// A `[main]` lane reading 0.00 -> 0.01 ms is a 100% move that means nothing:
/// at that magnitude the suite reports timer granularity, not the peer.
const _defaultMinMs = 0.1;

void main(List<String> args) {
  final threshold = _doubleFlag(args, '--threshold') ?? _defaultThreshold;
  final agreement = _doubleFlag(args, '--agreement') ?? _defaultAgreement;
  final minMs = _doubleFlag(args, '--min-ms') ?? _defaultMinMs;
  final runs = _loadRuns();
  if (runs.length < 2) {
    print('Need at least two parsable release runs; found ${runs.length}.');
    return;
  }

  if (args.contains('--history')) {
    _reportHistory(runs, threshold, agreement, minMs);
    return;
  }

  final since = _stringFlag(args, '--since');
  final candidate = runs.last;
  final baseline = since == null
      ? runs[runs.length - 2]
      : runs.lastWhere(
          (r) => r.date.compareTo(since) <= 0,
          orElse: () => runs.first,
        );

  final shift = peerShift(baseline.peers, candidate.peers, minMs);
  print('Peer drift: ${baseline.label}');
  print('        ->  ${candidate.label}\n');
  if (shift == null) {
    print(
      'No shared peer lanes above ${minMs}ms — these two runs measured '
      'different things, so the control cannot be compared.',
    );
    return;
  }

  print(
    'Median peer movement ${_pct(shift.median)} across ${shift.lanes} lanes, '
    '${(shift.agreement * 100).toStringAsFixed(0)}% moving the same way.',
  );

  if (!shift.exceeds(threshold, agreement)) {
    print(
      '\nWithin tolerance. Individual lanes still swung '
      '(worst ${_pct(shift.worst.first.delta)}), but without a consistent '
      'direction that is peer noise, not the apparatus. resqlite deltas across '
      'this window are comparable.',
    );
    return;
  }

  print('\nThe apparatus moved. Largest contributors:\n');
  for (final d in shift.worst.take(10)) {
    print('  ${_pct(d.delta).padLeft(7)}  ${d.lane}');
    print('           ${d.before} -> ${d.after} ms');
  }
  print(
    '\nA resqlite comparison across this window is measuring the change and '
    'the environment together. Check SDK, host and peer versions before '
    'reading any trend through these runs.',
  );
  if (args.contains('--fail')) exitCode = 1;
}

/// Every step in the corpus, ranked by how far the apparatus moved.
///
/// The retrospective view: it answers "when did the measuring apparatus move",
/// which no artifact recorded at the time.
void _reportHistory(
  List<_Run> runs,
  double threshold,
  double agreement,
  double minMs,
) {
  final shifts = <(_Run, _Run, PeerShift)>[];
  for (var i = 1; i < runs.length; i++) {
    final shift = peerShift(runs[i - 1].peers, runs[i].peers, minMs);
    if (shift == null) continue;
    shifts.add((runs[i - 1], runs[i], shift));
  }
  final flagged =
      shifts.where((s) => s.$3.exceeds(threshold, agreement)).toList()
        ..sort((a, b) => b.$3.median.abs().compareTo(a.$3.median.abs()));

  print('Steps where the apparatus moved, largest first\n');
  for (final (before, after, shift) in flagged.take(20)) {
    print(
      '  ${_pct(shift.median).padLeft(7)}  '
      '${(shift.agreement * 100).toStringAsFixed(0)}% agree  '
      '${shift.lanes.toString().padLeft(3)} lanes   ${after.date}',
    );
    print('           ${before.label}');
    print('        -> ${after.label}');
  }
  print(
    '\n${flagged.length} of ${shifts.length} comparable steps moved the '
    'apparatus beyond ${(threshold * 100).toStringAsFixed(0)}% median with '
    '${(agreement * 100).toStringAsFixed(0)}% agreement. The rest swung '
    'individual lanes without a consistent direction, which is noise.',
  );
}

/// Per-lane deltas between two runs, reduced to a median and an agreement rate.
///
/// Returns null when fewer than five lanes are shared: below that the median
/// is not a statistic, and reporting one would invent confidence.
PeerShift? peerShift(
  Map<String, double> before_,
  Map<String, double> after_,
  double minMs,
) {
  final drifts = <_Drift>[];
  for (final entry in before_.entries) {
    final before = entry.value;
    final after = after_[entry.key];
    if (after == null || before < minMs || after < minMs) continue;
    drifts.add(_Drift(entry.key, before, after, (after - before) / before));
  }
  if (drifts.length < 5) return null;

  final deltas = drifts.map((d) => d.delta).toList()..sort();
  final median = deltas.length.isOdd
      ? deltas[deltas.length ~/ 2]
      : (deltas[deltas.length ~/ 2 - 1] + deltas[deltas.length ~/ 2]) / 2;
  final agreeing = deltas.where((d) => d.sign == median.sign).length;

  return PeerShift(
    lanes: drifts.length,
    median: median,
    agreement: agreeing / deltas.length,
    worst: drifts..sort((x, y) => y.delta.abs().compareTo(x.delta.abs())),
  );
}

/// Committed release artifacts, oldest first.
///
/// Runs with few peer lanes are focused harnesses rather than the release
/// suite; including them would compare disjoint lane sets.
List<_Run> _loadRuns() {
  final dir = Directory('benchmark/results');
  if (!dir.existsSync()) return const [];
  final runs = <_Run>[];
  for (final file in dir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (!name.endsWith('.md')) continue;
    final date = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(name)?.group(1);
    if (date == null) continue;
    final peers = extractPeerMedians(file.readAsStringSync());
    if (peers.length < 10) continue;
    runs.add(_Run(date, name, peers));
  }
  runs.sort((a, b) => a.label.compareTo(b.label));
  return runs;
}

String _pct(double d) => '${d >= 0 ? '+' : ''}${(d * 100).toStringAsFixed(1)}%';

String? _stringFlag(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('$name=')) return a.substring(name.length + 1);
  }
  return null;
}

double? _doubleFlag(List<String> args, String name) {
  final raw = _stringFlag(args, name);
  return raw == null ? null : double.tryParse(raw);
}

class _Run {
  const _Run(this.date, this.label, this.peers);
  final String date;
  final String label;
  final Map<String, double> peers;
}

class PeerShift {
  const PeerShift({
    required this.lanes,
    required this.median,
    required this.agreement,
    required this.worst,
  });

  final int lanes;
  final double median;
  final double agreement;
  final List<_Drift> worst;

  bool exceeds(double threshold, double minAgreement) =>
      median.abs() >= threshold && agreement >= minAgreement;
}

class _Drift {
  const _Drift(this.lane, this.before, this.after, this.delta);
  final String lane;
  final double before;
  final double after;
  final double delta;
}
