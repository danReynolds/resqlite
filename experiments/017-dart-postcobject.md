# Experiment 017: Dart_PostCObject for Reads

**Date:** 2026-04-07
**Status:** Rejected

## Hypothesis

`Dart_PostCObject` uses a completely different code path (`dart_api_message.cc`) that bypasses the `Isolate.exit` validation walk. By building query results as `Dart_CObject` structs in C and posting them directly to a Dart `ReceivePort`, we could eliminate the ~470μs validation walk at 10k rows.

## What We Built

New C function `resqlite_select_post` that:
1. Acquires reader from pool
2. Prepares/caches statement, binds params
3. Steps rows, building a `Dart_CObject` tree (kInt64/kDouble/kString/kNull per cell)
4. Posts via `Dart_PostCObject_DL` to a Dart `ReceivePort`
5. Frees all C-side allocations

Vendored Dart SDK headers (`dart_api_dl.h/c`), updated build system, added FFI bindings and `Database.selectPost()` method.

## Results

| Rows | Isolate.exit | PostCObject | Delta |
|---:|---:|---:|:---|
| 100 | 0.15ms | 0.25ms | **66% slower** |
| 1000 | 0.41ms | 2.32ms | **459% slower** |
| 5000 | 1.84ms | 7.31ms | **297% slower** |
| 10000 | 5.24ms | 17.61ms | **236% slower** |

PostCObject is 2-5x slower at every size.

## Why It Failed

The research correctly identified that `Dart_PostCObject` bypasses the validation walk. But it missed the critical difference:

- **Isolate.exit**: Objects already live on the shared Dart heap. Ownership is reassigned (no copy). The validation walk just checks type tags — O(n) but ~10ns per object.
- **Dart_PostCObject**: C-side `Dart_CObject` structs must be **serialized** into a message buffer, sent through the port system, and **deserialized** into new Dart heap objects on the receiver. This is a full serialize + allocate + deserialize cycle — far more expensive than checking type tags.

The validation walk we were trying to eliminate costs ~0.47ms at 10k rows. The serialize/deserialize it replaced costs ~17ms. The "bypass" trades a cheap check for expensive work.

`Dart_PostCObject` is designed for sending data FROM native threads that don't have access to the Dart heap. For our case (Dart worker isolate with shared heap access), `Isolate.exit` is fundamentally the right tool — it leverages the shared heap to avoid serialization entirely.

## Decision

**Rejected.** Isolate.exit's validation walk (~10ns per object) is dramatically cheaper than Dart_PostCObject's serialize/deserialize cycle. The shared-heap ownership transfer model is the optimal path for Dart-to-Dart data transfer.

This confirms that our Isolate.exit + flat list + lazy ResultSet architecture (experiments 008-009) is at the practical performance ceiling for Dart isolate-based data transfer.
