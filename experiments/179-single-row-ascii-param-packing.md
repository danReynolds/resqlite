# Experiment 179: Single-row ASCII parameter packing

**Date:** 2026-06-16
**Status:** Rejected
**Direction:** `parameter-encoding-and-binding`
**Archive:** [`archive/exp-179`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-179)
**Benchmark Run:** Release-suite A/B (5×5 repeats) + focused `single_row_param_packing.dart` micro; see Results.

## Problem

Exp 125/149/150 gave the *batch* parameter encoder a direct-write fast path:
for ASCII (and UTF-8) text it copies code units straight into the single packed
param buffer instead of calling `utf8.encode()` per string, removing one
`Uint8List` allocation per string plus the `encodedStrings` list.

The *single-row* encoder — `allocateParams` in
`lib/src/native/resqlite_bindings.dart`, the path every non-batch
`execute`/`select` parameter list goes through — never got that treatment. It
still does pass 1 = `utf8.encode` each string into an `encodedStrings`
`List<Uint8List?>`, then pass 2 = copy the encoded bytes into the buffer. For an
all-ASCII parameter list that is one `Uint8List` allocation per string plus the
list, on the hottest bind path in the library.

**Prior art (this is a refinement of exp 142 / PR #130, not a new idea).** Exp
142 already retested "direct single-row text parameter encoding" under Tracelite
on chat-sim and narrow-batch-insert, saw +6.86% / +16.4% (slower, high CV,
inconclusive), and recorded *"small single-row string binding should stay on the
generic `allocateParams` path unless a future workload makes that encoding cost
material."* What exp 142 lacked was an isolated measurement of the *encoder
itself* — its workloads couldn't tell whether the direct path was actually
slower or just lost in workload noise. Exp 179 adds that isolation (a DB-free
encoder micro) to settle the mechanism question, and re-checks the release
suite.

## Hypothesis

Extending the batch path's direct-code-unit write to `allocateParams` should
remove those allocations for all-ASCII parameter lists (the common case), and a
hot enough single-row-bind workload — the Parameterized Queries lane
(`SELECT … WHERE category = ?`, one ASCII param × 100) and single-row text
inserts — should show a measurable wall improvement.

Acceptance criterion (set before running): the release suite's Parameterized
Queries or Single Inserts lane moves outside the run-to-run noise band, with no
regression elsewhere.

## Approach

`lib/src/native/resqlite_bindings.dart` — `allocateParams`:

- Pass 1 sizes the payload by scanning each string for non-ASCII code units.
  For an all-ASCII list the UTF-8 byte length equals `String.length`, so the
  buffer is sized from O(1) lengths with no `utf8.encode` and no
  `encodedStrings` list.
- Pass 2 writes structs and copies string code units directly
  (`view[dataOffset++] = value.codeUnitAt(j)`), exactly as the batch ASCII
  writer does.
- The first non-ASCII string bails to `_allocateParamsPreEncoded`, which is the
  original `utf8.encode`-per-string implementation (now factored out as the
  fallback). Integers, doubles, blobs, nulls, and embedded-NUL ASCII text are
  byte-identical to before.

No public API change. `dart test` — **303 passed** (text/unicode/blob/null/
embedded-NUL bind coverage included).

## Results

### Release suite A/B (`run_release.dart`, 5 repeats each side)

| Lane | Baseline | Candidate | Δ |
|---|---:|---:|---:|
| Parameterized Queries (100 × ~500 rows) | 14.046 ms | 14.052 ms | +0.04% |
| Single Inserts (100 sequential) | 1.422 ms | 1.398 ms | −1.7% (p90 +5%) |
| Concurrent Single Inserts (100) | 0.993 ms | 1.001 ms | +0.8% |

Overall comparison: **1 timing win / 0 regressions / 166 neutral.** The lone
flagged win and the one Memory flag (`Select 10k → Maps` RSS, +6.35 MB inside a
±5.00 MB MDE) are on the result-read path, which this change does not touch —
run-to-run noise, not effects of the bind change.

### Focused encoder micro (`single_row_param_packing.dart`, 200k cycles × 15 samples)

Times `allocateParams` + `freeParams` in isolation — no DB, FFI step, or result
transfer:

| Shape | Baseline ns/op | Candidate ns/op | Δ |
|---|---:|---:|---:|
| 1 short ASCII param | 60.7 | 33.6 | **−45%** |
| 5 mixed (int + 4 ASCII text) | 210.3 | 88.2 | **−58%** |
| 1 large ASCII (1 KB) | 2361.4 | 1493.2 | **−37%** |
| blob + int (no string — control) | 41.7 | 40.4 | flat |

The flat blob+int control confirms the ASCII deltas are the real allocation
removal, not thermal/measurement bias. (A `unicode-1` fallback shape read
~−53% in the same process, but that is cross-shape GC contamination — the
baseline generates far more garbage in the preceding ASCII shapes; the fallback
is byte-for-byte the original code and is neutral by construction.)

## Decision

**Rejected — real in isolation, below the noise floor on representative
workloads.**

The encoder is genuinely 37–58% faster on ASCII single-row binds in isolation,
and the mechanism is exactly as hypothesized. But the bind is too small a
fraction of any representative workload to register: the Parameterized lane
spends its wall on transferring/parsing ~500 result rows, and single inserts
pay the isolate round-trip — so the suite is flat (+0.04% / −1.7% / +0.8%, all
inside noise). This is the exp 146 result restated for the single-row path:
narrow/single-row param allocation removal stays below the floor on real
workloads.

Against ~60 lines of duplicated packing logic (the `_allocateParamsPreEncoded`
fallback), a win that is invisible everywhere except a synthetic encoder loop
does not clear the bar. Reverted from `lib/`; the focused micro is retained for
future bind-path rechecks and the implementation is preserved at
`archive/exp-179`.

**Refinement of exp 142.** This sharpens exp 142's record: the direct single-row
encoder is *not* slower (142's +6.86% / +16.4% was workload/Tracelite-overhead
confound, not the encoder) — it is meaningfully faster in isolation. The
operative reason to stay on the generic path is therefore *immateriality*, not a
regression. Exp 142's conclusion ("stay generic unless a workload makes the
encoding cost material") stands, now backed by an isolated encoder measurement
rather than only workload-level Tracelite runs.

Would reopen if a representative workload appears where single-row binds of
**large** ASCII text dominate (the 1 KB shape's −37% is the largest isolated
win) and the round-trip/result cost no longer hides it.

## Future Notes

- The batch path already has this optimization; this experiment closes the
  question of whether the single-row path should mirror it. It should not,
  absent a large-single-row-text-bind workload.
- `single_row_param_packing.dart` is the durable contribution: a DB-free
  microbenchmark that isolates `allocateParams` cost, reusable by any future
  bind-path experiment.
- Per exp 146 / this experiment, allocation-removal-only changes on narrow
  param shapes should be measured against representative wall lanes, not just an
  encoder micro, before acceptance.
