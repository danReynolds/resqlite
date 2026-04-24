# Experiment 098: Per-stmt JSON column-prefix cache

**Date:** 2026-04-24
**Status:** Rejected
**Archive:** [`archive/exp-098`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-098)

## Problem

`write_json_to_buf` emits a row object for every result row by walking the
column list and, for each column, calling `json_write_string` on the column
name followed by `buf_write_char(':')`. The column name is an invariant of the
prepared statement — it never changes across rows or across re-executions of
the same cached stmt — but the SWAR+LUT escape scan + quote + colon emit
sequence repeats for every row, every query, every column.

At 10k rows × 6 columns the selectBytes hot path re-escapes the same
`"id":`, `"name":`, `"description":`, ... byte sequences 60,000 times per
query.

## Hypothesis

Pre-computing the quoted, escape-scanned, colon-terminated column-name bytes
once per cached statement and collapsing the 3-4 per-column buf ops into a
single `buf_write` of the cached prefix should shave 5-15% off selectBytes on
the 10k-row benchmark — the column-name work is a real share of the per-row
loop, and SWAR's floor on short strings (~30 ns each) compounds.

## Approach

Added three fields to `resqlite_cached_stmt`:

- `char* json_prefix_buf` — concatenated `"name1":"name2":...` bytes for
  every output column
- `int* json_prefix_offsets` — `col_count + 1` offsets into the buffer, last
  entry is the sentinel total length, so each prefix lives in
  `[offsets[i], offsets[i+1])`
- `int json_prefix_col_count` — number of columns the cache was built for
  (so we can detect and rebuild on PRAGMA-style schema changes)

`stmt_build_json_col_prefixes` populates both fields using
`json_write_string` + `buf_write_char(':')` into a staging `resqlite_buf`,
then transfers ownership onto the cached stmt entry. Build is deferred to
the first row emitted (so the amortization is guaranteed before we pay the
build cost) with a rebuild fallback if the cached `col_count` stops matching
the live stmt.

`write_json_to_buf` now takes the `resqlite_cached_stmt*` as a second
argument. The per-row column loop replaces

```c
json_write_string(b, col_names[i], col_name_lens[i]);
buf_write_char(b, ':');
```

with

```c
int pfx_off = json_prefix_offsets[i];
int pfx_len = json_prefix_offsets[i + 1] - pfx_off;
buf_write(b, json_prefix_buf + pfx_off, pfx_len);
```

The stack-allocated `_col_names_stack` / `_col_name_lens_stack` arrays and
the heap fallback for `col_count > 64` are gone — the cached prefix buffer
replaces them entirely. Cache eviction in `stmt_cache_insert` and teardown
in `stmt_cache_clear` free the new buffers alongside the existing
`sqlite3_finalize` and `free(sql)` calls.

## Results

Artifacts:

- `benchmark/results/2026-04-24T07-27-09-exp098-json-col-prefix-cache.md`
- `benchmark/results/2026-04-24T07-27-09-exp098-json-col-prefix-cache.json`

Targeted selectBytes medians (baseline = exp097 merge, 3 runs each):

| Rows | Baseline (ms) | Experiment (ms) |
|---:|---:|---:|
| 10 | 0.01 | 0.01 |
| 100 | 0.04 | 0.04 |
| 500 | 0.17 | 0.17 |
| 1000 | 0.33 | 0.33 |
| 2000 | 0.79 | 0.79 |
| 5000 | 2.11 | 2.11 |
| 10000 | 3.51 | 3.51 (3.41..3.56) |
| 20000 | 8.02 | 8.02 |

Full-suite summary: **2 wins, 3 regressions, 148 neutral**. Both wins and
all three regressions were on `select()` / concurrent-read paths that don't
touch `write_json_to_buf` at all — the variance is entirely noise on
unrelated benchmarks.

All 68 selectBytes- and reader-pool-related unit tests pass — correctness
is fine.

## Decision

Rejected.

The optimization is semantically clean and the theoretical savings
(eliminating ~60k per-query SWAR+LUT column-name walks) should compound,
but on the shipped workload SWAR already makes short column-name writes
(`"id"`, `"name"`, etc.) near-free, and the selectBytes hot path is
saturated by memcpy bandwidth into `resqlite_buf` rather than per-column
control flow. The experiment delivers no measurable selectBytes win across
10 → 20,000 rows.

Below-floor measured win + new failure mode (`col_count` divergence
triggering a rebuild path) + extra heap management per cached stmt is the
wrong trade. Same class as exp 059 (row-count hint in schema cache) and
exp 093 (alias cache entry read tables) — structurally sound, benchmark
invisible.

Revisit if a future workload surfaces with either (a) very long column
names where SWAR's floor is no longer near-zero, or (b) very wide result
sets where 100+ per-row column ops genuinely dominate the emit loop.
