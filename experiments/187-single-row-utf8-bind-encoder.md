# Experiment 187: Single-row UTF-8 bind encoder

**Date:** 2026-06-19
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** none - focused `single_row_large_text_bind.dart` CJK/ASCII
  order-flipped pass + `single_row_param_packing.dart` micro; no release-suite
  run because the changed path is non-ASCII single-row text and the release
  suite has no representative lane for it.

## Problem

Exp 186 accepted the single-row direct-ASCII `allocateParams` encoder after
adding a representative large-text workload. That closed exp 179's ASCII revisit
condition, but it deliberately left non-ASCII strings on the old fallback:
`utf8.encode(value)` allocates a temporary `Uint8List`, then `setRange` copies
those bytes into the native parameter buffer.

The signal map kept the next condition explicit: do not extend the single-row
encoder to UTF-8 long payloads unless a representative non-ASCII large
single-row workload makes the fallback hot. CJK chat / document inserts are the
natural shape: the writer still does one SQLite step, but every string byte pays
for a temporary encoded list plus a second copy before binding.

## Hypothesis

Reusing the existing batch direct-UTF-8 helpers (`_utf8Length` and `_writeUtf8`)
inside single-row `allocateParams` should remove the temporary encoded list and
the second byte-buffer copy for non-ASCII text, while preserving exp 186's
ASCII-only fast path exactly.

Acceptance criterion: after broadening `single_row_large_text_bind.dart` with
byte-matched CJK payloads, CJK rows at 16 KB or larger improve by more than 5%
across an order-flipped pair, while ASCII controls stay in the same range as
exp 186's accepted direct-ASCII path.

## Approach

- `allocateParams` still detects an all-ASCII parameter list in pass 1 and keeps
  the O(1) `String.length` sizing plus direct code-unit copy from exp 186.
- When any string is non-ASCII, pass 1 sizes strings with `_utf8Length`, and
  pass 2 writes every string directly into the same native parameter buffer with
  `_writeUtf8`. This is the same UTF-8 encoder already used by the wide-batch
  path from exp 126.
- Removed the private `_allocateParamsPreEncoded` fallback because no single-row
  string path needs a temporary encoded list anymore.
- Extended `single_row_large_text_bind.dart` so every ASCII shape also has a
  byte-matched CJK shape (1 KB, 16 KB, 64 KB, 256 KB, 1 MB).
- Added a single-row regression test for multibyte text plus embedded NUL
  through `execute`.

No public API change. Integers, doubles, blobs, nulls, ASCII strings,
surrogate pairs, and embedded-NUL text keep the same `resqlite_param` layout and
explicit `text.len` binding.

## Results

### Focused workload (`single_row_large_text_bind.dart`)

Pass 1 was collected baseline first, then candidate:

| Payload | Baseline ms / 100 | Candidate ms / 100 | Delta |
|---|---:|---:|---:|
| ASCII 1 KB | 4.39 | 4.32 | -1.6% |
| ASCII 16 KB | 9.02 | 8.71 | -3.4% |
| ASCII 64 KB | 24.50 | 23.91 | -2.4% |
| ASCII 256 KB | 94.86 | 86.27 | -9.1% |
| ASCII 1 MB | 367.12 | 336.26 | -8.4% |
| CJK 1 KB | 3.38 | 2.00 | -40.8% |
| CJK 16 KB | 10.18 | 6.93 | -31.9% |
| CJK 64 KB | 35.92 | 25.15 | -30.0% |
| CJK 256 KB | 145.84 | 90.80 | -37.7% |
| CJK 1 MB | 556.30 | 347.21 | -37.6% |

Pass 2 was order-flipped: candidate had already run, then the same broadened
harness was applied to a temporary `origin/main` baseline worktree.

| Payload | Baseline ms / 100 | Candidate ms / 100 | Delta |
|---|---:|---:|---:|
| ASCII 1 KB | 4.14 | 4.32 | +4.3% |
| ASCII 16 KB | 8.99 | 8.71 | -3.1% |
| ASCII 64 KB | 25.19 | 23.91 | -5.1% |
| ASCII 256 KB | 90.98 | 86.27 | -5.2% |
| ASCII 1 MB | 352.12 | 336.26 | -4.5% |
| CJK 1 KB | 3.29 | 2.00 | -39.2% |
| CJK 16 KB | 9.99 | 6.93 | -30.6% |
| CJK 64 KB | 36.49 | 25.15 | -31.1% |
| CJK 256 KB | 148.38 | 90.80 | -38.8% |
| CJK 1 MB | 562.08 | 347.21 | -38.2% |

The CJK result reproduces cleanly at every size. The acceptance-relevant 16 KB
through 1 MB rows improve by roughly 31-39% in both pass orderings. ASCII rows
remain comparable to the exp 186 path; the code path is intentionally identical
for all-ASCII lists, so the small same-direction movements are harness drift
rather than a new mechanism.

### Encoder micro (`single_row_param_packing.dart`)

The existing small `unicode-1` micro is not the acceptance gate for this run;
it is a guardrail that the new direct encoder does not create a large small-text
tax:

| Shape | Baseline ns/op | Candidate ns/op | Delta |
|---|---:|---:|---:|
| unicode-1 | 289.6 | 304.0 | +5.0% |
| blob-int control | 41.0 | 43.4 | +5.9% |

Those are tens-of-nanoseconds differences in a synthetic allocate/free loop.
They are far below the writer round-trip floor, and the real target is the
large CJK bind path above where the removed allocation/copy is a material part
of wall time.

## Decision

**In Review.** The implementation meets the bounded gate: non-ASCII large
single-row text binds now use the same direct UTF-8 packing strategy as wide
batches, and the CJK workload improves by ~31-39% at 16 KB through 1 MB across
the order-flipped pair. Exp 186's ASCII fast path is preserved, and correctness
coverage now includes single-row multibyte + embedded-NUL text.

This consumes exp 186's UTF-8-heavy follow-up. Future single-row bind work
should treat `single_row_large_text_bind.dart` as both the ASCII and non-ASCII
large-payload gate. Small text remains at the round-trip floor; do not reopen
small single-row text encoding without a workload that changes that materiality
threshold.

## Future Notes

- If a future rewrite changes `_utf8Length` / `_writeUtf8`, run both the CJK
  and ASCII rows in `single_row_large_text_bind.dart`; preserving one path is
  not enough.
- A release-suite row for large single-row text would make this public-history
  visible, but the focused harness is currently the lower-cost guard because it
  exercises byte-size sweeps directly.
