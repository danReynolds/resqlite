# Experiment 138: Blob-heavy Batch Parameter Shape Audit

**Date:** 2026-05-16
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`, `measurement-system`

## Problem

After [exp 125](125-wide-ascii-batch-params.md) and
[exp 126](126-wide-utf8-batch-packing.md) extracted per-string
`utf8.encode` and the temporary `Uint8List` it allocates from the
wide-batch parameter encoder, the
`parameter-encoding-and-binding` direction left one open question on
the books in `signals.json`:

> Are there remaining blob-heavy parameter shapes where encoding, not
> SQLite stepping, dominates?

Static reading of `_allocatePackedBatchParams` in
`lib/src/native/resqlite_bindings.dart` is suggestive but not
conclusive. For `Uint8List` values the encoder writes the caller's
bytes directly into the inline parameter buffer with
`view.setRange(dataOffset, dataOffset + value.length, value)` — no
temporary allocation comparable to the per-string `utf8.encode` calls
that exp 125 / 126 removed. SQLite still pays for `bind_blob` +
`step` + WAL writes per row. The question is whether that ratio
leaves a removable Dart-side cost.

The existing focused harness
(`benchmark/experiments/batch_param_flatten.dart`) ships a fixed
25%/25%/25%/25% TEXT/INT/REAL/BLOB cell mix with a 4-byte blob in
every blob column. That is not enough to answer the blob question:
the BLOB total payload is small compared to the TEXT total even at
the widest shape, so blob encoding cost is masked.

## Hypothesis

Wide BLOB-heavy batches do not have removable Dart-side encoding
cost. Because the existing matrix encoder writes user-supplied
`Uint8List` directly into the inline parameter buffer, per-byte wall
time should converge to the SQLite stepping / WAL-write band as
blob size grows. Per-row overhead (struct write, `bind_blob`
dispatch, `step`) should dominate for tiny blobs and become
proportionally smaller at larger blob sizes — the opposite of a
"remove allocation" signature, where small payloads benefit most.

Accept this as a measurement experiment if:

- A focused blob-size sweep is wired into the existing
  `batch_param_flatten.dart` benchmark so future runs can reproduce
  this audit without re-deriving the workload;
- Wall scaling with payload bytes converges to a stable per-byte band
  (i.e., per-byte throughput plateaus rather than improving with
  larger blobs);
- The result either confirms "no removable encoding cost on blob path"
  and lets the corresponding `openQuestion` in `signals.json` be
  closed, or surfaces a specific gap.

## Approach

Extend `batch_param_flatten.dart` with two options:

- `--cell-mode=mixed|blob` (default `mixed`, preserving exp 113 / 125
  / 126 calibration). `blob` makes every column a `BLOB` and every
  value a `Uint8List`.
- `--blob-size=N` (default `4`). When `--cell-mode=blob`, every cell
  is a deterministic `Uint8List` of `N` bytes. Content varies by row
  and column so SQLite cannot collapse identical values into a
  shared cached representation, which would understate per-row
  encoding cost.

The mixed-mode behavior is unchanged so prior baselines and CI runs
keep their existing reading.

Run a single-pass sweep at:

- shapes: `{100, 1000, 10000}` rows × `{2, 8, 20}` params,
- blob sizes: `4, 64, 256, 1024, 4096` bytes,
- 30 iterations per shape (15 for the 4 KB / 10k × 20 case where
  total wall exceeds 1 minute).

Capture p50 wall and compute payload bytes / wall to get an effective
throughput band. Compare against the mixed-mode baseline at each
shape, and against exp 125 / 126's published wide-text throughputs at
the 10k × 20 shape.

## Results

Full table in
[`benchmark/profile/results/exp-138-blob-param-shape-aggregate.md`](../benchmark/profile/results/exp-138-blob-param-shape-aggregate.md).

Headline rows (p50 wall in ms):

| shape | mixed | blob 4B | blob 64B | blob 256B | blob 1024B |
|---|---:|---:|---:|---:|---:|
| 10000 rows × 20 params | 12.297 | 17.055 | 93.170 | 240.479 | 1335.526 |
| 10000 rows × 8 params | 6.503 | 9.011 | 26.297 | 146.825 | 417.401 |
| 1000 rows × 20 params | 1.149 | 1.638 | 2.915 | 18.361 | 69.791 |

Per-byte throughput at the 10k × 20 wide shape:

| blob size | total payload | p50 (ms) | throughput |
|---|---:|---:|---:|
| 4 B | 800 KB | 17.055 | 47 MB/s |
| 64 B | 12.8 MB | 93.170 | 137 MB/s |
| 256 B | 51.2 MB | 240.479 | 213 MB/s |
| 1024 B | 204.8 MB | 1335.526 | 153 MB/s |

Comparison against exp 125 / 126 wide-text shapes at the same 10k ×
20 wide width (one cell per column, all cells of the named type):

| variant | total payload | p50 (ms) | throughput | source |
|---|---:|---:|---:|---|
| ASCII (~12 B / cell) | ~2.4 MB | 12.760 | 188 MB/s | exp 125 |
| Unicode (~22 B / cell) | ~4.4 MB | 18.988 | 232 MB/s | exp 126 |
| Emoji (~26 B / cell) | ~5.2 MB | 17.458 | 298 MB/s | exp 126 |
| Blob 64 B | 12.8 MB | 93.170 | 137 MB/s | exp 138 |
| Blob 256 B | 51.2 MB | 240.479 | 213 MB/s | exp 138 |
| Blob 1024 B | 204.8 MB | 1335.526 | 153 MB/s | exp 138 |

The blob and text paths land in the same 137–298 MB/s throughput band
once total payload exceeds ~5 MB. Strings additionally benefit from
exp 125 / 126's allocation removal at the smaller end of the band;
blobs already use the direct-write path so their per-byte cost cannot
be reduced without changing SQLite-side work.

Tiny blobs (4 B) sit at 47 MB/s on the wide shape because they are
per-row-overhead-dominated — the same regime where mixed-mode lives
(12.297 ms at 10k × 20). Increasing per-row payload past 64 B amortizes
the per-row overhead and reveals the SQLite-stepping band.

## Decision

**Accept for review — measurement.**

The blob-mode sweep ships with the focused harness so future
`parameter-encoding-and-binding` work can re-evaluate any blob-shape
hypothesis without re-deriving the workload. The audit closes the
`parameter-encoding-and-binding` `openQuestion` it targets: there is
no removable Dart-side blob encoding cost in the current matrix
encoder. The `view.setRange(...)` direct write is already the
minimum amount of work needed to land the user's `Uint8List` in the
native parameter buffer; further savings would require changing
SQLite-side work (`bind_blob`, page writes, WAL frames), which is
out of scope for this direction.

This is consistent with the JOURNAL lesson "Filling a measurement
gap can still produce a rejection — and that's a stronger result":
the benchmark mode is the durable contribution; the implementation
candidate is rejected by direct measurement rather than analogy.

`signals.json#parameter-encoding-and-binding.openQuestions` drops
the blob-heavy-encoding entry. The matching candidate area in the
direction's `currentRead` is updated to call out exp 138 as the
authoritative answer.

## Future Notes

Do not retry blob-shape allocation removal experiments without a new
signal. The encoder's blob path has no removable allocation per cell;
the `Uint8List` the caller supplies is the same buffer SQLite reads
from. Revisit only if:

- a workload surfaces a *blob-specific* cost that is not present in
  text shapes (e.g. blob pinning, mass copying for a JOIN, blob
  page-cache invalidation, etc.), OR
- a SQLite release changes `bind_blob` or the blob page-write path
  in a way that breaks the current SQLite-bound throughput band.

Compare any future blob-encoder change against exp 138's per-byte
throughput band at the same shape; a candidate that improves the
4 B and 64 B rows but stays flat on the 256 B+ rows is per-row
overhead removal, not encoding removal — useful, but should be
labeled correctly so future readers do not conflate it with the
exp 125 / 126 wide-string allocation wins.
