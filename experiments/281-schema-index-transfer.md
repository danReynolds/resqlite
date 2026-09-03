# Experiment 281: the lookup table that rides on every read

**Date:** 2026-09-03
**Status:** PENDING
**Direction:** `result-transfer-shape`
**Benchmark Run:** PENDING

## Problem

[Exp 279](279-native-thread-dispatch.md) closed the question of *what vehicle*
carries a read — a POSIX worker thread is 2–3 µs slower than a Dart isolate, and
the isolate round trip is not the thing to replace. On the way it split
[claim 265.1](265-inline-main-isolate-select.md)'s 6.3 µs hop in two: 3.22 µs is
transport, and the other ~3.1 µs is resqlite's own per-request work on the two
sides of the messages (claim 279.3). It also flagged its own reply lane as a
floor — it sent "plain lists rather than `Row` facades" — and named the
decomposition of that remaining half as the next thing to do.

The real reply is not plain lists. `SelectRequest` comes back as a `ResultSet`
holding a `RowSchema`, and until this experiment `RowSchema` built a
`HashMap<String, int>` from its column names **in its constructor**:

```dart
RowSchema(this.names) : _indexByName = HashMap<String, int>() {
  for (var i = 0; i < names.length; i++) {
    _indexByName[names[i]] = i;
  }
}
```

A worker caches one `RowSchema` per SQL string, so that map is *built* once. But
the schema travels with every result, and `SendPort.send` copies the graph it is
handed. A `HashMap` copies as one object per entry plus its bucket array. So
every single `select()` — the library's most common operation, with no
eligibility condition of any kind — paid to ship a lookup table across the
isolate boundary that most results never consult, and that the receiver throws
away microseconds later.

## Hypothesis

**Assumption challenged:** that a per-SQL cache on the worker makes the schema
free. It makes the *construction* free. What crosses the boundary is charged per
read regardless of how long the sender kept it.

Building the index on first use instead of in the constructor should remove it
from every read's payload, at the cost of one `O(columns)` build on the
receiving side — and only for a caller who looks a column up by a name the
identity fast path ([exp 158](158-row-schema-hash-index.md),
[exp 176](176-row-containskey-identity-fastpath.md)) cannot resolve.

Decision rule set before building:

- **Accept** if the wire saving is reproduced in both orders on real reads at
  the widths results actually have, the lookup guards stay at the collection
  floor, and no read shape is made materially worse.
- **Reject** if the per-lookup cost of a nullable field shows up on
  consumption-heavy reads at a size that outweighs the once-per-read saving.

## Approach

`lib/src/row.dart` only. `RowSchema._indexByName` becomes a nullable field built
by the first lookup the identity scan cannot answer:

```dart
int indexOf(String name) {
  if (names.length <= _identityLookupMaxColumns) {
    for (var i = 0; i < names.length; i++) {
      if (identical(names[i], name)) return i;
    }
  }
  final index = _indexByName;
  if (index == null) return _buildIndexAndLookUp(name);
  return index[name] ?? -1;
}
```

Two details are load-bearing and both were measured, not assumed. The build is
in an `@pragma('vm:never-inline')` sibling, so the steady-state path stays a
load, a never-taken branch and a probe; folding it in as
`(_indexByName ??= _buildIndex())[name]` cost every *later* lookup, which showed
up as a reproduced regression on the thousand-row lane. And the field is typed
as the concrete `HashMap` rather than `Map`, so the probe keeps the receiver
type the old `final` field gave it.

Nothing else changes. The identity scan, its 32-column cap, `containsName`, and
the map's behaviour once built are all exactly as they were, so exps 158 and 176
keep their wins intact. The public surface is unchanged: `RowSchema`'s
constructor, `names`, `columnCount`, `indexOf` and `containsName` are the same.

### Two new harnesses

`benchmark/experiments/schema_index_transfer.dart` prices the mechanism with no
database and no resqlite code: one echo isolate, and lanes that differ only in
whether the schema carries a map. It also prices the three lookup forms and the
build itself, and it is where three candidate designs were compared before one
was written.

`benchmark/experiments/schema_index_read_ab.dart` is the end-to-end A/B: point,
wide and thousand-row reads, each with and without by-name consumption, plus a
`selectBytes` lane and a write lane as zero-ceiling controls and direct
`RowSchema.indexOf` lanes as the per-lookup guard.

## Results

### The map is the whole cost of sending a schema

`schema_index_transfer.dart`, two order-flipped passes, 11 samples × 2,000 round
trips, AOT. The lanes differ in one field: whether the schema carries a
`HashMap`.

| lane | with map | no map | the map's price |
|---|---:|---:|---:|
| 6 columns | 3.428 / 3.330 µs | 3.124 / 3.092 µs | **+0.30 / +0.24 µs** |
| 21 columns | 4.363 / 4.316 µs | 3.192 / 3.144 µs | **+1.17 / +1.17 µs** |
| 40 columns | 4.974 / 4.945 µs | 3.187 / 3.133 µs | **+1.79 / +1.81 µs** |

The no-map lanes are *flat at ~3.15 µs across all three widths*, which is the
finding underneath the finding: the column-name list is free to send. Strings
cross a same-group boundary by reference (claim 245.1), so a 40-column schema
and a 6-column schema cost the same to ship — right up until you attach a map,
which copies as one object per entry and scales with width. Every microsecond in
that right-hand column was being spent on a structure the receiver frequently
never touches, on the library's most frequent operation.

Building one on demand costs **95 ns at 6 columns, 322 ns at 21, and 617 ns at
40** — between a third and a quarter of what shipping it costs, and paid once
per result set rather than once per read.

### End to end, the wide reads move and nothing else breaks

`schema_index_read_ab.dart`, two AOT bundles from separate worktrees, each lane
in its own process, 41 samples after 8 warmup, three collections of
order-flipped passes (six passes; candidate against base within each pass).

| lane | six passes (Δ%) | median |
|---|---|---:|
| `wide40` | −22.2 −14.8 −22.8 −22.0 −23.9 −22.6 | **−22.4%** |
| `wide21` | −9.5 −5.4 −12.4 −11.9 −13.2 −13.0 | **−12.1%** |
| `wide21-literal` | −6.8 −4.2 −2.6 −4.9 +0.3 −6.4 | −4.6% |
| `point1-interned` | −2.1 −2.3 −5.0 −3.1 −9.3 −3.2 | −3.2% |
| `point1-literal` | −2.8 −4.2 −1.3 −1.5 −10.2 −0.5 | −2.2% |
| `point1` | +5.9 −4.3 +32.3 −3.6 −2.4 −4.2 | −3.0% |
| `rows1k-literal` | +1.3 +0.1 −1.0 −1.6 +0.2 −1.6 | −0.5% |
| `bytes1` (control) | −3.2 −0.4 +28.6 +2.2 −3.2 +3.9 | +0.9% |
| `writes` (control) | −1.9 −1.7 −10.1 −8.2 +6.2 −1.8 | −1.9% |

**A wide read gets a fifth of its time back.** `wide40` reproduces −22% in all
six passes and `wide21` −12% in the last four — both far outside anything the
controls do, and both within noise of the arithmetic: 1.8 µs off a 6.6 µs read
is 27%, 1.17 µs off 5.3 µs is 22%, and the shortfall is the per-read work the
saving does not touch.

**The point-read lanes are at the floor and lean the right way.** The predicted
saving there is 0.27 µs against a ~4.8 µs read — about 5.6%, which is the same
order as this collection's resolution. `point1-literal` and `point1-interned`
came out negative in all six passes, which is worth more than either median,
but the two zero-ceiling controls settle how much to claim: `bytes1` builds no
`RowSchema` at all and `writes` never crosses one, and they range over −10% to
+29%. This harness resolves the wide lanes and does not resolve the point lanes;
the mechanism harness is what prices those.

**The thousand-row lane is the trade, and it comes out even.** `rows1k-literal`
does 6,000 by-literal lookups against one build and one saved map, and reads
−0.5% across six passes. That is the check that mattered: the saving is
per-read and the tax is per-lookup, so a large result consumed entirely by name
is where the exchange could have gone negative. It does not.

### The per-lookup tax is real, sub-nanosecond, and only on one path

The lookup lanes call `RowSchema.indexOf` directly — no database, no isolate,
200,000 lookups against one schema — so they are the most stable numbers in the
run and they price what a nullable field costs the probe.

| lane | six passes (Δ%) | median | absolute |
|---|---|---:|---:|
| `lookup-literal-6` | +1.5 +1.2 +2.1 +1.5 +1.5 +1.6 | +1.5% | +0.28 ns |
| `lookup-literal-21` | +3.5 +2.4 +2.2 +2.2 +3.6 +3.9 | +3.0% | +0.83 ns |
| `lookup-literal-40` | −2.0 −1.4 +0.1 +0.1 −0.5 −0.1 | −0.3% | — |
| `lookup-interned-6` | +0.0 −2.8 +0.4 −0.2 −2.8 +0.0 | −0.1% | — |
| `lookup-interned-21` | −2.3 −1.3 −0.3 +0.4 +0.1 +0.1 | −0.1% | — |
| `lookup-miss-6` | −1.1 +0.8 +0.7 +0.9 −0.9 +0.8 | +0.8% | — |

The identity path is untouched, as it must be — exps 158 and 176 built it and
this change does not go near it. A lookup that reaches the index pays under a
nanosecond for the extra load and branch. That is the price of the whole
mechanism, and it buys 0.3–1.8 µs per read.

It was not free to get there. The first implementation wrote the natural
`(_indexByName ??= _buildIndex())[name]`, and `rows1k-literal` reproduced +1.1%
and +4.0% against base — the inlined build had cost the *steady-state* probe
enough to outweigh the saving 6,000 times over. Moving the build into a
`vm:never-inline` sibling took that lane to −0.5%.

### An assumption in the code was wrong, and now it is measured

`RowSchema.containsName`'s doc comment claimed the identity scan serves "the
common case, e.g. a literal column name". It does not, and cannot: decoded
column names come from `String.fromCharCodes` and are never canonicalized, so
`identical(row.keys.elementAt(1), 'name')` is **false** on a real read. Exp 176
predicted this in its signal entry and no one wrote it into the code; a test now
pins it. The idiomatic `row['name']` has always paid the full hash probe, which
is exactly why the index still has to exist — and why building it lazily rather
than deleting it is the right shape.

## Decision

**Accepted.** A `HashMap` that no result needs at the moment it crosses the
isolate boundary no longer crosses it. Wide reads — 21 and 40 columns — return
12% and 22% faster, reproduced in every pass of three order-flipped collections;
point reads gain a measured 0.27 µs of hop that this harness cannot resolve but
the mechanism harness prices directly; a thousand-row result consumed entirely
by column name is unchanged. There is no eligibility condition: every
`select()`, `selectWithDeps` and changed `selectIfChanged` emission in the
library carries a schema, so this is one of the few wins in the direction that
applies to all of them.

The cost on `main` is one nullable field, one never-taken branch, and one
out-of-line method in `lib/src/row.dart`. No public API changes.

### What this does not do

It does not touch `selectBytes`, which builds no `RowSchema` at all — the
`bytes1` control is there to prove it. It does not change any lookup's answer.
And it does not help a result read purely by position or by count, beyond
removing the map from its payload, because that result never had a lookup to
speed up.

### Reopen conditions

Two things would put the map back on the wire. If a *worker* ever looked a
column up by name — a worker-side filter, a column-aware hash, a decode that
consults the schema — its cached `RowSchema` would materialize an index and
resume shipping it on every read, silently. `resultSetHasNameIndex` and the test
around it exist to catch that.

And if `_identityLookupMaxColumns` is ever raised past 32 (exp 158's sweep put
the crossover between 32 and 48), the identity scan would start covering wider
schemas, which changes how often the index is built at all — re-run
`schema_index_read_ab.dart`'s lookup lanes with that sweep, not just exp 158's.

A third design was measured and left on the table. Replacing the map with a flat
`Uint32List` of the names' hash codes ships for free — the `digest` lanes match
the no-map lanes at every width, because typed data crosses as one buffer — and
resolves a literal lookup without an index at all. It was not taken because it
is slower on every lookup the identity scan does not catch (54.9 ns against
30.9 ns for a 40-column miss) and it would have replaced a structure whose
behaviour is understood with one that is not. It is the fallback if the lazy
build ever proves to be in the wrong place.
