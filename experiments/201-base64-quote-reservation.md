# Experiment 201: Base64 quote reservation for selectBytes BLOBs

**Date:** 2026-06-27T06:09:31-04:00
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** focused `benchmark/experiments/select_bytes_blob_base64.dart`, order-flipped pair
**Archive:** [`archive/exp-201`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-201)

## Problem

After [exp 199](199-row-level-buf-ensure.md), fixed-size
NULL/INTEGER/FLOAT cells in `write_json_to_buf` write directly under one
row-level reservation. Variable-size TEXT and BLOB cells still go through their
helpers because their encoded length is data-dependent.

The BLOB helper, `json_write_base64`, had a small remaining per-cell framing
cost:

```c
buf_write_char(b, '"');
buf_ensure(b, encoded_len);
... write base64 ...
buf_write_char(b, '"');
```

For BLOB-heavy `selectBytes()` payloads with many tiny cells, those two quote
writes and three capacity checks could plausibly be a visible part of the
cell-level overhead left after the numeric encoder work. Unlike a new base64
algorithm, this candidate is deliberately small and behavior-preserving.

## Hypothesis

Reserving `encoded_len + 2` once and writing the opening and closing JSON quotes
directly around the base64 payload should remove two helper calls and two
capacity checks per BLOB cell.

The acceptance bar was set on the tiny-BLOB lanes: if the mechanism matters,
the many-cell shapes should reproduce a candidate-faster result across an
order-flipped pair. Medium and large BLOB lanes are guardrails because the
base64 loop and transfer volume should dominate there.

## Approach

The archived prototype changed only `native/resqlite.c`:

- compute the same `encoded_len = ((len + 2) / 3) * 4`,
- call `buf_ensure(b, encoded_len + 2)` once,
- write `"` directly before and after the encoded payload,
- advance `b->len` by `encoded_len + 2`.

The experiment also adds
`benchmark/experiments/select_bytes_blob_base64.dart`, a focused harness with
tiny, small, medium, large, and mixed BLOB `selectBytes()` lanes. The runtime
prototype is archived at `archive/exp-201` and reverted from this branch; only
the harness and experiment record are kept.

## Results

Focused harness: `dart run benchmark/experiments/select_bytes_blob_base64.dart`.
Values are median microseconds per `selectBytes()` query.

| Lane | Baseline P1 | Candidate P1 | Delta P1 | Candidate P2 | Baseline P2 | Delta P2 |
|---|---:|---:|---:|---:|---:|---:|
| 10k rows x 8 tiny blobs (3B) | 2373 | 2379 | +0.3% | 2358 | 2360 | -0.1% |
| 10k rows x 20 tiny blobs (3B) | 5530 | 5417 | -2.0% | 5385 | 5340 | +0.8% |
| 10k rows x 8 small blobs (16B) | 2943 | 2945 | +0.1% | 2946 | 2888 | +2.0% |
| 10k rows x 4 medium blobs (128B) | 3847 | 3796 | -1.3% | 3823 | 3899 | -1.9% |
| 1k rows x 2 large blobs (4KB) | 4984 | 4602 | -7.7% | 4702 | 4885 | -3.7% |
| 10k rows x 8 mixed (4 blob + 2 int + 2 text) | 2777 | 2742 | -1.3% | 2803 | 2743 | +2.2% |

Focused correctness:

```bash
dart test test/database_test.dart --name "selectBytes encodes blobs as base64"
```

The test passed against the archived prototype.

## Decision

Rejected. The candidate did not move the lanes that should have carried the
mechanism. The 8-column tiny-BLOB lane was flat in both pass orderings, the
20-column tiny-BLOB lane changed sign, and the small/mixed lanes were flat or
worse in the confirmation pass. Medium and large BLOBs trended faster, but that
is not enough to keep the runtime change: those lanes have far fewer BLOB cells,
so a quote-framing optimization is not the load-bearing explanation.

No runtime code is kept. The focused harness remains because it closes this
specific candidate and gives future BLOB encoder work a direct gate.

## Future Notes

- Do not retry quote/framing reservation in `json_write_base64` without a new
  compiler/runtime fact; the many-tiny-cell lanes did not reproduce a win.
- Future BLOB `selectBytes()` work should change the base64 loop, the BLOB
  transport shape, or a measurable allocation/copy boundary, not only the quote
  writes around the encoded payload.
- Use `benchmark/experiments/select_bytes_blob_base64.dart` before accepting
  any future BLOB JSON encoder change. A real win should move the tiny-cell
  lanes and keep the medium/large lanes neutral or better.
