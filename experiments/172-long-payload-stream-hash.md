# Experiment 172: Long-payload stream hash coverage

**Date:** 2026-06-15
**Status:** In Review
**Direction:** `long-text-stream-hashing`, `measurement-system`

## Problem

Experiment 110 turned the rejected exp 099 8-byte FNV byte fold into a clear
win by adding a 4KB TEXT unchanged-fanout workload. The signal map still had
one measurement blocker open: no benchmark covered larger stream payloads or a
mixed TEXT/BLOB shape. Without that row, future runners could either overfit
to the text-only 4KB case or reopen hash-loop variants without knowing whether
the current chunked fold already handles broader long-payload streams.

## Hypothesis

Adding a mixed long-payload unchanged-fanout row should either expose a new
hashing bottleneck beyond exp 110, or close the blocker by showing that the
current 8-byte FNV fold scales acceptably to 32KB TEXT plus 32KB BLOB cells.

This run is complete under the paired measurement rule if the new row consumes
the blocker and either:

- shows enough headroom to name the next implementation candidate; or
- refutes the premise that another immediate hash-loop implementation is
  warranted.

## Approach

`benchmark/suites/streaming.dart` now has a direct `main()` so the streaming
suite can be run as a focused benchmark without compiling the full release
runner and its Drift-generated peers.

The new row is:

```text
Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)
```

Shape:

- 8 unchanged streams.
- Each unchanged result is 64 rows.
- Each row carries one 32KB ASCII TEXT cell and one 32KB BLOB cell.
- Inserts target ids outside the unchanged predicate, so the unchanged streams
  must hash and suppress re-emission.
- A `COUNT(*)` barrier stream is registered after the unchanged streams and
  changes on each insert, giving the timed loop a practical drain signal
  without decoding the large unchanged payloads.

Correctness coverage adds a long-BLOB stream test that verifies both sides of
the hash contract: a no-op BLOB update does not emit, and a same-length change
after the first 8-byte chunk does emit.

No production runtime code changed.

## Results

Focused validation:

```text
dart analyze --fatal-infos benchmark/suites/streaming.dart test/stream_test.dart
dart test test/stream_test.dart --timeout 60s
dart run benchmark/suites/streaming.dart
```

Focused stream benchmark medians from the same run:

| Row | resqlite wall p50 | resqlite wall p90 |
|---|---:|---:|
| Unchanged Fanout (1 canary + 10 unchanged streams) | 0.288 ms | 0.594 ms |
| Long-Text Unchanged Fanout (8 streams, 256 rows x 4KB TEXT) | 2.356 ms | 5.339 ms |
| Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB) | 3.446 ms | 5.011 ms |

The mixed row hashes roughly four times the payload bytes of the exp 110 row
per unchanged fanout wave, yet its median is only about 46% higher on this
machine. That is not a clean optimization target by itself: the row now gives
future experiments coverage for mixed long payloads, but it does not justify a
new hash-loop implementation in the absence of a more specific mechanism or a
production profile showing this path as dominant.

## Decision

**In Review - measurement coverage; immediate new hash variant deferred.**

The measurement blocker is closed. Resqlite now has default streaming-suite
coverage for long payloads beyond exp 110's 4KB TEXT cells, including BLOB
hashing. The result refutes the premise that another immediate hash-loop pass
is needed: current chunked FNV handles the broader shape well enough that the
next implementation should wait for a production profile or a concrete variant
that can explain why it should beat the existing 8-byte fold.

## Future Notes

- Use the new mixed row alongside the exp 110 TEXT row before trying any
  future byte-stream hash variant.
- Do not infer BLOB behavior from the 4KB TEXT row anymore; the streaming
  suite has a dedicated mixed-payload check.
- Reopen implementation work if a production profile shows long TEXT/BLOB
  unchanged fanout is still dominant, or if a new hash algorithm/loop shape has
  a concrete reason to improve both long rows without hurting short-cell
  streaming.

## Validation

- `dart pub get`
- `dart analyze --fatal-infos benchmark/suites/streaming.dart test/stream_test.dart`
- `dart test test/stream_test.dart --timeout 60s`
- `dart run benchmark/suites/streaming.dart`
