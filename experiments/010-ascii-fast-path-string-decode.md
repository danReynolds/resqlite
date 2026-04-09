# Experiment 010: ASCII Fast-Path for String Decoding

**Date:** 2026-04-06
**Status:** Rejected

## Problem

`utf8.decode` is called for every text column value. Most database strings are ASCII. Could an ASCII fast-path (`String.fromCharCodes` for all-ASCII bytes) avoid the UTF-8 validation overhead?

## Hypothesis

For ASCII-only strings (all bytes < 128), `String.fromCharCodes` would be faster than `utf8.decode` because it skips UTF-8 validation. A byte scan to check for non-ASCII bytes would be cheap for short strings.

## What We Tested

Micro-benchmark comparing `utf8.decode` vs a fast-path that scans for non-ASCII bytes and uses `String.fromCharCodes` for ASCII, falling back to `utf8.decode` for non-ASCII.

## Results

| String type | utf8.decode | Fast-path | Winner |
|---|---|---|---|
| Short ASCII (10 bytes) | 50 ns | **20 ns** | Fast-path (60% faster) |
| Medium ASCII (50 bytes) | 55 ns | **37 ns** | Fast-path (33% faster) |
| Long ASCII (100 bytes) | 84 ns | 81 ns | Tie |
| Unicode (emoji) | **44 ns** | 53 ns | utf8.decode (20% slower) |
| Unicode (CJK) | **72 ns** | 80 ns | utf8.decode (11% slower) |

The fast-path wins for short ASCII strings but the advantage shrinks with length. For non-ASCII strings, it's strictly worse (double scan — first for ASCII check, then utf8.decode).

## Aggregate Impact

At 5,000 rows with ~3,000 text values: estimated savings of ~0.27ms (18ns per string × 15,000 strings). Measured in practice: within noise. The `utf8.decode` implementation in the Dart VM is already highly optimized C code.

## Why Rejected

- Marginal aggregate improvement (~0.27ms) not worth the code complexity
- Slower for non-ASCII strings (double scan)
- `utf8.decode` is implemented in native C inside the Dart VM — hard to beat with Dart-level code
- The byte scan loop is itself Dart code with per-byte overhead

**Key lesson:** The Dart VM's native implementations of common operations (utf8.decode, SendPort.send) are highly optimized C++. Dart-level alternatives rarely win.
