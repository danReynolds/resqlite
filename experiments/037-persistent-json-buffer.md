# Experiment 037: Persistent JSON Buffer Per Reader

**Date:** 2026-04-09
**Status:** Accepted

## Change

Added a `resqlite_buf json_buf` to the `resqlite_reader` struct. Instead of
malloc/free per `resqlite_query_bytes` call, the buffer persists across queries.
Reset is just `reader->json_buf.len = 0` — no allocation.

The Dart side copies from the persistent buffer into a Dart `Uint8List` (which
it already did) and no longer calls `resqlite_free` on the result pointer.

Safe because dedicated reader assignment (experiment 030) guarantees exclusive
access — the caller copies before the next query on that reader.

## Results

Part of the cumulative selectBytes improvement. Eliminates 1 malloc + 1 free
per selectBytes query. The buffer grows to the high-water result size and stays.

## Decision

**Accepted** — eliminates real syscall-class operations on the hot path.
Initialized to 16KB at open time, grows as needed, freed on close.
