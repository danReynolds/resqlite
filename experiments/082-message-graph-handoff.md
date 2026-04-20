# Experiment 082: Isolate message-graph benchmark for result payloads

**Date:** 2026-04-20
**Status:** Rejected (optimization hypothesis disproven; benchmark harness kept)

## Problem

After several result-storage experiments, it was still unclear whether the
remaining headroom lived in:

- SQLite decode
- isolate hand-off
- main-isolate row consumption

Those phases were too entangled in normal `db.select()` benchmarking to
attribute wins cleanly. We needed a benchmark that isolated the message
graph itself.

## Hypothesis

If the current `ResultSet` / `Row` shape is not near-optimal, then an
isolated hand-off benchmark should show a clearly better alternative graph
shape for one or both of:

- `SendPort.send` (same-group copy path)
- `Isolate.exit` (handoff path)

Candidate graphs:

1. Current `ResultSet`
2. Fully materialized row maps
3. Binary row facade

Measured separately:

- transfer time
- main-isolate consumption time
- total time

## Approach

Added reusable benchmark harness:
- `benchmark/experiments/message_graph.dart`

The harness:

- builds synthetic result-shaped payloads without SQLite
- tests both numeric-heavy and mixed-schema data
- tests 100 / 1000 / 10000 rows
- runs both `SendPort.send` and `Isolate.exit`
- reports p50 / p90 for transfer, consume, and total
- runs in both JIT and AOT

This gives a direct answer to “is the result object shape itself still a
frontier?” without conflating decode cost.

## Results

Artifacts:
- JIT: `/tmp/resqlite-exp097-jit.txt`
- AOT: `/tmp/resqlite-exp097-aot.txt`

The AOT run is the most important signal because it matches shipped
Flutter runtime behavior.

### AOT examples

#### Numeric-heavy, `SendPort.send`, 1000 rows

| Shape | Transfer p50 | Consume p50 | Total p50 |
|---|---:|---:|---:|
| current `ResultSet` | 0.013 ms | 0.091 ms | **0.104 ms** |
| materialized maps | 0.165 ms | 0.157 ms | 0.316 ms |
| binary row facade | 0.013 ms | 0.396 ms | 0.409 ms |

#### Mixed-schema, `SendPort.send`, 10000 rows

| Shape | Transfer p50 | Consume p50 | Total p50 |
|---|---:|---:|---:|
| current `ResultSet` | 0.275 ms | 0.769 ms | **1.048 ms** |
| materialized maps | 2.021 ms | 1.266 ms | 3.345 ms |
| binary row facade | 0.080 ms | 2.482 ms | 2.566 ms |

#### Mixed-schema, `Isolate.exit`, 10000 rows

| Shape | Transfer p50 | Consume p50 | Total p50 |
|---|---:|---:|---:|
| current `ResultSet` | 1.816 ms | 0.781 ms | **2.580 ms** |
| materialized maps | 4.882 ms | 1.074 ms | 6.114 ms |
| binary row facade | 2.063 ms | 2.370 ms | 4.397 ms |

## Decision

Rejected as an optimization direction, but the benchmark harness should be
kept.

The main result is that the current `ResultSet` / `Row` shape is already
very strong for the shipped `select()` contract:

- lazy rows on the receiving isolate
- one shared flat backing list
- `Map`-compatible API

Both alternatives we tested lost on end-to-end total time once actual row
consumption was included:

- materialized maps lose on transfer/object count
- binary row facades lose on main-isolate access cost

This is a useful negative result. It means future performance work should
not keep trying to replace generic `select()` result objects unless the
API contract changes.

More promising directions from here are:

- specialized byte/typed-data APIs
- threshold / hand-off policy work
- optimizing stream/reactive work rather than generic row payloads

The harness remains valuable because it gives a clean way to test any
future result-graph idea without conflating SQLite decode, isolate
transport, and row consumption.
