# Experiment 099: 8-byte-chunked FNV for byte-stream cells

**Date:** 2026-04-25
**Status:** Rejected

## Problem

`fnv_combine_bytes` in [native/resqlite.c](../native/resqlite.c) hashes TEXT
and BLOB cell payloads one byte at a time during stream change detection
(`resqlite_query_hash`, exp 075). For long string columns the per-byte
xor + multiply chain is the dominant cost of the unchanged-fanout
fast-path: with N input bytes we pay N FNV rounds.

The integer-cell path already folds 8 bytes per multiply (it XORs the
full `int64` directly into the accumulator). The byte-stream path was
the only one still in the per-byte regime.

## Hypothesis

Switching `fnv_combine_bytes` to a SWAR-style 8-bytes-per-multiply main
loop with a per-byte tail should reduce the cost of unchanged hash
walks proportional to text-cell length, with no semantic change for
short cells and a measurable win on long-text streams.

The hash crosses no isolate boundary and never persists — `lastResultHash`
lives only in `StreamEntry` in-memory. So a hash-bit-pattern change is
safe: producer (initial query) and consumer (selectIfChanged) are always
the same algorithm version inside one process lifetime.

## Approach

Replaced the byte loop with a chunked main loop:

```c
while (i + 8 <= len) {
    uint64_t word;
    memcpy(&word, b + i, 8);
    h ^= word;
    h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
    i += 8;
}
for (; i < len; i++) {
    h ^= (uint64_t)b[i];
    h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
}
```

`memcpy(&word, b+i, 8)` is the standard idiom for unaligned 8-byte
load — clang/gcc compile it to a single `mov` on x86-64 / `ldr` on
arm64, avoiding strict-aliasing UB.

For cells shorter than 8 bytes the main loop is skipped entirely and
the tail produces bit-for-bit identical hashes to the original
implementation. So short-string workloads are unaffected by definition.

206 existing tests pass (`dart test`).

## Results

Artifact: [`benchmark/results/2026-04-25T07-21-19-exp099-fnv-8byte.md`](../benchmark/results/2026-04-25T07-21-19-exp099-fnv-8byte.md)

Baseline: `2026-04-23T19-38-11-exp097-one-pass-initial-stream-hash.md`

The change is benchmark-invisible on this suite:

| Workload | Baseline (ms) | Experiment (ms) | Status |
|---|---:|---:|---|
| Streaming / Unchanged Fanout Throughput | 0.19 | 0.25 | ⚪ Within noise (±37% / ±0.20 ms MDE) |
| Streaming / Fan-out (10 streams) | 0.20 | 0.25 | ⚪ Within noise (±54% MDE) |
| Streaming / Initial Emission | 0.03 | 0.03 | ⚪ Within noise |
| Streaming / Invalidation Latency | 0.04 | 0.05 | ⚪ Within noise |

Suite-level: **6 wins, 4 regressions, 143 neutral** — every flagged
delta sits inside its noise envelope. The two flagged Column-Granularity
deltas (`Overlapping -510` and `Disjoint +128`) cannot be attributable
to this change: those benchmarks use 2–3 character column values
(`v$i`, `z$i`) that are <8 bytes and therefore route entirely through
the unchanged tail loop. The deltas are run-to-run variance.

The Concurrent Reads `4×` win (-53%) and `8×` regression (+18%) are
paired anti-correlated outliers in the same suite — symptomatic of
per-run scheduler jitter, not the FNV change (concurrent reads do not
exercise the hash path at all).

## Why Rejected

The current streaming benchmarks don't carry any cell long enough to
exercise the 8-byte main loop:

- Unchanged Fanout writes `value` strings ≤ 8 chars
- Column Granularity writes `v$i` / `z$i` (2–3 chars)
- Chat Sim and Feed Paging hash mostly integer PKs and short metadata

For the hash path, the inputs are short enough that the new main loop
is structurally never entered, and the tail loop is identical to the
old code. There is no measurable win to bank, and adding the chunked
path costs ~10 lines of C plus an `endianness-dependent hash`
documentation line for any future maintainer (the bit pattern depends
on host byte order, which is fine for in-process use but needs to be
called out if someone ever tries to persist the hash).

This is the same class of "structurally sound but unmeasurable on
current workloads" rejection as exp 071 (MRU-first stmt cache scan).
Worth revisiting if a future benchmark exercises long TEXT/BLOB cells
on the unchanged-fanout fast-path — the change-detection win would then
scale linearly with cell size.

## Decision

Rejected. The optimization is correct and would help long-text streams,
but the present benchmark suite has no workload that lights it up, so
there is no signal to commit against. Revisit when a long-text streaming
benchmark exists, or as part of a broader hash-throughput effort.
