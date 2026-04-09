import 'dart:math';

final class BenchmarkTiming {
  BenchmarkTiming(this.label);

  final String label;
  final List<int> wallUs = [];
  final List<int> mainUs = [];

  void record({required int wallMicroseconds, required int mainMicroseconds}) {
    wallUs.add(wallMicroseconds);
    mainUs.add(mainMicroseconds);
  }

  void recordWallOnly(int wallMicroseconds) {
    wallUs.add(wallMicroseconds);
    mainUs.add(wallMicroseconds); // synchronous = all on main
  }

  Stats get wall => Stats(wallUs);
  Stats get main => Stats(mainUs);
}

/// Computed statistics (median, p90, mean) for a set of timing samples.
final class Stats {
  Stats(List<int> raw) : _sorted = List.of(raw)..sort();

  final List<int> _sorted;

  double get medianMs => _sorted[_sorted.length ~/ 2] / 1000.0;
  double get p90Ms => _sorted[(_sorted.length * 0.9).floor()] / 1000.0;
  double get meanMs {
    final sum = _sorted.fold<int>(0, (a, b) => a + b);
    return sum / _sorted.length / 1000.0;
  }
}

String fmtMs(double ms) => ms.toStringAsFixed(2).padLeft(8);

/// Print a comparison table for a set of timings at a given row count.
void printComparisonTable(String title, List<BenchmarkTiming> timings) {
  print('');
  print(title);
  print('-' * title.length);
  print('');

  final labelWidth = timings.map((t) => t.label.length).reduce(max) + 2;

  print(
    '${'Library'.padRight(labelWidth)}'
    '${'Wall med'.padLeft(10)}'
    '${'Wall p90'.padLeft(10)}'
    '${'Main med'.padLeft(10)}'
    '${'Main p90'.padLeft(10)}',
  );
  print('${''.padRight(labelWidth, '-')}'
      '${''.padRight(10, '-')}'
      '${''.padRight(10, '-')}'
      '${''.padRight(10, '-')}'
      '${''.padRight(10, '-')}');

  for (final t in timings) {
    print(
      '${t.label.padRight(labelWidth)}'
      '${fmtMs(t.wall.medianMs)} ms'
      '${fmtMs(t.wall.p90Ms)} ms'
      '${fmtMs(t.main.medianMs)} ms'
      '${fmtMs(t.main.p90Ms)} ms',
    );
  }
  print('');
}

/// Generate markdown table for a set of timings.
String markdownTable(String title, List<BenchmarkTiming> timings) {
  final buf = StringBuffer();
  buf.writeln('### $title');
  buf.writeln('');
  buf.writeln(
    '| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |',
  );
  buf.writeln('|---|---|---|---|---|');
  for (final t in timings) {
    buf.writeln(
      '| ${t.label} '
      '| ${t.wall.medianMs.toStringAsFixed(2)} '
      '| ${t.wall.p90Ms.toStringAsFixed(2)} '
      '| ${t.main.medianMs.toStringAsFixed(2)} '
      '| ${t.main.p90Ms.toStringAsFixed(2)} |',
    );
  }
  buf.writeln('');
  return buf.toString();
}
