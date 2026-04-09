# Experiment 029: Periodic PASSIVE Checkpointing

**Date:** 2026-04-08
**Status:** Accepted
**Commit:** [`8822bd2`](https://github.com/danReynolds/dune/commit/8822bd2)

## Hypothesis

The current writer policy uses:

- `wal_autocheckpoint = 10000`
- `journal_size_limit = 64MB`

That is a good default, but it still leaves checkpoint timing entirely to SQLite.
If checkpoints happen at unlucky commit boundaries, burst workloads can still see
tail-latency spikes.

A coarse manual policy might do better:
- disable autocheckpoint on the writer
- run `PRAGMA wal_checkpoint(PASSIVE)` periodically during the burst

If even that crude policy improves p95/p99 write latency, a built-in smarter
checkpoint scheduler becomes worth considering.

## Change

Added an experiment-only benchmark:

- `benchmark/experiments/checkpoint_policy.dart`

It compares two policies on a burst of 6000 single-row inserts with an 8KB text
payload:

1. **Baseline**: legacy SQLite autocheckpoint (`wal_autocheckpoint=10000`)
2. **Manual**: `wal_autocheckpoint=0` plus `PRAGMA wal_checkpoint(PASSIVE)` every
   500 writes

Measured:
- write p50 / p95 / p99 / max
- periodic read p95 during the burst
- checkpoint p95 for the manual policy
- final `PRAGMA wal_checkpoint(NOOP)` state

## Results

| Policy | Write p50 | Write p95 | Write p99 | Write max | Read p95 | Checkpoint p95 | WAL noop |
|---|---:|---:|---:|---:|---:|---:|---|
| baseline-autocheckpoint-10000 | 0.06ms | 0.12ms | 0.22ms | 53.60ms | 0.24ms | n/a | `busy=0 log=4752 ckpt=0` |
| manual-passive-every-500 | 0.05ms | 0.08ms | 0.12ms | 9.27ms | 0.19ms | 11.26ms | `busy=0 log=2062 ckpt=2062` |

This is the first checkpoint-oriented experiment with clearly non-noisy signal:
- lower p95
- lower p99
- dramatically lower max write latency
- slightly better concurrent read latency during the burst

The trade-off is explicit checkpoint work (`11.26ms` p95 on checkpoint calls), but
that work is happening at predictable intervals instead of surfacing as a 53ms
write outlier.

## Decision

**Accepted**.

This does not justify shipping `PRAGMA wal_checkpoint(PASSIVE)` calls from the
Dart layer as-is. The adopted implementation instead moved checkpoint scheduling
into the writer connection via a lower-level WAL hook.

Compared with the earlier `wal_autocheckpoint` tuning experiment, this is the
first result that makes the scheduler itself look worth deeper implementation.
