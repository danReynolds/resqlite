# Experiment 001: C-Native JSON Serialization

**Date:** 2026-04-06
**Status:** Accepted
**Commit:** [`4acfb57`](https://github.com/danReynolds/dune/commit/4acfb57)

## Problem

Building an HTTP response from a SQLite query requires: query → Dart maps → jsonEncode → utf8.encode → shelf. At 5,000 rows, jsonEncode + utf8.encode alone costs ~8.6ms on the main isolate. The data passes through three intermediate representations (maps, JSON string, UTF-8 bytes) before reaching the socket.

## Hypothesis

If we write a C function that reads SQLite column values and writes JSON directly into a malloc'd buffer, we can skip all Dart object allocation for the result data. The Uint8List containing the JSON would transfer to the main isolate via Isolate.exit at effectively zero cost (one object to validate).

## What We Built

`resqlite_query_to_bytes` — a C function that:
- Calls `sqlite3_step` in a loop
- Reads each column via `sqlite3_column_text/int64/double/blob`
- Writes JSON directly: `[{"col":"value",...},...]`
- Handles string escaping, number formatting, null literals
- Returns a malloc'd buffer + length

## Results

At 5,000 rows (1MB JSON):

| Path | Wall time |
|---|---|
| resqlite `selectBytes()` (C JSON) | **4.35 ms** |
| sqlite3 package + jsonEncode | 15.02 ms |

**3.5x faster.** Zero Dart objects for result data. Zero main-isolate work.

## Why Accepted

The C JSON pipeline is unambiguously the fastest path for producing HTTP response bodies from SQLite queries. No other approach in the Dart ecosystem comes close. This became the `selectBytes()` API.
