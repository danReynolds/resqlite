---
title: Why resqlite Started
slug: 2026-04-06-main-isolate
date: 2026-04-06
summary: resqlite began as a Flutter SQLite library shaped by one product constraint: keep database work from stealing frame time while preserving ordinary SQLite ergonomics and reactive queries.
tags: main isolate, Flutter, measurement
tone: green
---

# Why resqlite Started

## Problem Statement

resqlite did not start as an attempt to make SQLite itself faster. SQLite was already fast. The starting problem was how SQLite felt inside a data-heavy Flutter app: screen loads, reactive views, and writes all competed with rendering and input when too much database work happened on the main isolate.

The library goal was deliberately practical: keep the directness of SQLite, expose ordinary Dart rows, support reactive queries, and avoid making application code own invalidation rules. The first constraint was therefore not "can SQLite be fast?" It was: can a Dart SQLite wrapper keep normal query ergonomics while moving database work and result preparation off the UI isolate?

## Background

The first motivating workload was ordinary screen loading: query a few thousand rows, turn them into Dart data, and let the UI render. The synchronous `sqlite3` package ran the query and materialized rows on the calling isolate, which was usually the main isolate. That is a reasonable API for many programs, but it is uncomfortable when the caller is also responsible for frame production.

The second requirement was reactivity. The application wanted live queries: widgets should update when writes changed their data without every call site maintaining its own cache, listener, or table-dependency logic. That requirement made resqlite more than "run SQLite on a worker." It had to become a small database runtime for Flutter.

For readers new to this part of Flutter: the [Flutter performance guide](https://docs.flutter.dev/perf/ui-performance) frames smoothness around the frame budget, and the [Flutter isolate guide](https://docs.flutter.dev/perf/isolates) explains why CPU-heavy work is commonly moved away from the main isolate. Dart's lower-level [isolate documentation](https://dart.dev/language/isolates) is the runtime background behind `Isolate.run`, `Isolate.spawn`, `SendPort`, and `ReceivePort`.

Those requirements set the first design constraints:

1. Reads and writes should run away from the main isolate.
2. Query results should still arrive in ordinary Dart types.
3. Stream invalidation should be part of the database layer.
4. Benchmarks should report main-isolate time separately from end-to-end wall time.

## Hypothesis

The first hypothesis was intentionally modest: moving SQLite execution to a worker isolate should reduce UI-isolate exposure. The more important hypothesis came immediately after: this only solves the product problem if the result representation also crosses isolates cheaply. A small transfer graph, such as one `Uint8List`, should put much less pressure on the main isolate than a large graph of Dart maps.

That made the first lesson about measurement rather than cleverness. A byte buffer is not automatically better because it is "lower level"; it is better when the caller wants bytes. If the caller wants rows, bytes still have to become Dart values somewhere. The opening story in the project is therefore about choosing the right metric before choosing the data structure.

## What We Tried

The first prototype was close to what many Flutter developers would try first: put the SQLite call on a worker isolate while keeping the caller-facing row shape familiar.

```dart
final rows = await Isolate.run(() {
  final db = sqlite3.open('app.db');
  return db.select('SELECT * FROM items');
});
```

That moved SQLite execution away from the caller, but returned `List<Map<String, Object?>>`. A second path returned one byte buffer instead, matching the direction later captured in [Experiment 001](../../../experiments/001-c-native-json-serialization.md). The point was not that JSON bytes should be the final API. It was a probe: how much of the observed pain came from SQLite execution, and how much came from the shape of the Dart data crossing back?

## Results

The important signal was main-isolate time, not just wall time:

| Path (5,000 rows) | Wall | Main |
|---|---:|---:|
| Synchronous on main | 15.30 ms | **8.64 ms** |
| `Isolate.run()` -> `List<Map>` | 15.15 ms | **7.84 ms** |
| `Isolate.run()` -> `Uint8List` | 16.03 ms | **0.00 ms** |

[Experiment 001](../../../experiments/001-c-native-json-serialization.md) measured the same idea on the JSON response path:

| Path (5,000 rows, about 1 MB JSON) | Wall |
|---|---:|
| resqlite `selectBytes()` with C JSON | **4.35 ms** |
| `sqlite3` package + `jsonEncode` | 15.02 ms |

The byte path was not just faster. It avoided creating Dart result objects for the response body, which meant there was essentially nothing heavy for the main isolate to validate or encode.

## Outcome

The first design principle became measurable: wall time matters, but main-isolate time is the product constraint for Flutter. From this point on, resqlite treated "async SQLite" as insufficient. The goal became SQLite with small main-isolate exposure, a normal row API, and enough internal structure to support reactive queries without pushing bookkeeping into application code.

This opening measurement set up the rest of the project. The next stories ask, in order, what the isolate boundary really costs, which result representations fail under that constraint, and what shape finally lets resqlite keep the API ordinary without handing too much work back to the UI isolate.

## Related Experiments

- [Experiment 001: C-native JSON serialization](../../../experiments/001-c-native-json-serialization.md)
- [Experiment 002: C binary buffer for maps](../../../experiments/002-c-binary-buffer-for-maps.md)

## Reference Docs

- [Flutter performance profiling](https://docs.flutter.dev/perf/ui-performance)
- [Flutter concurrency and isolates](https://docs.flutter.dev/perf/isolates)
- [Dart isolates](https://dart.dev/language/isolates)
