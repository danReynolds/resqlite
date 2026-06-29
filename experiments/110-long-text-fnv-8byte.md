# Experiment 110: Long-text stream hash benchmark + 8-byte FNV

**Date:** 2026-04-27T15:46:01
**Status:** Accepted
**Direction:** `long-text-stream-hashing`, `measurement-system`
**PR:** [#53](https://github.com/danReynolds/resqlite/pull/53)

## Problem

Experiment 099 found a structurally sound optimization for TEXT/BLOB hashing,
but rejected it because the benchmark suite did not contain a stream workload
with long enough cells to exercise the byte-stream hash loop. The new research
map correctly pointed at this as a measurement-first direction: build the
missing long-text workload before spending more time on hash-loop variants.

The current stream unchanged-result fast path still hashes raw SQLite TEXT bytes
in C before deciding whether to skip Dart decode. SQLite's result-value API
supports this shape: callers can read UTF-8 text with `sqlite3_column_text()`,
then get its byte length with `sqlite3_column_bytes()`, and the pointer remains
valid until the statement steps, resets, or finalizes. Recent SQLite release
notes did not expose a new C API that replaces this local hash loop, and Dart's
current isolate-transfer tools do not remove the need to avoid decode entirely
on unchanged stream re-queries.

Sources checked:

- SQLite result values API: https://www.sqlite.org/c3ref/column_blob.html
- SQLite 3.53.0 release notes: https://www.sqlite.org/changes.html
- Dart isolates: https://dart.dev/language/isolates
- `TransferableTypedData`: https://api.dart.dev/dart-isolate/TransferableTypedData-class.html
- sqlite_async peer streaming context: https://pub.dev/packages/sqlite_async

## Hypothesis

Adding a representative long-text unchanged-fanout benchmark should make the
hash-loop cost visible. If that happens, reviving experiment 099's 8-byte
chunked byte fold should produce a large win on the new workload while keeping
short-cell workloads and public API behavior effectively unchanged.

## Approach

Added a default streaming benchmark:

- 8 unchanged streams
- 256 rows per unchanged result
- 4KB ASCII TEXT cell per row
- one changed long-text barrier stream registered after the unchanged streams

Each timed iteration inserts a new row outside the unchanged streams'
predicate. The unchanged streams must not emit; the barrier stream changes and
emits, giving the benchmark a practical completion signal for the fanout wave.

Then revived the archived experiment 099 C change in `fnv_combine_bytes`:

```c
for (; i + 8 <= len; i += 8) {
    uint64_t word;
    memcpy(&word, b + i, 8);
    h ^= word;
    h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
}
for (; i < len; i++) {
    h ^= (uint64_t)b[i];
    h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
}
```

`memcpy(&word, b + i, 8)` is the standard unaligned-safe load idiom. The hash
bit pattern is host-byte-order dependent, but stream hashes are in-memory only:
the producer and consumer are always the same process and same algorithm
version.

## Results

Artifacts:

- `benchmark/results/2026-04-27T15-42-56-baseline-for-exp110-long-text.md`
- `benchmark/results/2026-04-27T15-42-56-baseline-for-exp110-long-text.json`
- `benchmark/results/2026-04-27T15-46-01-exp110-fnv-8byte-long-text.md`
- `benchmark/results/2026-04-27T15-46-01-exp110-fnv-8byte-long-text.json`

Target workload:

| Benchmark | Baseline | 8-byte FNV | Delta |
|---|---:|---:|---:|
| Long-Text Unchanged Fanout median | 10.328 ms | 2.435 ms | -76% |
| Long-Text Unchanged Fanout p90 | 15.035 ms | 3.871 ms | -74% |

The full one-pass release comparison reported **20 wins, 11 regressions, 124
neutral**. The broad suite deltas were noisy in both directions, which is normal
for single-repeat release runs. The targeted long-text result is far outside the
threshold and matches the exact path changed by the implementation.

Correctness checks:

- `dart test test/query_decoder_test.dart test/stream_test.dart --timeout 60s`

The stream test suite now includes a long-text case that verifies both sides of
the hash contract: a no-op long-text update does not emit, and a same-length
change after the first 8-byte chunk does emit.

## Decision

Keep in review.

The experiment is accepted for PR review: the revised process did exactly what
it was designed to do. It kept the prior rejected idea available without forcing
it, identified the missing benchmark as the next useful step, and then let the
new evidence turn experiment 099's implementation from "structurally sound but
unmeasurable" into a clear targeted win.

The main caution is methodological: the single-run full-suite comparison should
not be over-read. The acceptance signal is the new long-text benchmark plus
targeted correctness coverage; CI and review should still watch for unexpected
platform-specific fallout from the host-byte-order hash bit pattern.

## Future Notes

The long-text stream benchmark is now part of the default release suite and the
experiment dashboard's curated metrics. Future hash-loop work should compare
against this benchmark first, then check the normal short-text streaming metrics
for regressions. Avoid more hashing variants unless they improve this workload
or a production profile shows a new long-payload shape.
