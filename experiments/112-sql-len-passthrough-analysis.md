# Experiment 112: SQL byte-length passthrough — rejected during design

**Date:** 2026-04-29
**Status:** Rejected (not implemented — analysis showed no measurable headroom)
**Direction:** `parameter-encoding-and-binding`

## Problem

Every public C entry point that takes a SQL string calls `strlen(sql)` to
size the cache lookup and `sqlite3_prepare_v3` call. Today's call sites
(`native/resqlite.c`):

| Entry point | Line | Hot path? |
|---|---:|---|
| `resqlite_execute` | 715 | every `db.execute()` write |
| `run_batch_locked` lookup | 778 | every batched write |
| `run_batch_locked` insert | 788 | only on first prep of a unique SQL |
| `resqlite_stmt_acquire` | 1119 | pool path (rarely used since exp 030) |
| `resqlite_stmt_acquire_on` | 1161 | every reader query (point queries, selects, streams) |
| `resqlite_stmt_acquire_writer` | 1186 | every transaction read |
| `resqlite_query_bytes` | 1497 | every `selectBytes()` call |

Dart already knows the byte length when it loads the cached UTF-8 buffer
in `lib/src/native/request_cache.dart::cachedSqlUtf8`. We could thread
it through FFI (`(sql, sql_len, params, ...)`) and drop the C-side
`strlen`. This pattern matches the strlen-skip half of [exp 109](109-inline-param-buffer.md),
which let `sqlite3_bind_text` skip its internal `strlen` walk on the
text-bind path.

## Hypothesis

Skipping a `strlen(sql)` per query call across every read and write
entry point should remove visible per-call work, especially on the
~9 µs point-query and ~10 µs writer-dispatch floors identified by
[exp 080](080-dispatch-budget.md).

## Why it doesn't work out

### The savings ceiling is below the dispatch-noise floor

Modern SIMD `strlen` runs at ~16 bytes/cycle on the Apple Silicon
hardware in our reference benchmark (`memchr`-class loop). For the
benchmark suite's representative SQL strings — sampled from
`benchmark/suites/`:

```
"SELECT id, body, updated_at FROM items WHERE id = ?"  // 51 bytes
"INSERT INTO items(body, updated_at) VALUES (?, ?)"     // 48 bytes
"UPDATE wide SET c = ? WHERE id = ?"                    // 34 bytes
"INSERT INTO messages(conv_id, sender_id, body, sent_at) VALUES (?, ?, ?, ?)" // 75 bytes
```

— per-call cost is roughly 3–6 ns. Cross-referenced against the
[exp 080](080-dispatch-budget.md) budget table (point query 9 µs;
single insert 16 µs; writer floor 10 µs), the strlen contribution is
**0.03–0.07 % of wall time**. The Sync Burst merge-rounds path calls
`strlen` twice in `run_batch_locked` (lookup + cache-miss insert), but
the cache-miss case fires once per unique SQL — amortized to zero on
hot loops — and the lookup path is one strlen per batch-of-N rows, so
the per-row contribution is divided by N again.

This sits below the noise floor on the same release suite that already
rejected:

- exp 095 (persistent writer 16-byte result buffer) — 0 wins / 14 regressions
- exp 094 / 104 (dirty/read string reuse) — flat under A11c fan-out
- exp 102 (cached SAVEPOINT/RELEASE strings) — only run-to-run drift on
  unrelated paths
- exp 108 (persistent selectBytes out-slots) — within noise

The recurring lesson: **a single repeated computation of ~tens of
nanoseconds, even when removed from every query, does not register on
the suite.** [Exp 109](109-inline-param-buffer.md) is the explicit
counter-example, and the reason it landed is that it combined two
effects (per-text/blob `calloc` removal **and** SQLite-internal
`strlen` skip) — not just the strlen.

### The compounding lever isn't there

To raise this above the noise floor we would need to combine the
strlen-skip with a second per-call saving on the same path. Candidates
considered:

1. **Drop the `LinkedHashMap` LRU promote in `cachedSqlUtf8`.** The
   cache currently does a `remove` + re-`put` on every hit to keep
   the most-recent entry at the tail. A plain `HashMap` lookup would
   skip one hash op (~50 ns). But the cache is sized at 32 entries,
   which exceeds the distinct-SQL count of every shipped benchmark and
   most realistic apps — the LRU never evicts, so the promote-on-hit
   work is functionally redundant. Removing it is a separate, equally
   marginal optimization with the same noise-floor problem; see exp 071
   (MRU-first stmt cache scan), which was rejected for the identical
   "≤ 10 distinct SQLs in the suite" reason.

2. **Combine with cache-key change.** The cache is keyed by Dart
   `String`. We can't trivially drop the per-call `String.hashCode`
   because the FFI signature requires a stable native pointer keyed by
   the original Dart SQL. Memoizing the hash on the Dart string
   itself is already the VM's behavior.

3. **Bigger refactor.** Pre-cache a `(Pointer<Utf8>, int len)` *struct*
   in a Dart `Expando<NativeSqlEntry>` keyed off the `String` so the
   first lookup is the only hash. This trades the LinkedHashMap for an
   identity-keyed Expando. Implementation cost is real (lifecycle for
   freeing the native pointer when the Dart string is collected — Dart
   `Finalizer` adds its own per-allocation cost), and the savings
   ceiling is still strlen + one hash op. Not worth it without a
   workload that actually stresses the path.

### FFI signature change cost

Threading `int sql_len` through six C entry points and matching Dart
`@ffi.Native` declarations is mechanical, but it's a change to every
call site and to the compiled native library. The cost isn't the
implementation — it's the precedent: every future readability/refactor
pass through these signatures pays for the extra parameter. The
benchmark-invisible win does not justify the permanent surface change,
matching the same line of reasoning that closed exp 076 and exp 108.

## Decision

**Rejected without implementing.** The savings ceiling (3–6 ns per
query × every entry point) sits below the demonstrated noise floor of
the release suite, and the only realistic way to raise it above the
floor is to compound with another marginal optimization that hits the
same noise wall on its own (see exps 071, 094, 095, 102, 108).

This is the same shape as [exp 076](076-prebound-stmt-cache-analysis.md):
a structurally sensible "remove a small repeated computation" change
whose target cost is below the suite's measurement floor before
implementation begins.

## What would reopen this

Reopen the area when **any** of these is true:

- A workload arrives whose SQL strings dominate per-call cost — for
  example, a benchmark with auto-generated `WHERE` clauses or `IN ()`
  expansions producing 1–10 KB SQL strings. The current suite tops out
  near ~75 bytes; 50× longer strings move strlen from sub-percent to
  the low single-digit per-call percentage.
- A profile/trace shows C-side `strlen` as a meaningful slice of
  dispatch wall (today the dispatch budget profile in
  `benchmark/profile/dispatch_budget.dart` does not have the
  granularity to surface a 3–6 ns slice; that itself would require
  finer instrumentation, which is its own investigation).
- A second, structurally independent per-call C-side saving on the
  same entry points lands first — at which point combining the two
  matches the exp 109 acceptance pattern.

## What this means for future rounds

The dispatch floor identified in [exp 080](080-dispatch-budget.md) is
not going to fall to per-call C-side cleanups in the 5–50 ns range.
The realistic next levers are still those exp 080 itself enumerated:

1. **Writer/reader 3 µs gap** (preupdate hook, authorizer, dirtyTables
   zero-write traversal) — partially attacked by exp 077, but the hook
   enable/disable cost wasn't what 077 optimized.
2. **Isolate-wake / SendPort round-trip** — the dominant share of the
   point-query 9 µs.
3. **Tail-latency p99** — checkpoint scheduling and GC pauses.

`strlen`-at-entry is not on that list, and this writeup is the record
that it was considered.

## What WAS tried before writing this up

None — this document is the pre-implementation analysis. The estimate
combines (a) the C source audit from this branch, (b) representative
SQL byte lengths sampled from the shipped benchmark suite, and
(c) the per-call cost framing established by exp 080.
