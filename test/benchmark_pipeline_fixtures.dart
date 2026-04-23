String fixtureHardwareResultsMarkdown({required String resultFile}) => '''
## Devices

| Device | CPU | OS | Dart | Date | By | Result File |
|---|---|---|---|---|---|---|
| Fixture Mac | M1 | macOS 26.2 | 3.11 | 2026-04-23 | @tester | $resultFile |
''';

const fixtureBenchmarkMarkdown = '''
# resqlite Benchmark Results

## Select → Maps

### 1000 rows

| Library | Wall med | Wall p90 | Main med | Main p90 |
|---|---|---|---|---|
| resqlite select() | 1.23 | 1.50 | 0.12 | 0.15 |
| sqlite3 select() | 2.34 | 2.80 | 2.34 | 2.80 |
''';

const fixtureExperimentsReadmeMarkdown = '''
## Accepted

| ID | Title | Impact | Commit |
|---|---|---|---|
| [083](083-test.md) | Test Experiment | Synthetic summary | [`deadbee`](https://example.com) |
''';

const fixtureExperimentMarkdown = '''
**Date:** 2026-04-23
**Commit:** [`deadbee`](https://example.com)

## Problem
Synthetic benchmark fixture.

## Hypothesis
Structured sidecars should win over markdown parsing.

## Primary Metrics
- `1000 rows / resqlite select()`

## Decision
Accepted for testing.
''';
