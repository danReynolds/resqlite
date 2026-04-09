# Experiment 005: Dart Binary Codec with TransferableTypedData

**Date:** 2026-04-06
**Status:** Rejected

## Problem

`Isolate.exit()` transfers maps zero-copy but kills the isolate. `SendPort.send()` keeps workers alive but deep-copies maps. Could we encode maps into a `Uint8List` on the worker, send via `TransferableTypedData` (zero-copy over `SendPort.send()`), and decode on main? This would give us both persistent workers AND zero-copy transfer.

## Hypothesis

A Dart-side binary codec (encode maps → bytes → TransferableTypedData → decode maps) would be faster than `SendPort.send()`'s deep copy for large results, while keeping workers alive.

## What We Tested

Used the existing `tool/transport_benchmark.dart` from sqlite_reactive, which implements a Dart binary row codec (header + per-cell type tags + values) and compares it against raw object transport via `SendPort.send()` on long-lived workers.

## Results

| Rows | Object transport (SendPort.send) | Binary codec (TransferableTypedData) | Winner |
|---|---|---|---|
| 100 | 29 μs | 240 μs | Object (8x faster) |
| 1,000 | 166 μs | 851 μs | Object (5x faster) |
| 5,000 | 724 μs | 5,088 μs | Object (7x faster) |
| 10,000 | 1,402 μs | 8,304 μs | Object (6x faster) |

**The Dart binary codec was 5-7x slower at every size.** The Dart VM's internal C++ serializer (used by `SendPort.send()`) is far more efficient than anything we can build in Dart-level byte manipulation.

## Why Rejected

Cannot beat the VM's native serializer with Dart code. The encode/decode overhead (iterating values, writing to BytesBuilder, reading back from ByteData) far exceeds the copy cost of `SendPort.send()`.

**Key lesson:** The only way to beat `SendPort.send()` is to avoid creating Dart objects in the first place (C pipeline for bytes) or reduce the object count (which we later did with the flat list approach in experiment 008).
