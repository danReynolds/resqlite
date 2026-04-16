# Experiment 063: SelectOne fast path (combined single-row FFI with inline text copy)

**Date:** 2026-04-16
**Status:** Rejected (measured +28-48% win, rejected to preserve lean API)

## Problem

Point queries (single-row lookups by primary key or indexed column) are a common pattern, but the current `select()` path crosses the FFI boundary four times per query:

1. `sqlite3_column_count` — 1 crossing
2. `resqlite_stmt_acquire_on` — 1 crossing (includes get_or_prepare + bind)
3. `resqlite_step_row` → returns SQLITE_ROW — 1 crossing
4. `resqlite_step_row` → returns SQLITE_DONE — 1 crossing

Plus it allocates a 512-slot `List<Object?>` for results, constructs `RawQueryResult` + `ResultSet` wrappers, and returns a single-element List via isolate transfer — all machinery that's essential for multi-row results but dead weight for point queries.

Experiment 060 attempted to combine these into one FFI call but was blocked by text pointer lifetime. This experiment resurrects the idea with an inline-copy solution.

## Hypothesis

Combine the four crossings into one FFI call. Handle the text pointer lifetime issue by **copying text/blob bytes into the caller's buffer** before resetting the statement. The cell's `p` field stores a byte offset into the buffer instead of an absolute SQLite-owned pointer. Dart reconstructs the pointer as `bufBase + offset`.

Expose this via a new `selectOne(sql, params) → Future<Map<String, Object?>?>` API that returns a single Map directly, bypassing the List+ResultSet wrappers.

## Approach

### C side: `resqlite_query_single_row_copy`

Does acquire + bind + step (once) + copy text/blob inline + reset + return. Buffer layout:
- `[0 .. col_count*16)` — cell array
- `[col_count*16 .. buf_size)` — text/blob data area

For TEXT/BLOB cells, `cells[i].i` stores an offset into the data area. The Dart side reads the bytes at `cell_buf + offset`.

### Dart side: `selectOne(sql, params)`

New API on `Database` and `ReaderPool` that returns a single Map (or null if no row). On first call for a new SQL, falls back to `executeQuery` internally to warm the schema cache; subsequent calls use the fast path.

## Results

Standalone benchmark, 5 runs:

| Run | select() qps | selectOne() qps | Speedup |
|----:|-------------:|----------------:|--------:|
| 1 | 94,411 | 123,305 | +30.6% |
| 2 | 98,775 | 128,535 | +30.1% |
| 3 | 111,932 | 165,071 | +47.5% |
| 4 | 122,941 | 170,648 | +38.8% |
| 5 | 124,254 | 158,881 | +27.9% |

**Consistent 28-48% throughput improvement on point queries.** Absolute improvement: ~3μs saved per query. Correctness verified against `select()` for int/real/text/blob/null columns, empty result sets, and long strings.

## Why the Win Was So Large

The savings decompose into three sources:
1. **2-3 FFI crossings eliminated** (~200-300ns)
2. **No 512-slot `List<Object?>.filled` allocation** — `selectOne` builds a small Map directly
3. **No `RawQueryResult`/`ResultSet` wrappers** — simpler isolate transfer payload (Map vs List+wrappers)

FFI savings alone would be ~4-5%. The other two sources (enabled by returning `Map` instead of `List<Map>`) contribute the bulk.

## Decision

**Rejected despite the strong measured win** — adds API surface (new method `selectOne`) that complicates the lean library API.

The user feedback: "I like the methodology though. Are there wins to try that are under the hood and leverage these innovations while making it transparent for consumers?"

This led to experiment 066, which attempted a transparent version using probe-based detection in `select()`. That showed the win cannot be captured transparently — the bulk of the improvement comes from the API shape change (Map vs List<Map>), which by definition can't be done without changing the API.

**Future consideration:** if workload evidence surfaces that single-row queries dominate a particular app, this API could be revisited. The implementation is sound and tested. For now, the preference for a lean surface wins.

## Lasting artifact

The `fill_cells_inline` helper in `resqlite.c`, designed for this experiment, was reused for experiment 066's probe function.
