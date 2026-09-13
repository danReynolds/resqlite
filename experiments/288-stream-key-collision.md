# Experiment 288: Two streams, one 29-bit key

**Date:** 2026-09-10
**Status:** Accepted
**Category:** Correctness
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** Release headline suite captured at HEAD on 2026-09-10
  (5-sample medians,
  [`benchmark/results/2026-09-10T18-51-57-exp288-stream-key-collision.md`](../benchmark/results/2026-09-10T18-51-57-exp288-stream-key-collision.md)),
  gated against the previous release anchor
  (`2026-08-09T20-36-47-exp266-headline-refresh.md`, passed explicitly because
  auto-compare picks the newest markdown in `benchmark/results/`, which was a
  focused-harness result without a sidecar): exit 0, 0 wins / 0 regressions /
  169 neutral. The decision evidence is the regression tests; the release run
  is the no-collateral-damage sweep.

## Problem

`db.stream(sql, params)` deduplicates: two calls with the same SQL and
parameters share one `StreamEntry`, one SQLite query, and one re-run per
write. The registry that makes that work was

```dart
final Map<int, StreamEntry> _entries = {};
...
final key = Object.hash(sql, Object.hashAll(params));
if (_entries[key] case StreamEntry entry) {
  return _subscribe(entry);          // no check that entry.sql/params match
}
```

`Object.hash` is 29 bits wide — [exp 033](033-fnv1a-hash.md) noted exactly
that when it retired it from *result* hashing in April, and the stream key
kept using it. A 29-bit key has 536,870,912 values, and a map keyed on the bare
integer, with no equality behind it, treats any two queries that share one as
the same query. So among the parameter values a keyed stream is asked for, two
distinct ids eventually collide, and the second subscriber is handed the first
subscriber's rows: it is seeded from the wrong `lastResult`, re-runs the wrong
SQL, and keeps receiving the wrong rows for as long as the first stream stays
open. Nothing errors and nothing is stale in a way the subscriber could notice
— the rows are current, for someone else's query.

The pair is not exotic. Searching `SELECT id, name, value FROM items WHERE id
= ?` over consecutive integer ids finds the first collision within a few tens
of thousands of values (36,683 in one process; the hash is seeded per process,
so the pair moves, the distance does not). Integer primary keys in the tens
of thousands are ordinary. Two colliding streams have to be *live at the same
time*, which is what keeps it rare: for `n` concurrent streams over the same
SQL the chance of a pair sharing a key is about `n² / 2³⁰`, roughly one in
107,000 for 100 concurrent keyed streams — per screen, per open, across every
install.
The failure is silent and self-consistent, which is the kind that survives.

`StreamEntry` also carried the same key as its `hashCode`/`==`, so the
`Set<StreamEntry>` instances the engine keeps — the per-table index, the
re-query queue, the unknown-dependencies set — could not hold both of a
colliding pair either.

A second, smaller aliasing sat in the same lookup: `1 == 1.0` in Dart and both
hash alike, so `stream('SELECT typeof(?)', [1])` and `[1.0]` shared an entry,
although they bind as INTEGER and REAL and SQLite can tell them apart.

## Hypothesis

Equality is what the hash was standing in for. Keying `_entries` by a value
object that hashes the same way and compares SQL and parameters structurally
closes the first aliasing outright, without touching how streams are
dispatched, hashed, or re-run; making `StreamEntry` identity-equal (the
default) closes the set aliasing; and distinguishing `int` from `double` in
the parameter comparison closes the second. The cost is one equality check on
a dedup hit, which no lane the suite measures can see next to the query round
trip a miss has to pay.

## Approach

`_entries` is now `Map<_StreamKey, StreamEntry>`. `_StreamKey` holds the SQL
and the parameters, hashes with the same `Object.hash(sql,
Object.hashAll(params))` the bare key used — so the two colliding pairs above
now reach the equality check instead of the wrong entry — and compares SQL
and parameters element-wise with `==`, plus `(a is double) != (b is double)`
so an integer and a double never match. `==` on the parameters is value
equality for the bindable scalars and identity for blobs, which is exactly the
set of distinctions the hash already drew, so what deduplicated before still
deduplicates.

The key stored in the map takes its own fixed-length copy of the parameter
list. A caller's list could change after `stream()` returns; the old integer
was computed once and immune, but a key that *holds* the list would not be.
The entry's `params` — what every re-run binds — is now that same copy, which
also means a mutated caller list can no longer change what a live stream
re-runs; before this that was quietly possible. The probe key built for the
lookup itself borrows the caller's list and is discarded.

`StreamEntry` loses its `hashCode`/`==` override and falls back to identity,
which is what its sets always meant.

Two regression tests in `test/stream_test.dart`:

- **`distinct queries whose dedup keys collide do not share a stream`** —
  finds a colliding pair of ids for a `WHERE id = ?` query at test time using
  the engine's own hash formula (the seed is per process, so it cannot be
  hard-coded), inserts both rows, opens a stream on each and keeps both
  subscribed, and asserts each stream reports its own id and that two entries
  are registered.
- **`an int and a double parameter are different streams`** — `typeof(?)`
  bound with `1` and with `1.0`, expecting `integer` and `real` from two
  entries.

## Results

| | without fix | with fix |
|---|---|---|
| colliding-key regression test | fails — stream for id 27098 receives row 25336; 1 entry registered | passes |
| int-vs-double regression test | fails — `[1.0]` stream reports `integer`; 1 entry registered | passes |
| `test/stream_test.dart` | — | 34 / 34 |
| stream, database, write-coalescing, trigger-cascade, reader-pool, transaction, dependency-shape, cache-hit, invalidation-coalescing, overflow-fallback, encryption, stmt-cache-pressure suites | — | 167 / 167 |

The price of the key, measured in isolation (AOT, a map holding 100 live
streams, 2M lookups per lane, no database):

| lane | bare `int` key | `_StreamKey` |
|---|---|---|
| dedup hit | 35 ns | 106 ns |
| miss, then register (includes the parameter copy) | 38 ns | 75 ns |

+70 ns on a hit and +37 ns on a miss. A hit goes on to allocate a
`StreamController` and seed it; a miss goes on to a reader-pool round trip
that [exp 282](282-read-request-residual.md) prices at 3.27 µs (claim 282.2) before any
SQLite work. Neither is visible from any public lane, and the headline suite
is the no-collateral-damage sweep rather than the decision evidence.

The headline release run from the committed tree (`--repeat=5
--fail-on-regression --fail-on-memory-regression`, compared explicitly
against the last release anchor, exp 266's 2026-08-09 refresh) exited 0 with
**0 wins, 0 regressions, 169 neutral** resqlite lanes. Every streaming lane
— the ones this change could touch — reads flat: high-cardinality fan-out,
keyed-PK, feed paging, many-streams writer throughput, and both column-
granularity rows (resqlite re-emits 0 disjoint / 10 overlapping, identical to
the anchor). The comparison's two flagged re-emit rows (−134 / +673) are the
`sqlite_async` peer's counts, not resqlite's. `check_peer_drift.dart
--since=2026-08-09` puts the apparatus movement across the month at a −2.6%
median with 71% lane agreement — within tolerance, so the resqlite deltas
are comparable despite the anchor's host being recorded under a different
hostname. The anchor carried no memory section, so the memory gate had no
baseline; this run's values are recorded for the next one.

## Decision

**Accepted.** A silent, self-consistent wrong-rows bug in the library's
primary feature, closed at the registry with no change to dispatch, hashing,
or re-run behaviour, no public API change, and a hot-path cost that is two
digits of nanoseconds against a microsecond round trip.

## Why this and not a performance candidate

The run's shortlist, for the record:

1. **This.** Found while reading the stream registration path for churn cost;
   confirmed by construction in under a minute.
2. **Exp 283's named reopen** — a one-pass changed re-run with a cheap
   freshness re-check instead of the second walk. Deferred: claim 283.4 puts
   the win at −11.3% on 20 streams over 1,000-row partitions and nothing
   measurable at 100 rows, and no representative workload streams
   thousand-row results that change often.
3. **`Database.open` cold-start.** No lane measures it, and every app pays it
   once per launch. Probed in AOT: `open` returns in 689 µs median (611 min)
   and the first read after it completes 157 µs later, so the whole pool spawn
   plus first query is under a millisecond. There is no per-launch cost worth
   an optimization's complexity; recorded as claim 288.3 so it is not probed
   again.

## Future notes

- The identity-hashed `Uint8List` blob parameter never deduplicated and still
  does not; two streams bound with equal-content blobs run twice. That is the
  pre-existing behaviour, and content-hashing blobs on every `stream()` call
  is the wrong trade for a case with no evidence behind it.
- Any future registry that keys on a hash — a SQL-keyed cache, a
  dependency index — should carry the equality it stands in for. The
  per-connection C statement cache compares SQL bytes; the Dart-side schema
  and row-size caches key on the `String` itself. This was the only bare-hash
  key in the runtime.
