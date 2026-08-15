# Experiment 272: trace the SQL UTF-8 cache boundary

**Date:** 2026-08-15
**Status:** Rejected
**Category:** Measurement
**Direction:** `result-transfer-shape`
**Benchmark Run:** none (no runtime code ships). The product-incidence trace is
recorded in
[`benchmark/results/2026-08-15T10-22-43Z-exp272-sql-utf8-cache-incidence.md`](../benchmark/results/2026-08-15T10-22-43Z-exp272-sql-utf8-cache-incidence.md).

> **Rejected: premise refuted in the measured product flows.** Three captured
> Dune flow traces spanning five test lifecycles produced 911 SQL-pointer-cache
> accesses across 25
> reader/writer isolate lifetimes. All 316 repeated accesses had one-based LRU
> rank at most 32. Expanding the cache from 32 to 128 would therefore have
> rescued zero of 595 misses and avoided zero UTF-8 conversions in these
> traces. The temporary tracer is removed and no runtime change ships.

## Problem

[Exp 267](267-stmt-cache-capacity.md) raised three SQL-keyed caches from 32 to
128: the native prepared-statement cache, each worker's schema cache, and the
pool's row-size memory. Its synthetic cyclic workload established a sharp
capacity cliff (claim 267.1). One adjacent cache did not move:
`cachedSqlUtf8` in `lib/src/native/request_cache.dart` still retains 32 native
UTF-8 pointers per isolate.

Every cacheable query or DML statement that reaches the native statement cache
routes its SQL through that helper; a helper miss converts it before native
lookup. A workload whose per-isolate reuse rank is 33-128 can therefore hit the
128-entry statement/schema/hint caches while repeatedly allocating and freeing
the SQL pointer used to look them up. Raising one constant to 128 is
mechanically plausible and has little code complexity.

The missing fact was incidence. Total distinct SQL is not the relevant number:
the cache is isolate-local and LRU, so the candidate needs frequent *repeated*
SQL at one-based LRU rank 33-128 (32-127 distinct identities intervening). The
August 13 runner had already declined this change until a downstream trace
supplied that fact. Exp 267's all-cyclic pressure harness supplies an eligible
workload and proves the adjacent statement-cache cliff; it never timed this
UTF-8 pointer-cache cap or its per-miss saving.

## Hypothesis

The candidate was eligible for implementation only if a downstream trace
showed accesses at one-based reuse rank 33-128. That population would then be
replayed against 32- and 128-entry LRUs, combined with measured conversion/free
cost, and followed by an order-flipped AOT implementation A/B only if predicted
representative wall impact reached 3%.

The gate deliberately came before timing. With no rescued accesses,
`frequency × eligible share × per-miss saving` is exactly zero in the measured
flows. A synthetic 40/64/128-statement rotation could still make the helper
look faster, but it could not establish aggregate product value.

## Approach

A temporary trace point was placed inside `cachedSqlUtf8`, after its real LRU
lookup. Each access emitted:

- process ID, isolate role/name and isolate identity;
- a monotonic per-isolate sequence number;
- the actual 32-entry-cache hit bit;
- UTF-8 byte length; and
- a collision-free base64 encoding of the SQL bytes.

The retained offline
[`sql_utf8_cache_trace_analyze.dart`](../benchmark/experiments/sql_utf8_cache_trace_analyze.dart)
groups events by process and isolate, computes the exact one-based LRU stack,
and replays capacities 32 and 128. Its anonymized
[`event stream`](../benchmark/results/2026-08-15T10-22-43Z-exp272-sql-utf8-cache-events.tsv)
replaces SQL bytes with per-isolate opaque IDs while retaining order, byte
length, actual hit bit and computed reuse rank, so the aggregate remains
auditable without publishing application queries.

The trace ran three normal Dune product flows against this checkout through
Dune's existing sibling `dependency_overrides` path:

1. admin onboarding, including database open/migration and two onboarding
   paths;
2. message round-trip, including identity, send/sync, receipt, reactions,
   reaction removal and message deletion; and
3. canvas sync and object lifecycle, including local reads, encrypted remote
   sync, edits and deletion.

All five tests passed. The synchronous tracer was then removed; the branch
contains no runtime or test-only instrumentation. The offline analyzer and
anonymized replay stream remain as the durable reproduction and reopening gate.

## Results

| Dune flow | isolate lifetimes | accesses | first-touch misses | reuse 1-32 | reuse 33-128 | misses at 32 | misses at 128 |
|---|---:|---:|---:|---:|---:|---:|---:|
| admin onboarding | 10 | 201 | 191 | 10 | **0** | 191 | 191 |
| message round-trip | 5 | 318 | 139 | 179 | **0** | 139 | 139 |
| canvas sync/lifecycle | 10 | 392 | 265 | 127 | **0** | 265 | 265 |
| **total** | **25** | **911** | **595** | **316** | **0** | **595** | **595** |

The result is not merely that these flows use few statements. The
message-round-trip writer saw 77 unique SQL identities in 146 accesses. Each
canvas writer saw 79 unique identities. Those lifetimes exceed the current
capacity in total diversity, but every reuse still occurred within the most
recent 32 identities. Cold migration and feature breadth raise the unique
count; they do not create a reusable working set beyond the cache.

The 32-entry cache hit 316 times and missed 595 times. A 128-entry replay hit
the same 316 times and missed the same 595 times, so its incremental hit rate
was **0.0%** and the SQL bytes attached to rescued misses were **0**. There is
no eligible per-hit saving to time in these traces. Replay matched the real
32-entry hit bit on all **911/911** events; sequences began at zero with no gap
or duplicate, every encoded SQL identity decoded to its recorded byte length,
and the maximum observed one-based rank was only 19 (admin 9, message 19,
canvas 16), well below the boundary.

## Decision

**Rejected under the premise-refuted measurement escape.** The cap mismatch is
real, and a deliberately cyclic 33-128-statement workload remains sufficient
to exercise it. These downstream flows show no access that the larger cache
could rescue, however. Implementing the one-line cap change and benchmarking
only that synthetic shape would violate the value-before-mechanism gate.

No library, native, build-hook, or public-API code is retained. No prototype
archive is needed because the candidate constant was never changed. The
temporary tracer and SQL-bearing logs are not publication artifacts; only the
offline analyzer and anonymized replay stream remain.

This result refines rather than overturns claim 267.1. Exp 267 established that
an actual cyclic working set beyond a cache cap is expensive. Exp 272 shows
that total SQL diversity—even 79 unique statements in one writer lifetime—is
not evidence that this adjacent 32-entry cache sees that working set.

### Reopen conditions

Do not retry the cap change from the synthetic pressure harness alone. Reopen
the investigation only when a longer, lower-perturbation downstream trace,
measured separately per reader and writer isolate, reports at least one access
at rank 33-128 and includes:

1. request-weighted reuse ranks 33-128, not merely total or unique SQL;
2. the miss-rate reduction from replaying the trace at 32 and 128;
3. access frequency and rescued SQL byte lengths, so aggregate allocation
   saving can be estimated; and
4. a bounded retained-memory estimate for `(candidate cap - 32)` additional
   strings and native buffers per isolate (96 when testing cap 128).

Implement only if `call frequency × rescued share × measured conversion/free
saving` predicts at least 3% representative wall impact. Then run the smallest
trace-supported cap in two independent order-flipped AOT pairs and require at
least 3% in both orders of each pair. Reuse-rank-at-most-32, point-read, unique
churn and above-cap controls must show no reproduced regression of 3% or more;
RSS must stay bounded. These short synchronous-logger traces
observe only the current Dune process, not buffered spawned-peer stderr. The
logger can extend worker busy time and change availability-based reader
assignment, so the reader result describes the captured instrumented routing;
the serialized FIFO writer sequences are stronger. This is not hours-long dogfood,
and a broader trace can legitimately reopen the conclusion.
