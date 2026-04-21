# Feasibility: deeply-immutable `ResultSet` for zero-copy isolate transfer

**Date:** 2026-04-21
**Status:** Blocked — re-check when `UnmodifiableTypedData`-style factories land
**Verdict:** **Not ready to prototype.** The pragma itself is stable, but the set of types Dart currently accepts as deeply immutable does not include `List<Object?>` or `Uint8List`. Both are structural requirements of our `ResultSet` shape.

---

## 1. SDK status

- `pubspec.yaml` pins `environment.sdk: ^3.10.4`.
- I could not execute `dart --version` in this worktree (Bash denied), but the constraint floor is 3.10.4.
- `@pragma('vm:deeply-immutable')` is documented in `runtime/docs/pragmas.md` under **"Pragmas for general use"** ("part of the VM's API and are safe for use in external code"). It is not gated behind an experimental flag and does not require `dart:_internal`. It has shipped for several releases.
- The broader *shared-memory multithreading* work (SDK issue #56841, language proposal 333) is still in-progress; the pragma is the one piece that has already stabilized.
- A runtime probe (declare a class, annotate it, send across `SendPort`) was not executed because Bash is denied in this environment. The existing scratch probe at `overnight-experiments/deeply_immutable_bench.dart` already uses the pragma on a class whose fields are all `String` / `int` — the likely-to-compile case. A follow-up probe under full `dart` access should confirm compilation and round-trip.

## 2. Constraints on what can be marked (from the design doc)

A class annotated `@pragma('vm:deeply-immutable')` must:

- Be `final` or `sealed`.
- All subtypes must also be deeply immutable.
- Supertype must be deeply immutable (except `Object`).
- All instance fields: `final`, non-`late`, and typed with a **deeply-immutable** or function type.

The **closed** list of deeply-immutable types today:

- `bool`, `int`, `double`, `Null`, `String`
- `Float32x4`, `Float64x2`, `Int32x4`
- `Pointer<T>`
- Any class with the pragma
- Type parameters bound by the above

**Explicitly NOT on the list:** `List<T>`, `Map<K,V>`, `Set<T>`, `Uint8List`, `Int64List`, any typed-data list, any `Iterable`. `List.unmodifiable` produces a *shallow-immutable* list (different VM bit) which is not the same thing and currently does not participate in zero-copy transfer in the same way.

SDK issue #50068 ("API to create deeply immutable typed data") is open and unresolved: the VM supports deeply-immutable typed data internally (via an embedder API), but no public Dart factory exists to produce one.

## 3. How our current shape conforms

`lib/src/row.dart`:

```dart
final class ResultSet with ListMixin<Row> {
  final List<Object?> _values;   // BLOCKS: List is not DI
  final RowSchema _schema;        // RowSchema has List<String> + Map<String,int> — both BLOCK
  final int _rowCount;
}
final class Row with MapMixin<String, Object?> {
  final List<Object?> _values;   // BLOCKS
  final RowSchema _schema;        // BLOCKS
  final int _offset;
}
```

`lib/src/query_decoder.dart`:

```dart
final class RawQueryResult {
  final List<Object?> values;    // BLOCKS
  final RowSchema schema;         // BLOCKS
  final int rowCount;
  final int estimatedBytes;
}
```

Cell payload types produced by `decodeQuery` include `Uint8List` for BLOB columns (line ~269). `Uint8List` is **not** deeply immutable, so even a hypothetical "immutable `List<Object?>`" would fail deep immutability the moment a blob row appears.

The worker message tuple sent via `SendPort.send` / `Isolate.exit` in `lib/src/reader/read_worker.dart` is a `Record` containing the `ResultSet` (or a nested record with it). Records themselves are not in the deeply-immutable set either — the design doc doesn't carve out record types.

## 4. Ecosystem survey

- No existing uses of `vm:deeply-immutable` in this repo other than `overnight-experiments/deeply_immutable_bench.dart` (the probe scratch file).
- Pub.dev search (via WebSearch) surfaced no packages that use the pragma in shipped code. It is almost entirely an internal VM concept today, with a handful of experimental users inside `dart-lang/*`.

## 5. Blocker assessment

Two independent hard blockers:

1. **No deeply-immutable list type.** `ResultSet` and `RawQueryResult` are centered on `List<Object?>` and `RowSchema.names` is `List<String>`. Without a DI list, nothing above them can be marked. Replacing the backing list with a chain of DI records (one DI class per value, linked) would explode object count, lose flat-list cache locality, and almost certainly regress the shape exp 082 just showed is near-optimal.
2. **No deeply-immutable `Uint8List`.** BLOB cells are `Uint8List`. Even if we solved blocker 1, blobs would block. SDK #50068 is the upstream tracking issue.

Blocker 1 is the structural one. Blocker 2 is a subset of it.

## 6. Verdict and upstream watch

**Blocked. Re-check when either:**
- a public `List.deeplyImmutable` / `UnmodifiableTypedData.fromCopy` factory ships (track SDK #50068), **or**
- the "shared isolates" phase of language proposal 333 lands with a broader zero-copy send path for shallow-immutable graphs (track SDK #56841).

Until then, the ~0.05 ms `memcpy` cost for our sub-256 KB results is not worth a restructuring that would fight the language. Exp 082 already showed current shape wins at 10 k rows both on `SendPort.send` and `Isolate.exit`. The sacrifice-threshold machinery (exp 039) stays.

## 7. Low-cost follow-ups worth doing now

- Confirm under real `dart` access that `overnight-experiments/deeply_immutable_bench.dart` compiles and that `SendPort.send` of the `ImmutableResult` (three `String` + two `int` fields) measurably beats an equivalent mutable class. This pins down whether the same-group zero-copy path actually activates, giving a numeric ceiling for any future refactor.
- Subscribe / poll SDK #50068 quarterly. The day a DI typed-data factory ships, blocker 2 dissolves.

## 8. If blocker 1 ever lifts — minimal refactor sketch

Breadth estimate: ~4 files, ~150 LoC, one new cell-storage abstraction, full test suite should pass unchanged because the `Map`/`List` facades don't change.

```dart
@pragma('vm:deeply-immutable')
final class ImmutableRowSchema {
  final ImmutableList<String> names;              // needs DI List
  final ImmutableMap<String, int> indexByName;    // needs DI Map
  ImmutableRowSchema(this.names, this.indexByName);
}

@pragma('vm:deeply-immutable')
final class ImmutableResultSet {
  final ImmutableList<Object?> values;            // needs DI List<Object?>
  final ImmutableRowSchema schema;
  final int rowCount;
  final int estimatedBytes;
  ImmutableResultSet(this.values, this.schema, this.rowCount, this.estimatedBytes);
}
```

Files that would touch: `lib/src/row.dart`, `lib/src/query_decoder.dart`, `lib/src/reader/read_worker.dart`, `lib/src/writer/writer_worker.dart`. Blob cells would need a `ImmutableBytes` wrapper once #50068 ships. `selectBytes` is unaffected — it already transports a single `Uint8List` via the raw bytes path.

---

**Word count:** ~690
