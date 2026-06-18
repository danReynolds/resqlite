# Experiment 186: Single-row large-text bind encoder

**Date:** 2026-06-18
**Status:** Accepted
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** Release-suite A/B (5 repeats/side) + focused
  `single_row_large_text_bind.dart` workload, two passes; see Results.

## Problem

Exp 179 retired the single-row direct-ASCII rewrite of `allocateParams`
(in `lib/src/native/resqlite_bindings.dart`) because it landed flat on
every representative release-suite lane — Parameterized Queries
(1-short-ASCII param), Single Inserts (1-int + 4-short-text typical
shapes), and the wide-batch path that already had its own direct ASCII
fast path (exp 125/149/150). The encoder was 37–58 % faster in
isolation but the bind cost was too small a fraction of any
public workload to register.

Exp 179's writeup left an explicit revisit: *"do not re-test single-row
allocateParams direct encoding again without a representative
large-single-row-ASCII-text-bind workload where the round-trip/result
cost no longer hides the encoder; the encoder mechanism is now measured
and settled (see `single_row_param_packing.dart`)."* The library has
no such public workload yet: every existing single-row bind shape sits
well under 64 bytes of text payload, so the encoder's per-string
`utf8.encode()` allocation + `setRange()` copy is dominated by the
~3 ms writer round-trip floor.

Large-single-row text binds are common in real apps — chat-message
inserts, log-line inserts, JSON-document persists, blob-flavored TEXT
columns — and the encoder cost scales linearly with text size. At
text payload around 16 KB the encoder allocation and intermediate copy
should become a material fraction of single-write wall.

## Hypothesis

For ASCII single-row text binds with payloads at or above the
mid-tens-of-KB range, the encoder's `utf8.encode(value)` allocation +
`view.setRange(...)` copy is a measurable fraction of wall time, and
the exp 179 direct code-unit write path (sized from `String.length`,
copied via `view[i++] = value.codeUnitAt(j)`) saves enough to clear a
focused-workload primary gate without regressing the small-payload
release-suite lanes that exp 179 measured flat.

Acceptance criterion (set before running): the focused large-text
workload (added in this experiment) moves > 5 % at one or more of the
16 KB / 64 KB / 256 KB / 1 MB shapes, reproduced across two passes,
with all small-payload release-suite lanes neutral.

## What We Built

1. **Encoder change** (`lib/src/native/resqlite_bindings.dart`) —
   revives exp 179's two-pass `allocateParams` rewrite:
   - Pass 1 scans each string for non-ASCII code units; an all-ASCII
     list sizes the buffer from O(1) `String.length` with no
     `utf8.encode()` and no `encodedStrings` `List<Uint8List?>`. The
     first non-ASCII string bails to `_allocateParamsPreEncoded`
     (factored out, byte-for-byte the original implementation).
   - Pass 2 copies code units directly into the param buffer
     (`view[dataOffset++] = value.codeUnitAt(j)`), exactly like the
     batch ASCII writer (exp 125/149). Embedded-NUL ASCII bytes stay
     correct because `text.len` carries the actual byte count.

   No public API change. Integers, doubles, blobs, nulls, and
   embedded-NUL ASCII text remain byte-identical to before.

2. **Focused workload** (`benchmark/experiments/single_row_large_text_bind.dart`)
   — sequential `INSERT INTO doc(body) VALUES (?)` of an ASCII-only
   text param at 1 KB / 16 KB / 64 KB / 256 KB / 1 MB, 100 writes per
   sample, 11 samples per shape. Each shape warms up 5 writes and
   `DELETE`s between samples so the page cache isn't carrying state
   across measurements. The harness directly exercises `allocateParams`
   on the writer-isolate path used by every non-batch `db.execute()`.

## Results

### Focused workload (two passes — `single_row_large_text_bind.dart`)

Pass 1 (candidate first):

| Text bytes | Baseline med ms | Candidate med ms | Δ |
|---|---:|---:|---:|
| 1 KB | 4.63 | 4.44 | −4.1 % |
| 16 KB | 10.38 | 8.78 | −15.4 % |
| 64 KB | 29.77 | 24.61 | −17.3 % |
| 256 KB | 133.80 | 90.60 | **−32.3 %** |
| 1 MB | 487.37 | 357.28 | **−26.7 %** |

Pass 2 (order-flipped, baseline first):

| Text bytes | Baseline med ms | Candidate med ms | Δ |
|---|---:|---:|---:|
| 1 KB | 4.64 | 4.10 | −11.6 % |
| 16 KB | 10.04 | 8.93 | −11.1 % |
| 64 KB | 29.92 | 24.33 | −18.7 % |
| 256 KB | 134.16 | 91.06 | **−32.1 %** |
| 1 MB | 493.34 | 352.81 | **−28.5 %** |

Both passes agree same-direction across every shape, with the largest
wins (256 KB / 1 MB) reproducing within ~2 % of each other. The 1 KB
shape stays inside the focused harness's per-sample variance; the
material wins start at 16 KB.

### Encoder isolation (`single_row_param_packing.dart`, 200k cycles × 15 samples)

Exp 179's deltas reproduce exactly on the same baseline:

| Shape | Baseline ns/op | Candidate ns/op | Δ |
|---|---:|---:|---:|
| ascii-1-short | 60.3 | 33.3 | −45 % |
| ascii-5-mixed | 208.3 | 87.8 | −58 % |
| ascii-1-large (1 KB) | 2367.6 | 1493.5 | −37 % |
| blob+int (control, no string) | 41.8 | 41.1 | flat |

(The `unicode-1` cross-shape reading is the same exp 179 GC-contamination
artifact, by construction — the unicode fallback path is byte-for-byte
the original implementation.)

### Release suite A/B

Suite ran 5 repeats/side, candidate-vs-baseline-for-exp186. Headline:
**3 wins / 2 regressions / 164 neutral**. The two flagged regressions
do not touch the changed code:

- **Batched Write Inside Transaction (100 rows)**: +44 % on a 0.37 →
  0.53 ms lane with 18.8 % CV (`moderate`). The sibling 1000-row
  variant moves −10 % (5 % CV) on the same change, so the small-lane
  flag is the classic phase-ordered noise on a sub-ms metric. Code-path
  wise, `tx.executeBatch` routes to `allocateBatchParams` (untouched
  by this change), not `allocateParams`, so the encoder cannot
  mechanistically produce a +44 % batch-tx regression.
- **Streaming (Column Granularity) re-emit counts** (+473 / +174):
  these are invalidation-count comparisons, not timing — sensitive
  to write-coalescing timing (exp 180) and stream invalidation logic
  (exp 160 in-flight). The encoder change does not touch the writer
  invalidation harvest or stream dispatch.

Small-payload single-row binds that exp 179 measured flat stay flat
here too (Parameterized Queries, Single Inserts, Concurrent Single
Inserts all neutral), confirming exp 179's small-bind finding still
stands — the encoder is invisible until the payload lifts it above
the round-trip floor.

Full results file:
`benchmark/results/2026-06-18T07-48-46-exp186-single-row-large-text-bind.md`.

## Decision

**Accepted.** The exp 179 encoder mechanism is materially beneficial
once the bound text crosses the mid-tens-of-KB range, where the
`utf8.encode()` allocation and `setRange()` copy start to dominate the
per-write isolate round-trip floor. The candidate saves one
`Uint8List` allocation + one byte-buffer copy per ASCII string param;
on the 1 MB shape that is ~1 MB of avoided allocation + memcpy per
write, which is now measurable end-to-end (-27 % / −29 % across the
two passes).

This sharpens exp 179's conclusion rather than overturning it: small
single-row binds remain at the noise floor (exp 179's release-suite
finding stands), but as soon as a representative payload lifts the
encoder above the round-trip floor — exactly the revisit condition
exp 179 named — the direct-ASCII path is the right default for the
single-row path too, matching the batch fast path (exp 125/149/150).

Behavior is preserved: integers/doubles/blobs/nulls/embedded-NUL ASCII
text are byte-identical, and non-ASCII strings still route through
`_allocateParamsPreEncoded` (the original encoder, factored out as the
fallback), so Unicode bind paths are unchanged.

### Future notes

- The focused harness (`single_row_large_text_bind.dart`) is retained
  as the durable workload for any future bind-path change that targets
  large single-row text.
- If a future change rewrites the bind protocol again, the 1 MB shape
  is the load-bearing acceptance gate: it is where the encoder
  dominates wall by ~25–30 %, so any rewrite that does not match the
  current numbers there is a regression.
- Long-payload non-ASCII single-row binds are still untested at scale;
  if a UTF-8-heavy workload (e.g. CJK chat) makes the fallback path
  hot, exp 126's direct-UTF-8 batch writer is the natural template to
  extend.
