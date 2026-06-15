# Exp 173 - 32 KB long-text streaming benchmark + 16-byte FNV fold

Date: 2026-06-15

Focused benchmark:

```bash
dart run benchmark/experiments/long_text_32kb_hash.dart
```

The benchmark seeds a real resqlite database with 64 rows × 32 KB ASCII TEXT,
registers 8 unchanged streams and 1 changed barrier stream, and then times one
write per round. The unchanged streams must not emit (their predicate
excludes the new row); the barrier stream's second emission proves the rerun
wave has reached the main isolate so the stopwatch can stop. Two warmup
rounds, nine measured rounds, fresh DB per round.

## Candidate

The discarded candidate replaced the 8-byte body of `fnv_combine_bytes` in
`native/resqlite.c` with an unrolled 16-byte body — two unaligned 8-byte
loads per iteration, feeding the same serial xor-mul chain. The 8-byte
body remained as the tail for inputs of length 8..15, and the unaligned
0..7 byte tail was unchanged. The final hash bit pattern is identical
between the two bodies for every input.

## Pair 1 — candidate first

| Round | 8-byte body (ms) | 16-byte body (ms) |
|---|---:|---:|
| 0 | 2.655 | 3.079 |
| 1 | 5.219 | 5.825 |
| 2 | 2.642 | 3.205 |
| 3 | 3.257 | 3.023 |
| 4 | 4.950 | 5.306 |
| 5 | 2.830 | 2.773 |
| 6 | 2.634 | 2.695 |
| 7 | 5.379 | 5.391 |
| 8 | 3.067 | 3.441 |

Run-median summary:

| Metric | 8-byte | 16-byte |
|---|---:|---:|
| Median | 3.067 ms | 3.205 ms |
| p90    | 5.379 ms | 5.825 ms |
| Min    | 2.634 ms | 2.695 ms |
| Max    | 5.379 ms | 5.825 ms |

Delta on median: **+4.5 % (slower)**.

## Pair 2 — baseline first (order flipped per JOURNAL.md)

| Round | 8-byte body (ms) | 16-byte body (ms) |
|---|---:|---:|
| 0 | 2.639 | 2.562 |
| 1 | 6.043 | 5.217 |
| 2 | 2.651 | 2.639 |
| 3 | 3.232 | 3.168 |
| 4 | 5.236 | 5.868 |
| 5 | 2.636 | 3.419 |
| 6 | 2.685 | 3.054 |
| 7 | 5.533 | 6.035 |
| 8 | 2.863 | 3.209 |

Run-median summary:

| Metric | 8-byte | 16-byte |
|---|---:|---:|
| Median | 2.863 ms | 3.209 ms |
| p90    | 6.043 ms | 6.035 ms |
| Min    | 2.636 ms | 2.562 ms |
| Max    | 6.043 ms | 6.035 ms |

Delta on median: **+12.1 % (slower)**.

## Reading the numbers

Each pass's spread is roughly 2.6 → 6.0 ms, a factor of ~2.3×. The candidate
medians sit slightly above the baseline medians on both passes, but each
pass's signal is well inside its own variance. The order flip did not
flip the sign of the delta, so the slight regression is not a pure
phase-drift artifact — it just isn't a real signal either.

Why so little headroom: the production reader pool is sized at
`min(numCores - 1, 4)`, so on a 4-worker fleet each worker hashes roughly
2 streams × 2 MB = 4 MB per burst. At ≈3 ns / 8-byte fold that's ≈1.5 ms
of hash work per worker. The observed median wall is ≈3 ms, so the
byte-stream fold is at most ~50 % of wall, and the 16-byte fold can
only attack the loop-control portion of that. A generous 10 % hash-loop
saving collapses to ≈5 % wall — under the run-to-run spread this
benchmark exhibits.

## Outcome

Rejected — "premise refuted" escape hatch from `RUNNER_INSTRUCTIONS.md`.

`native/resqlite.c`'s `fnv_combine_bytes` was reverted to the exp 110
8-byte body. The 32 KB benchmark itself is the durable contribution: the
release-suite `Long-Text 32KB Unchanged Fanout` row in
`benchmark/suites/streaming.dart` and the focused
`benchmark/experiments/long_text_32kb_hash.dart` harness remain, plus the
new curated metric in `benchmark/shared/workload_registry.dart` so future
hash recheck experiments can compare against this lane without
rebuilding the workload.
