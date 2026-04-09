# Experiment 033: FNV-1a Hash for Result Change Detection

**Date:** 2026-04-09
**Status:** Accepted

## Change

Replaced `Object.hash(hash, value)` with FNV-1a 64-bit hash for stream result
change detection. Created shared `result_hash.dart` module imported by both
`read_worker.dart` (worker-side hash) and `stream_engine.dart` (main-side hash)
to ensure one source of truth.

FNV-1a uses a single multiply + XOR per element vs Object.hash's Jenkins hash
which operates on 29-bit values with more operations per combine step.

## Results

Part of cumulative -11% stream invalidation improvement. No isolated signal
due to the hash being a small fraction of total query time.

## Decision

**Accepted** — shared module eliminates the divergence risk of having two
independent hash implementations. FNV-1a has better avalanche properties
than the 29-bit Jenkins hash used by Object.hash.
