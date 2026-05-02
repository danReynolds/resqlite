# Experiment 117: Named parameters

**Date:** 2026-05-01
**Status:** Rejected (deferred for v0.x launch — see Decision)
**Direction:** `parameter-encoding-and-binding`
**Implementation:** [`exp-117-named-parameters` branch](https://github.com/danReynolds/resqlite/tree/exp-117-named-parameters), PR [#83](https://github.com/danReynolds/resqlite/pull/83) (closed unmerged)

## Problem

resqlite only accepts positional `?` parameters. SQLite supports four placeholder
syntaxes natively (`:name`, `@name`, `$name`, `?NNN`), all resolved through
`sqlite3_bind_parameter_index`. Peers (sqlite3, sqlite_async, drift) accept
named maps; the resqlite ergonomics gap shows up in any code that constructs SQL
with a templating layer or a struct-shaped row.

The constraint is that the existing positional hot path has been tuned across
many experiments (009 batch FFI, 028 SQLITE_STATIC, 070 zero-row buffer, 077
cached `bind_parameter_count`, 109 inline param buffer, 113 direct batch matrix).
A naïve "switch on every call" implementation would regress all of them. The
acceptance criterion was therefore "named ergonomics at zero cost to positional".

## Hypothesis

Add `Map<String, Object?>` as a second accepted shape on every public
parameter-taking method (`select`, `selectBytes`, `execute`, `executeBatch`,
`stream`, `transaction.execute`, `transaction.select`,
`transaction.executeBatch`). The Dart-side encoder writes a different layout
for named binds; the C-side dispatcher picks between two binders based on the
sign of `param_count` (negative = named).

The positional bind loop in C is left structurally identical: the dispatcher
inlines into a single sign check that's loop-invariant in `run_batch_locked`,
so the optimizer should hoist it out of the per-row hot path. The single-row
positional encoder in Dart (`allocateParams(List<Object?>)`) is unchanged.

## Approach

### Public API

`Database.select`, `selectBytes`, `execute`, `stream`, `executeBatch`, plus the
matching `Transaction` methods, accept `Object` for parameters. At runtime the
caller-provided value must be either:

- `List<Object?>` — positional binds for `?` placeholders
- `Map<String, Object?>` — named binds; keys include the leading `:`/`@`/`$`
  sigil exactly as written in the SQL

For `executeBatch`, every row in `paramSets` must have the same shape (all
positional or all named). Mixed batches throw `ArgumentError` on the main
isolate via `assertUniformParamSets`.

### Wire format

Two parameter struct shapes share the same `[structs][bytes]` reusable native
buffer (introduced in exp 109):

```
positional (24 bytes / slot, unchanged):
  type:i32  pad  int_val:i64
                 OR float_val:f64
                 OR { ptr:i64; len:i32; pad }   (text or blob)

named (32 bytes / slot, new):
  type:i32  name_len:i32  name_ptr:i64
  union (16 bytes, mirrored layout):
                 int_val:i64
                 float_val:f64
                 { data_ptr:i64; len:i32; pad } (text or blob)
```

`Dart → C` calls pass `param_count` as a *signed* int. Positive = positional;
negative absolute value = named entry count. The buffer pointer is reinterpreted
on the C side based on sign.

### C dispatch

```c
static inline int bind_params_dispatch(stmt, params, param_count, expected) {
  if (__builtin_expect(param_count >= 0, 1)) {
    return bind_params(stmt, params, param_count, expected);  // existing
  }
  return bind_params_named(stmt, params, -param_count, expected);  // new
}
```

`bind_params` is byte-identical to before. `bind_params_named` copies each
entry's name onto a 64-byte stack buffer (or heap for unusually long names),
calls `sqlite3_bind_parameter_index`, and binds via the same `sqlite3_bind_*`
family. Unknown / missing names return `SQLITE_RANGE`.

## Results

**Functional:** 26 new named-parameter tests pass; full existing suite (127
tests) continues to pass. All four placeholder syntaxes work, in `select`,
`execute`, `executeBatch`, `transaction`, and `stream`, with mixed types
including unicode names and zero-length blobs.

**Performance** (2-repeat release suite, candidate vs baseline):

| Benchmark | Baseline ms | Candidate ms | Delta |
|---|---:|---:|---:|
| Single Inserts (100 sequential) | 2.18 | 2.12 | -3% |
| Batch Insert (1000 rows) | 0.40 | 0.42 | +5% |
| Batch Insert (10000 rows) | 3.96 | 4.14 | +5% |
| **Wide Batch Insert (10000 × 20 params)** | **16.26** | **20.76** | **+28%** |
| Batched Write Inside Transaction (1000 rows) | 0.66 | 0.75 | +14% |
| Nested Transactions (savepoints) batch | 1.05 | 1.26 | +20% |

The Wide Batch +28% was scrutinized with a focused 5-run A/B on the same shape:

| | Baseline p50 (ms) | Candidate p50 (ms) |
|---|---:|---:|
| Median | 18.10 | 18.60 |
| Range | 16.84..19.62 | 18.33..19.41 |

Focused 5-run delta: **+2.7% with overlapping ranges**.

Suite-level: 16 wins, 2 regressions, 143 neutral.

## Decision

**Deferred for v0.x launch.** Will reopen post-launch if either condition holds.

The implementation is functionally complete and correct. The 5-run focused
harness shows the wide-batch +28% in the 2-repeat suite is largely small-sample
noise — the real delta is +2.7%, within overlapping ranges. So this is *not*
clearly broken.

What it *is*, on close reading, is a 12K-LOC change touching the entire write
path (writer isolate, reader pool, FFI bindings, native dispatch) where:

1. **The trend across write-path metrics is consistently positive (slower).**
   6 of 7 measured write benchmarks went the wrong direction. Each individually
   is "within noise," but collectively the direction is monotonic — that's
   weaker evidence than independent random fluctuation would suggest.
2. **The wire format changes the Dart↔C contract.** Once shipped, future
   native-side changes have to maintain dual-mode dispatch in perpetuity.
3. **The ergonomics benefit is real but modest.** `{':id': 42}` vs `[42]` is
   convenient for SQL with many parameters but doesn't change what users can
   do. Peers offer it, and resqlite's lack of it is a documented gap, but it
   is not the reason anyone picks or rejects this library.

For a pre-launch package whose primary marketing claim is performance, shipping
an invasive hot-path change for an ergonomics nice-to-have is a worse trade
than shipping without it and adding it later if real users ask for it.

### Reopen if

- A 5-run release suite (vs fresh baseline) on the existing branch consistently
  shows neutral wide-batch numbers, *and* community feedback indicates named
  parameters are an actual barrier to adoption (not just a "would be nice"
  comment).
- Or: someone redesigns the C dispatch as two top-level branches in
  `run_batch_locked` (positional vs named) instead of routing every per-row
  bind through the inline dispatch helper. The agent's hypothesis was that the
  wide-batch drift came from the optimizer failing to hoist the dispatch
  branch out of the inner loop in release builds; specializing the loop would
  eliminate that risk entirely. If that variant benchmarks clean on a 5-run,
  the cost/benefit shifts and merge is the right call.

The full implementation lives on the
[`exp-117-named-parameters` branch](https://github.com/danReynolds/resqlite/tree/exp-117-named-parameters)
and can be cherry-picked, rebased, or used as a starting point for the
specialized-loop variant.

## Future Notes

If this is reopened, two follow-ups already noted by the implementation pass
are worth profiling:

1. **Cache `name → bind_index` in the statement cache entry.** Today every bind
   calls `sqlite3_bind_parameter_index` which walks the statement's parameter
   list. For a stmt rebound many times with the same map shape, a per-entry
   `(name → idx)` cache would replace the strcmp walk with a hash lookup.
2. **Shrink the named struct from 32 to 24 bytes** by storing the name as a
   tail-block offset rather than a 64-bit pointer — matching the positional
   layout — at the cost of one extra address-decode in `bind_params_named`.
   Skip unless wire format width shows up as a memory constraint.

If a real use case wants to pass the same map to many back-to-back queries
(e.g. batched `update where id=:id` with stable keys but varying values),
pre-encoding the buffer once and re-binding values into the existing layout
could save a lot of `utf8.encode` work on the names.
