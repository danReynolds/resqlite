# Experiment 032: Completer.sync in Pool Dispatch

**Date:** 2026-04-09
**Status:** Accepted

## Change

Replaced `Completer<T>()` with `Completer<T>.sync()` in reader_pool.dart for
the per-request completer, the worker available notification, and the spawn
handshake. Sync completers fire synchronously instead of scheduling a microtask.

## Results

No isolated signal in aggregate benchmarks (expected — saves ~1 microtask per
query, which is ~10-50µs). Part of the cumulative +17% point query improvement.

## Decision

**Accepted** — one-word change, zero risk. Eliminates unnecessary microtask
scheduling on every query response.
