# Experiment 117: Named parameters

**Date:** 2026-05-01T14:10:31
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`

## Problem

resqlite only accepts positional `?` parameters. SQLite supports four placeholder
syntaxes natively (`:name`, `@name`, `$name`, `?NNN`), all resolved through
`sqlite3_bind_parameter_index`. Peers (sqlite3, sqlite_async) accept named maps;
the resqlite ergonomics gap shows up in any code that constructs SQL with a
templating layer or a struct-shaped row.

The constraint is that the existing positional hot path has been tuned across
many experiments (009 batch FFI, 028 SQLITE_STATIC, 070 zero-row buffer, 077
cached `bind_parameter_count`, 109 inline param buffer, 113 direct batch matrix).
A naïve "switch on every call" implementation would regress all of them. The
acceptance criterion is therefore "named ergonomics at zero cost to positional".

## Hypothesis

Add `Map<String, Object?>` as a second accepted shape on every public
parameter-taking method (`select`, `selectBytes`, `execute`, `executeBatch`,
`stream`, `transaction.execute`, `transaction.select`,
`transaction.executeBatch`). The Dart-side encoder writes a different layout
for named binds; the C-side dispatcher picks between two binders based on the
sign of `param_count` (negative = named).

The positional bind loop in C is left structurally identical: the dispatcher
inlines into a single sign check that's loop-invariant in `run_batch_locked`,
so the optimizer hoists it out of the per-row hot path. The single-row
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

Validation runs on the main isolate via `checkParameters` so callers see a
typed `ArgumentError` directly rather than a generic
`ResqliteException("Internal error in writer isolate: ...")` wrapper.

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

`bind_params` is byte-identical to before exp 117. `bind_params_named`
copies each entry's name onto a 64-byte stack buffer (or heap for unusually
long names), calls `sqlite3_bind_parameter_index`, and binds via the same
`sqlite3_bind_*` family as the positional path. Unknown / missing names
return `SQLITE_RANGE` so the public API surfaces a unified
"parameter count mismatch" error.

The batch loop in `run_batch_locked` precomputes the per-row stride and
absolute count once outside the hot loop:

```c
const int abs_count = param_count < 0 ? -param_count : param_count;
const size_t stride = param_count < 0
    ? sizeof(resqlite_named_param) * abs_count
    : sizeof(resqlite_param) * abs_count;
for (int i = 0; i < set_count; i++) {
  bind_params_dispatch(stmt, row_base + i*stride, param_count, expected);
  ...
}
```

### Hot-path preservation

The encoder, message types, and worker entry points were all updated to
accept `Object` parameters. Care was taken to keep the positional path
allocation-and-branch-equivalent to before:

- `executeWrite` does an inline `if (params is List<Object?>)` once and
  delegates straight to `allocateParams` — no extra record allocation, no
  extra closure indirection.
- `assertUniformParamSets` adds one `is List<Object?>` check per row to
  catch mixed-shape batches; this fires on the main isolate before the
  isolate hop.
- `_handleBatch` (writer) promotes the loose `List<Object>` SendPort
  payload to `List<List<Object?>>` *once* via `cast().toList(growable: false)`,
  but only if a runtime `is List<List<Object?>>` fast-path check fails. For
  the common case (caller passes `List<List<Object?>>`-typed input, e.g.
  `[for (var i = 0; i < N; i++) [...]]`), the fast path returns the message
  as-is.
- `allocateBatchParams` and `_allocateBatchNamedParams` accept strongly-typed
  inputs so their per-cell hot loops never do an `as` cast inside the
  iteration. An earlier draft of this experiment used inline per-row `as`
  casts and showed a clear ~25% regression on the 10,000-row × 20-param
  wide batch insert, which was traced to the per-row check overhead and
  fixed by pre-promoting once.

### Tests

`test/named_params_test.dart` covers:

- All four placeholder syntaxes (`:name`, `@name`, `$name`, `?NNN`)
- Mixed sigils in the same SQL
- All SQLite types (int, double, text, blob, null)
- Unicode, empty strings, zero-length blobs, very long parameter names
  (overflowing the C-side stack buffer)
- Map insertion order independent of SQL parameter order
- Positional and named on same `Database` (statement cache must not
  collide)
- Unknown / missing / extra parameter throws `ResqliteQueryException`
- Non-list non-map throws `ArgumentError` with the original stack trace
- `executeBatch` named with mixed types and uniformity validation
- `executeBatch` rejects mixing positional and named rows
- Named params inside `db.transaction(...)` body
- Named params inside `tx.executeBatch(...)` (nested batch path)
- `db.stream(...)` with named params (initial emit + re-emit on table change)
- Stream key dedup: two streams with same SQL + same map (different
  insertion order) share a single `StreamEntry`
- `selectBytes` with named params

26 tests, all pass; full existing suite continues to pass (105 tests in
`database_test.dart` + `transaction_test.dart` + `reader_pool_test.dart` +
related).

## Results

Artifacts:

- Baseline: [`benchmark/results/2026-05-01T13-17-43-baseline-for-exp117.md`](../benchmark/results/2026-05-01T13-17-43-baseline-for-exp117.md)
- Candidate: [`benchmark/results/2026-05-01T14-10-31-exp117-named-parameters.md`](../benchmark/results/2026-05-01T14-10-31-exp117-named-parameters.md)

Command:

```text
dart run benchmark/run_release.dart exp117-named-parameters --repeat=2 \
  --compare-to=benchmark/results/2026-05-01T13-17-43-baseline-for-exp117.md
```

Suite-level (2 repeats per side): **16 wins, 2 regressions, 143 neutral**.

The wins concentrate on read-shaped scaling benchmarks (10k row scaling,
20k row scaling) at ~13–28% — these are downstream of unrelated reader
work and are noted only because they show that the named dispatch did not
displace those gains.

The decision-relevant write benchmarks (positional hot path):

| Benchmark | Baseline ms | Candidate ms | Delta | Status |
|---|---:|---:|---:|---|
| Single Inserts (100 sequential) | 2.18 | 2.12 | -3% | within noise |
| Batch Insert (100 rows) | 0.05 | 0.06 | +20% | within noise |
| Batch Insert (1000 rows) | 0.40 | 0.42 | +5% | stable, within noise |
| Batch Insert (10000 rows) | 3.96 | 4.14 | +5% | within noise |
| Wide Batch Insert (10000 rows × 20 params) | 16.26 | 20.76 | **+28%** | flagged |
| Batched Write Inside Transaction (1000 rows) | 0.66 | 0.75 | +14% | noisy |
| Nested Transactions (savepoints) batch | 1.05 | 1.26 | +20% | noisy |

The Wide Batch Insert flag is the one to scrutinize. A focused 5-run A/B
on the same 10k × 20 shape, isolating just the batch encode path:

| Run | Main p50 (ms) | Candidate p50 (ms) |
|---|---:|---:|
| 1 | 17.05 | 18.60 |
| 2 | 19.62 | 18.39 |
| 3 | 18.10 | 18.92 |
| 4 | 16.84 | 19.41 |
| 5 | 18.82 | 18.33 |
| Median | 18.10 | 18.60 |
| Range | 16.84..19.62 | 18.33..19.41 |

The median delta on the focused harness is +2.7%, with overlapping
inter-run ranges. The release suite's larger +28% number is dominated by
the 2-repeat shape: with only two samples, a single high-noise iteration
shifts the reported median. The focused 5-run comparison is the more
reliable signal.

## Decision

**Keep in review.**

The named-parameter implementation is functionally complete and correct,
and the positional hot path is at most a few percent slower than baseline
on the targeted bind-heavy workloads. The release suite's 2-repeat
"+28% wide batch" flag is a known artifact of the small sample count;
the focused 5-run on the same shape shows ~3% (within noise).

To convert to **Accepted** the right gating signal is a 5-run release
suite from each side rather than 2-run. That run is a follow-up cost
the runner schedule can absorb cleanly; if 5-run shows the same wide-
batch +28% the implementation needs another pass before merge.

Acceptance bar that should make this clearly mergeable:

1. 5-run release suite, candidate vs fresh baseline, with no ≥10% regression
   on Single Inserts / Batch Insert (10k) / Wide Batch Insert / Stream
   Churn.
2. CI green.

If 5-run still shows wide-batch regression beyond noise, the most likely
cause is the dispatch wrapper losing its hoisted-check optimization in
release builds; the fix would be to specialize the batch loop with two
top-level branches (positional vs named) instead of routing every per-row
bind through the inline dispatch helper.

## Future Notes

If named binding sees real production traffic, two follow-ups are worth
profiling:

1. Cache `name → bind_index` in the statement cache entry. Today every
   bind calls `sqlite3_bind_parameter_index` which walks the statement's
   parameter list. For a stmt rebound many times with the same map shape,
   a per-entry `(name → idx)` cache would replace the strcmp walk with a
   hash lookup. Only worth doing once a profile shows it.
2. The 32-byte named struct could be shrunk to 24 bytes by storing the
   name as a tail-block offset rather than a 64-bit pointer — matching
   the positional layout — at the cost of one extra address-decode in
   `bind_params_named`. Skip unless the wire format width shows up as
   a memory constraint.

If a future named-parameter use case wants to pass the same map to many
back-to-back queries (e.g. batched `update where id=:id` with stable
keys but varying values), pre-encoding the buffer once and re-binding
values into the existing layout could save a lot of utf8.encode work on
the names. Out of scope for this experiment.
