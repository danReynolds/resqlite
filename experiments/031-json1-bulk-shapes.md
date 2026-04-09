# Experiment 031: JSON1 Bulk Shapes

**Date:** 2026-04-08
**Status:** Rejected

## Hypothesis

SQLite's JSON1 extension can trade many bound parameters for one JSON payload.
That could help `resqlite` in two places where host-side overhead still matters:

- large structured batch inserts
- large `IN (...)` reads

The most important question was not just "is JSON1 fast?", but:

1. does it beat the existing bind path when JSON encoding is included?
2. does it only help when the payload is already available as JSON?

## Change

Added a targeted experiment script:

- [json1_bulk_shapes.dart](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/experiments/json1_bulk_shapes.dart)

It measures three variants for each workload:

1. current bind-heavy baseline
2. JSON1 with `jsonEncode(...)` inside the measured path
3. JSON1 with a pre-encoded payload

Workloads:

- insert 5000 customer rows
- read 1000 ids
- read 5000 ids

The JSON1 shapes use `json_each(?)`:

```sql
WITH rows AS (
  SELECT
    json_extract(value, '$[0]') AS name,
    json_extract(value, '$[1]') AS email
  FROM json_each(?)
)
INSERT INTO customers(name, email)
SELECT name, email FROM rows
```

and:

```sql
SELECT id, name, email
FROM customers
WHERE id IN (SELECT value FROM json_each(?))
ORDER BY id
```

## Results

Two process-level runs showed the same overall pattern even though the insert
baseline was noisier than the read cases.

### Run 1

| Workload | Baseline | JSON1 + encode | JSON1 + pre-encoded |
|---|---:|---:|---:|
| Insert 5000 rows | 3.49ms | 4.22ms | 2.87ms |
| Read 1000 ids | 0.60ms | 0.76ms | 0.39ms |
| Read 5000 ids | 1.78ms | 2.19ms | 2.00ms |

### Run 2

| Workload | Baseline | JSON1 + encode | JSON1 + pre-encoded |
|---|---:|---:|---:|
| Insert 5000 rows | 8.30ms | 4.30ms | 3.10ms |
| Read 1000 ids | 0.81ms | 0.67ms | 0.42ms |
| Read 5000 ids | 2.78ms | 2.37ms | 2.20ms |

### Interpretation

The directional signal is clearer than the raw numbers:

- **Pre-encoded JSON can be competitive or better**.
  - strongest on insert and 1000-id reads
- **Encoding inside the measured path usually erases most of the win**.
  - sometimes still competitive
  - not reliably better than the normal bind path
- **For very large `IN (...)` reads, JSON1 is mixed even pre-encoded**.
  - it improved one run
  - it still lost the other

So the real win is not "JSON1 beats binds". The real win is:

> when the app already has the payload as JSON, JSON1 can sometimes replace a
> lot of host-side bind overhead cheaply.

That is a much narrower claim.

## Decision

**Rejected** as a default `resqlite` runtime optimization.

Reasons:

- not a clear general-purpose win
- too workload-specific
- the best results depend on already having a JSON payload
- baking this into the runtime would add complexity for something that is
  better expressed at the query layer

## Takeaway

JSON1 is still a useful tool, just not a blanket optimization.

The practical guidance is:

- keep normal binds as the default fast path
- consider JSON1 selectively for:
  - very large `IN` lists
  - bulk structured inserts
  - cases where the payload is already JSON for app/protocol reasons

That makes it a query-shape optimization, not a `resqlite` architecture change.
