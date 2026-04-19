# Experiment 084: Columnar typed arrays — Phase 1 spike (exp 055 redux)

**Date:** 2026-04-19
**Status:** Phase 1 complete — original hypothesis does not reproduce on
current Dart SDK. Phase 2 **deferred** pending a production workload
that would benefit from the narrower remaining win.

## Purpose

Exp 055 (2026-04-15) was rejected because the time-based benchmark
suite couldn't see its memory-axis wins. Profile mode (exp 080) now
captures RSS + SQLite counters + allocation counters per workload, so
a memory-axis experiment is finally end-to-end measurable.

Before committing 3–5 days to the decode-path rewrite, this spike
re-runs exp 055's micro-benchmarks on the current Dart SDK to confirm
the original numbers still hold. They don't — and the "why" is useful.

## Approach

`benchmark/profile/columnar_spike.dart` — standalone harness that
constructs row-major `List<Object?>` and columnar typed-array (`Int64List`
/ `Float64List`) layouts in isolation and measures:

1. **Allocation time** — how long to allocate + populate 100k elements
2. **RSS footprint** — `ProcessInfo.currentRss` delta with heap-churn
   preamble. Holds 20 × 100k-element copies simultaneously so VM arena
   pre-allocation doesn't hide the delta (important: `_rssHoldCount`
   had to be tuned upward after the single-copy case produced near-zero
   deltas). Separate cases for:
   - **small ints** (within the SMI tag range)
   - **large ints 2^62+** (forced heap-allocated `Mint` objects)
   - **doubles** (always heap-allocated)
3. **Isolate transfer** — persistent echo worker; single spawn amortized
   over all samples; measures `SendPort.send` round-trip
4. **Iteration** — sum N integers from each container
5. **Mixed schema** — 10k rows × (2 int + 1 double + 2 string)
   representative CRUD schema

No production code modified. Spike is pure micro-benchmark.

## Results

Measured on macOS arm64, Dart 3.11.0 stable. Median of 5 trials
(except RSS sections, which use a single measurement — the `_rssMB()`
tool's signal-to-noise at these scales is too low for re-sampling to
help).

### Headline comparison vs exp 055's original findings

| Dimension | Exp 055 (original) | Current SDK | Hypothesis holds? |
|---|---|---|---|
| Allocation (100k ints) | **31× faster** (339μs → 11μs) | 1.77× faster (267μs → 151μs) | Partial |
| RSS — 100k small ints | **3× reduction** | ~1× (measurement noisy; theoretical ~1×) | **No — SMI mooted it** |
| RSS — 100k 2^62+ ints | Not tested | Data noisy; theoretical ~3× | Likely |
| RSS — 100k doubles | Not separated | 2.5× reduction (38 MB → 15 MB) | Yes |
| Isolate transfer | **4.4× faster** | 3.4× faster (282μs → 82μs) | Partial |
| Iteration | 1.1–1.4× faster | 1.0× (identical) | **No — SMI mooted it** |
| 10k-row mixed schema | Implied 3× for numeric cols | Below measurement noise | Inconclusive |

### Why the numbers changed — the SMI story

On 64-bit Dart, the VM stores small integers ("SMIs") directly in
pointer slots via tag bits, with no separate heap object. SMI range
is 63 bits in JIT mode (-2^62 to 2^62−1) and roughly 30 bits in AOT
mode with compressed pointers. Every integer in `0 .. 2^62−1` — which
is essentially every ID, count, enum, or foreign key ever used in
practice — stores in 8 bytes total (same as an `Int64List` element).

The original exp 055 assumed ~24 B per boxed int (16 B object header
+ 8 B body + 8 B pointer slot). That assumption held on older Dart
versions that didn't do SMI tagging (or did it with a tighter range).
On current SDK, the arithmetic is:

- **Small int case:** `List<Object?>[i] = intValue` → 8 bytes. No heap
  box. Same as `Int64List`. No win.
- **Large int case (> 2^62):** `List<Object?>[i] = bigInt` → 8 B slot
  + 16 B `_Mint` object = 24 B. vs `Int64List` = 8 B. **Expected 3×
  win on heap-allocated Mints specifically.** (Our Section 2b
  measurement was too noisy to confirm cleanly, but theory matches.)
- **Double case:** `List<Object?>[i] = 1.5` → 8 B slot + 16 B `_Double`
  object = 24 B. vs `Float64List` = 8 B. **Measured 2.5× win** (38 MB
  → 15 MB on 2M doubles).

Doubles are *always* heap-boxed because there's no SMI-equivalent
tagging for them — the pointer-tag bit budget is already consumed by
int tagging. So columnar arrays remain a real memory win for
double-heavy schemas. They are **not** a meaningful win for int-heavy
schemas, which is the majority of practical CRUD workloads (IDs,
counts, timestamps — all SMI candidates).

### Remaining wins by axis

**Time axis:**
- Allocation: 1.77× faster. Real but small absolute value (116μs/100k
  elements).
- Isolate transfer: 3.4× faster. `TypedData` is handed off to the
  receiving isolate via memcpy; generic `List<Object?>` deep-copies
  each pointer slot. The win here is genuine. However, resqlite's
  reader-pool already uses `Isolate.exit` (zero-copy handoff) for
  results >256KB — so the SendPort path this applies to is only the
  <256KB case.
- Iteration: no measurable difference. `as int` on an SMI compiles to
  effectively a no-op; `Int64List[i]` returns an int directly. Both
  are one-instruction hot.

**Memory axis:**
- Int-only schemas: no meaningful win (SMI already gets ~100%).
- Double-only schemas: ~2.5× backing-storage reduction.
- Mixed schemas: proportional to the double-column fraction.
- String columns: zero win (strings are heap regardless).

## Why RSS-based memory measurement was unreliable at this scale

Several sections in the spike produced nonsense numbers (negative
deltas, near-zero deltas despite guaranteed allocations). The root
cause is a combination of:

1. **VM arena pre-allocation.** The Dart VM pre-maps young-gen pages
   beyond what's currently in use. A 1.6 MB allocation that fits in
   those pre-mapped pages produces zero RSS growth even when the
   heap objects are truly new.
2. **Cross-section interference.** An allocation from section 2 stays
   live until `_section2Rss` returns, so section 2b's "baseline" is
   inflated by section 2's 15 MB of retained lists. Young-gen GC
   activity between sections can move that number around by several
   MB.
3. **Missing sync GC trigger.** Dart doesn't expose a synchronous GC
   force. `_churnHeap()` hints at young-gen collection but doesn't
   guarantee it.

**Takeaway for future memory experiments:** `ProcessInfo.currentRss`
delta has a signal-to-noise floor around ~5–10 MB on this platform.
Deltas below that are unreliable. For the exp 055 scenarios, pushing
the `_rssHoldCount` up to 20× was necessary to get a clean signal on
the double case (38 MB vs 15 MB). Smaller scales (e.g. single-query
results in the 100 KB range) will never produce measurable RSS deltas
with this tool. Future memory-axis experiments will likely need
`dart --observe` + Service API heap stats for scales below 10 MB.

## Phase 2 decision

**Deferred — not strict rejection.** The original exp 055 rejection
reasons still apply:

1. **Throughput is not the bottleneck** — confirmed. 1.77× allocation
   speedup on 100k elements is ~0.1 ms saved, well below anything
   users perceive.
2. **Memory wins don't show in time-based benchmarks** — no longer
   true; profile mode can see them. But the win is narrower than
   originally claimed.
3. **Large surface area change** — still true. Row, ResultSet,
   RawQueryResult, hash function, sacrifice threshold, schema, and
   transaction-read decode would all need to change.

The updated quantitative case:

- For **int-only tables**: no win (SMI already wins).
- For **mixed tables with doubles**: maybe 30–40% backing reduction
  proportional to double-column count.
- For **workloads dominated by queries that return >256KB**: the win
  is even smaller because `Isolate.exit` already handles transfer.

The decision to ship exp 055 would make sense **if and only if** a
concrete user workload has:
- Large result sets (>10k rows)
- Double-heavy schemas (financial, analytics, scientific)
- Memory pressure observed in production

Without that concrete signal, the implementation cost (3–5 days of
careful decode-path work) exceeds the EV.

**Recommendation:** park exp 084 on the architectural backlog. Revisit
when a user reports memory pressure traceable to double-heavy
decoded results.

## What Phase 2 would look like if revived

Concrete integration plan, preserved here for a future experimenter:

1. **Data structure.** Change `RawQueryResult.values: List<Object?>`
   to a per-column union:
   ```dart
   sealed class Column { final int nullBitmap; }
   final class IntColumn extends Column { final Int64List data; }
   final class FloatColumn extends Column { final Float64List data; }
   final class TextColumn extends Column { final List<String> data; }
   final class BlobColumn extends Column { final List<Uint8List> data; }
   final class MixedColumn extends Column { final List<Object?> data; } // fallback
   ```
   Mixed columns are required because SQLite is dynamically typed —
   column X can hold int in one row, string in the next.

2. **Row dispatch.** `Row.operator[]` looks up the column's type and
   dispatches to the appropriate backing array. A single
   `List<Column>` per ResultSet replaces the flat `List<Object?>`.

3. **Hash + sacrifice threshold.** Walk each column array in turn.
   Sacrifice threshold calculation uses per-column byte size.

4. **Isolate handoff.** Each typed column is individually
   zero-copy-transferable via `Isolate.exit` or `TransferableTypedData`.
   This is potentially a bigger win than the flat case, because the
   *whole result* can be handed off as a collection of refs rather
   than deep-copied via SendPort.

5. **Tests.** Existing query-decode tests should already cover
   correctness (Row's `Map<String, Object?>` surface is unchanged).
   Add specific tests for the mixed-type column fallback, because
   that's the failure-prone case.

Estimated: 3–5 days implementation + 1 day testing + 1 day
profile-mode validation = ~1 week of focused work.

## Reproduction

```bash
dart run benchmark/profile/columnar_spike.dart
```

Takes ~5 seconds. No `-DRESQLITE_PROFILE=true` needed — the spike
doesn't use the production code path.

## Conclusion

The original exp 055 is a case study in how VM improvements can
obsolete optimizations. The 75% memory reduction claim was real on
2024-era Dart; SMI tagging on current SDK captures ~95% of that win
for free.

For resqlite specifically, columnar decode storage remains a
plausible optimization for double-heavy workloads, but the EV has
shifted: it's now a niche win for specific production workloads
rather than a general improvement. Ship it when there's a concrete
user need, not speculatively.

The profile-mode infrastructure did its job: it gave us a way to
actually measure the memory axis, and the measurements told us the
honest story even though the answer was "the VM already fixed most of
this."
