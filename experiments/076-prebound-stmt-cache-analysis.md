# Experiment 076: Pre-bound statement cache — rejected during design

**Date:** 2026-04-16
**Status:** Rejected (not implemented — analysis showed no measurable headroom)

## Original hypothesis

Caching bound parameters per-stream would let re-queries skip the
`sqlite3_clear_bindings` + `sqlite3_bind_*` loop and go straight to
`sqlite3_reset` + step. Expected win: a few hundred nanoseconds per
stream re-query, amplified at high invalidation rates.

## Why it doesn't work out

### Bind is ~1% of a re-query's wall time

Hot-path cost breakdown for a typical re-query of
`SELECT COUNT(*) FROM items` (0 params):

| Stage | Approx cost |
|---|---:|
| main isolate: dispatch to reader pool | 5 µs |
| SendPort request | ~2 µs |
| FFI `stmt_acquire_on` | ~1 µs |
| `sqlite3_reset` | ~30 ns |
| `sqlite3_clear_bindings` | ~30 ns |
| `sqlite3_bind_parameter_count` | ~20 ns |
| `sqlite3_step` loop | ~3 µs |
| Cell decode into Dart | ~2 µs |
| Hash fold (exp 075) | ~200 ns |
| SendPort reply | ~2 µs |
| main isolate: emit | ~2 µs |

The combined bind-path cost (`clear_bindings` + parameter count check)
is **~50 ns out of ~15 µs** — about 0.3 % of the re-query. A perfect
implementation saves nothing visible against noise.

### The memcmp-based bind cache has a fundamental flaw

Dart's `allocateParams` builds a fresh `resqlite_param[]` buffer on
every call. For integer and double params the values are inlined — a
memcmp against a cached buffer would correctly detect "same params."
But for text and blob params, Dart writes a **pointer + length**:

```c
struct { const char* data; int len; } text;
struct { const void* data; int len; } blob;
```

The pointer is a fresh Dart heap allocation each call, even when the
logical text is identical. A memcmp never matches, so the bind-cache
never hits on any query with string parameters — which is the majority
of real Flutter queries (`WHERE name = ?`, `WHERE user_id = ?` etc.).

Workarounds considered:
1. **Content-compare text/blob in C.** Equivalent cost to re-binding;
   no win.
2. **Dart inlines text content into the param buffer.** Requires
   copying text twice (once into the param buffer, once via SQLite's
   bind copy) — more work than the current path.
3. **API-level "same as last time" hint from Dart.** Would require a
   public API change, violating the round 2 constraint.

### Per-stream pre-bind (the tier-list variant)

A stream-specific dedicated stmt pre-prepared + pre-bound on every
reader, never shared with ad-hoc queries, would dodge the text-pointer
problem. But:

- Memory cost: `N_streams × N_readers × ~1-4 KB` — tolerable.
- Complexity cost: new lifecycle (per-stream stmt created at subscribe,
  released at cancel, re-prepared on sacrifice-respawn).
- Actual savings: the ~50 ns per re-query still holds. Even across a
  100-stream-update burst that's 5 µs of savings total — under the
  measurement floor.

## Decision

Rejected without implementing. The analysis shows the savings ceiling
is ~50 ns per re-query (0.3% of wall time), and the only clean way to
realize it (dedicated per-stream stmts) adds real complexity for a
change that wouldn't register on any benchmark.

## What this means for future rounds

The right optimizations are further up the stack. Per-re-query work
breaks down as:

1. **isolate dispatch + SendPort round-trips** (~12 µs): experiment
   056-class — move dispatch or the hop.
2. **FFI crossings in the step loop** (~3 µs + ~50 ns × rows): experiment
   052' — one FFI call instead of N.
3. **Dart-side object materialization** (~2 µs + alloc per cell): attack
   via lazy decode or raw buffer transport.

Bind is not on the list. Moving on to experiment 074.

## What WAS tried before writing this up

None — this document is the pre-implementation analysis. Saving the
time it would have taken to write the C+Dart machinery for a
guaranteed-null result.
