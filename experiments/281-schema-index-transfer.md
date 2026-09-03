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

PENDING

## Decision

PENDING
