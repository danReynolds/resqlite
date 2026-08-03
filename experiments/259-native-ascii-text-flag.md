# Experiment 259: Classify TEXT cells as ASCII in the native step loop

**Date:** 2026-08-03
**Status:** Accepted
**Category:** Performance
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused AOT A/B, no release run;
  [`benchmark/experiments/select_rows_text_decode.dart`](../benchmark/experiments/select_rows_text_decode.dart),
  results in
  [`benchmark/results/2026-08-03T11-05-00Z-exp259-native-ascii-text-flag.md`](../benchmark/results/2026-08-03T11-05-00Z-exp259-native-ascii-text-flag.md)

## Problem

`decodeQuery` cannot turn a TEXT cell into a Dart `String` until it knows
whether the payload is pure ASCII. If it is, `String.fromCharCodes` widens the
bytes into a `OneByteString` directly; if it is not, the cell needs
`utf8.decode`. Getting that wrong is not a crash — it is silent mojibake — so
the check is unavoidable.

Today the decoder answers the question itself, in `fastDecodeText`:

```dart
final list = ptr.asTypedList(len);
if (len >= 16 && ptr.address & 7 == 0) {
  final words = ptr.cast<ffi.Int64>().asTypedList(len >> 3);
  for (var i = 0; i < words.length; i++) {
    if (words[i] & asciiMask != 0) return utf8.decode(list);
  }
  ...
} else {
  for (var i = 0; i < len; i++) {
    if (list[i] >= 0x80) return utf8.decode(list);
  }
}
return String.fromCharCodes(list);
```

Three costs ride along, per TEXT cell:

1. A second `ExternalTypedData` object for the `Int64` word view, on top of the
   `Uint8List` view the string constructor needs anyway.
2. A bounds-checked Dart loop over the payload.
3. For anything under 16 bytes — or on the rare unaligned pointer — the
   word-at-a-time path is skipped entirely and the scan runs **byte by byte**.
   Short values are the common database shape: ids, names, categories, ISO
   timestamps.

Meanwhile `resqlite_step_row` already holds the payload pointer and length one
frame earlier, in C, where the same question is a branch-free SWAR pass over
bytes that are already in cache from the value fetch.

Exp 251 measured Dart-side result construction at 34-58% of observed `select()`
latency depending on row shape, and found the mixed row *result-construction
heavy* (63% of worker wall). This is a concrete, bounded slice of that: not a
storage-shape rewrite (exp 258 closed that), just moving one classification
across a boundary it was on the wrong side of.

## Hypothesis

Answering "is this TEXT ASCII?" in `resqlite_step_row` and reporting it as a
distinct cell type code will remove one allocation and one scan per TEXT cell
from the Dart decoder, for a per-cell saving large enough to show up on
text-bearing `select()` lanes. Integer-only reads should be untouched, and
non-ASCII reads should be no worse — the C scan replaces a Dart scan that was
running anyway.

## Approach

`resqlite.h` defines `RESQLITE_TEXT_ASCII` as `6`. SQLite's own type codes
occupy 1-5, so 6 is the first free value and keeps the decoder's switch dense.

`resqlite.c` gains `text_is_ascii`, an accumulate-then-test SWAR scan:

```c
RESQLITE_HOT static int text_is_ascii(const unsigned char* p, int len) {
    uint64_t acc = 0;
    int i = 0;
    for (; i + 8 <= len; i += 8) {
        uint64_t word;
        memcpy(&word, p + i, 8);
        acc |= word;
    }
    for (; i < len; i++) acc |= (uint64_t)p[i];
    return (acc & 0x8080808080808080ULL) == 0;
}
```

Loads go through `memcpy` because SQLite makes no alignment promise for TEXT
payloads — which is also why the Dart side had an alignment guard it could not
drop. The scan deliberately runs to the end rather than stopping at the first
high byte: that keeps a single branch on the common all-ASCII path, and a
non-ASCII value is about to be walked again by `utf8.decode` anyway, at roughly
ten times the per-byte cost. The `text8-cjk` lane exists to hold that trade
honest.

Both `resqlite_step_row` and `resqlite_step_row_hash` call it and overwrite
`cells[i].type` with `RESQLITE_TEXT_ASCII` when it answers yes.

The stream hash is untouched. `resqlite_step_row_hash` folds the *local* `type`
from `sqlite3_value_type` into the accumulator before the switch runs, so the
canonical digest still sees `SQLITE_TEXT` and stays byte-identical to what
`resqlite_query_hash` produces on the rerun path. That equality is what exp 228
made load-bearing, and breaking it would silently re-emit every stream.

On the Dart side `decodeQuery` and `decodeQueryWithInitialHash` split the TEXT
arm in two: `sqliteTextAscii` does `String.fromCharCodes` on the single view it
already needs, and `sqliteText` — now only reachable when the native scan found
a byte at or above `0x80` — goes straight to `utf8.decode` with no scan of its
own. Zero-length text always classifies as ASCII, so the empty-string guard
lives only on the fast arm.

`fastDecodeText` stays, unchanged, for column names in `_schemaFor`: those come
from `sqlite3_column_name`, not from the cell buffer, so there is no native
classification to inherit.

### Safety

- `resqlite_test_text_is_ascii` exports the classifier for a differential test
  (the `resqlite_test_i64_to_str` pattern from exp 231). A wrong `1` is silent
  corruption, so it gets a direct byte-level gate: a high byte at every position
  of every length 0-40, the `0x7F`/`0x80` boundary at every word edge, real
  UTF-8 payloads, and a 20k-case sparse-high-byte fuzz.
- `test/database_test.dart` adds an end-to-end round trip that inserts every
  string of length 0-20 with a `é` or `🎉` at every offset and reads them back
  through `select()`, covering the wiring as well as the classifier.

## Results

Two order-flipped passes, fresh AOT process per arm, 31 samples per lane.
Full table in the results file; p50 deltas:

| lane | pass 1 | pass 2 | verdict |
|---|---:|---:|---|
| `text8-short` (10k x 8, 10 B ASCII) | -12.3% | -10.4% | REPRODUCED |
| `text8-mid` (10k x 8, 40 B ASCII) | -14.3% | -10.7% | REPRODUCED |
| `text4-long` (2k x 4, 400 B ASCII) | -22.2% | -19.4% | REPRODUCED |
| `mixed6` (10k x 6 default shape) | -7.8% | -7.8% | REPRODUCED |
| `text8-cjk` (guard) | -2.4% | -1.7% | neutral |
| `int8` (control) | +0.2% | -2.9% | neutral |

Verdicts are `benchmark/ab_drift_check.dart`'s.

Reading them: a text-bearing `select()` gets **10-22% faster end to end**, and
the default six-column product row — two thirds of which is not text at all —
still improves a reproduced 7.8% in both orderings. The saving is per TEXT cell,
so it scales with how much text a read carries, not with row count alone; the
400 B lane gains most because the Dart scan it replaces was walking 50 words per
cell.

The two neutral lanes are what make the win believable. `int8` has no TEXT, so
both binaries execute identical code there — it moves +0.2% then -2.9%, opposite
signs and inside the 3% floor, which rules out the systematic per-worktree binary
offset that invalidated exp 254's first comparison. And `text8-cjk` confirms the
full-scan trade costs nothing measurable: non-ASCII reads land at -2.4% / -1.7%,
if anything slightly better than before, because the C scan it gained is cheaper
than the partial Dart scan it lost.

A standalone microbenchmark of the mechanism alone puts the per-cell saving at
6-15 ns, or 12-49% of `fastDecodeText`'s wall depending on payload width — which
at 80k TEXT cells per lane is 0.5-1.2 ms, the right order of magnitude for the
end-to-end deltas.

## Outcome

**Accepted.** A byte-identical-output change that moves one per-cell
classification from Dart to the C step loop, worth 10-22% on text-bearing
`select()` reads and 7.8% on the default row shape, with an untouched stream
hash and no public API change.

The direction this leaves open: the same argument applies to any per-cell
question the decoder currently asks in Dart while C holds the answer one frame
earlier. It does **not** reopen the broad columnar/storage rewrites — exp 258
and exp 251 closed those on their own evidence, and this win is orthogonal to
both, since it removes work rather than moving it between isolates.

Would revisit if a future Dart runtime gives `String.fromCharCodes` a native
UTF-8 entry point that makes the ASCII/UTF-8 split unnecessary, or if
`Pointer.asTypedList` stops allocating — at which point the remaining Dart-side
cost is just the string copy and the classification would be worth re-timing.

## Test plan

- `dart analyze --fatal-infos lib/ test/ benchmark/experiments/select_rows_text_decode.dart` — clean
  (the 77 pre-existing `benchmark/drift/*` codegen errors are unchanged from
  `origin/main`)
- `dart test test/native_encoder_diff_test.dart -n "exp 259"` — 4 groups, classifier
  differential + fuzz
- `dart test test/database_test.dart` — including the new every-offset multibyte
  round trip
- `dart test test/query_decoder_test.dart test/stream_test.dart test/transaction_test.dart
  test/select_bytes_transfer_test.dart test/stream_dependency_shapes_test.dart
  test/write_coalescing_test.dart` — 160 tests green
- focused A/B, both orders, with control and guard lanes;
  `benchmark/ab_drift_check.dart` verdicts above
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/259-native-ascii-text-flag.md`
