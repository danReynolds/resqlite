import 'dart:io';

/// Peak-RSS guard for focused experiment harnesses
/// ([EXP-261](../../experiments/261-focused-memory-guard.md)).
///
/// Focused AOT A/B harnesses are where experiments are actually decided, and
/// until now they measured wall time only — a candidate could halve a lane's
/// latency and double its memory without anything noticing. This is the
/// smallest instrument that closes that hole in the mode those harnesses have
/// to run in.
///
/// ## What it can and cannot tell you
///
/// It is a **regression guard, not a metric**, and the asymmetry is not a
/// limitation of the implementation — it is what `ProcessInfo` measures:
///
/// - **`currentRss` and `maxRss` can tell opposite stories, and `maxRss` is the
///   one to gate on.** On a lane whose results cross `sacrificeSlotThreshold`,
///   the two disagreed by 76 percentage points about the same change: sampled
///   `currentRss` peaked at 36.6 MB against 64.0 MB, while `maxRss` was 65.9 MB
///   against 64.8 MB — a 1.7% *fall*, inside the run-to-run band and nothing like
///   the regression the other reading reports. Both are honest. `maxRss` is
///   the true high-water; a sampled `currentRss` curve only says how much is
///   resident at the instants you looked, which is a *retention* signal, and
///   retention moves when isolates die and hand their pages back. Read
///   [MemoryReading.maxMb] for "did peak memory get worse" and
///   [MemoryReading.growthMb] for "how much does this hold between reads".
/// - **Within one isolate the VM keeps pages after GC**, so a candidate that
///   frees more of its own garbage reads as "no change" rather than as a win.
///   A whole isolate exiting *does* return memory, which is why a sacrificing
///   lane's `currentRss` falls and a non-sacrificing one's does not.
/// - **`maxRss` is a process-lifetime high-water mark.** In a harness that runs
///   several lanes in one process, every lane after the first inherits the
///   watermark of the ones before it. A per-lane figure is only trustworthy
///   when that lane had the process to itself — run with `--lane=<name>`, which
///   is why [MemoryReading.laneIsolated] is recorded alongside the numbers.
/// - Process RSS covers **every isolate**, so a change that alters how often
///   reader workers are sacrificed and respawned moves this number for reasons
///   that have nothing to do with the allocation under test. Read it next to
///   whether the lane crosses `sacrificeSlotThreshold`.
///
/// Heap-level attribution would answer all of that, and is not available here:
/// an AOT binary has no VM service (`Service.getInfo()` returns null and
/// `--enable-vm-service` is rejected), and running the candidate under JIT to
/// get one would change the thing being measured — exp 193 requires AOT for any
/// decode-path result. When an experiment's *subject* is memory rather than its
/// guard, instrument the allocation directly with a counter instead.
///
/// ## Use
///
/// Sample between timed iterations, never inside them — a `currentRss` read
/// costs ~700 ns, which is real money against a lane whose samples are tens of
/// microseconds:
///
/// ```dart
/// final memory = MemoryProbe.start();
/// for (var i = 0; i < samples; i++) {
///   final sw = Stopwatch()..start();
///   await db.select(sql);
///   sw.stop();
///   values.add(sw.elapsedMicroseconds);
///   memory.sample();
/// }
/// final reading = memory.finish(laneIsolated: onlyLane != null);
/// ```
final class MemoryProbe {
  MemoryProbe._(this._startRss) : _peakRss = _startRss;

  /// Take the baseline reading. Call after the lane has seeded its data and
  /// finished warming up, so setup allocation is not attributed to the
  /// measured region.
  factory MemoryProbe.start() => MemoryProbe._(ProcessInfo.currentRss);

  final int _startRss;
  int _peakRss;
  int _samples = 0;

  /// Record one reading. Call outside the stopwatch.
  void sample() {
    final rss = ProcessInfo.currentRss;
    if (rss > _peakRss) _peakRss = rss;
    _samples++;
  }

  MemoryReading finish({required bool laneIsolated}) => MemoryReading(
    startRssBytes: _startRss,
    peakRssBytes: _peakRss,
    maxRssBytes: ProcessInfo.maxRss,
    samples: _samples,
    laneIsolated: laneIsolated,
  );
}

/// One lane's memory reading. See [MemoryProbe] for what these numbers mean —
/// in particular, why [maxMb] and [growthMb] can disagree about the same
/// change, and which one to gate on.
final class MemoryReading {
  const MemoryReading({
    required this.startRssBytes,
    required this.peakRssBytes,
    required this.maxRssBytes,
    required this.samples,
    required this.laneIsolated,
  });

  final int startRssBytes;
  final int peakRssBytes;
  final int maxRssBytes;
  final int samples;

  /// Whether this lane had the process to itself. [maxRssBytes] is only
  /// comparable across arms when this is true.
  final bool laneIsolated;

  double get startMb => startRssBytes / (1024 * 1024);
  double get peakMb => peakRssBytes / (1024 * 1024);
  double get maxMb => maxRssBytes / (1024 * 1024);

  /// How far resident memory climbed across the measured region — a retention
  /// signal, not a peak. A candidate that climbs further is holding more
  /// between reads, which may mean it allocates more or merely that it returns
  /// less. Gate on [maxMb]; read this one for the shape.
  double get growthMb => (peakRssBytes - startRssBytes) / (1024 * 1024);

  /// Space-separated `key=value` fields, matching the `shape=... median_us=...`
  /// convention the focused harnesses already emit so a pair of runs can be
  /// diffed with the same tooling.
  String format() =>
      'rss_start_mb=${startMb.toStringAsFixed(1)} '
      'rss_peak_mb=${peakMb.toStringAsFixed(1)} '
      'rss_growth_mb=${growthMb.toStringAsFixed(1)} '
      'max_rss_mb=${maxMb.toStringAsFixed(1)} '
      'rss_samples=$samples '
      'lane_isolated=$laneIsolated';
}
