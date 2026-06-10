# Experiment 160: Tiered incremental stream maintenance (row deltas)

**Date:** 2026-06-10
**Status:** In Review
**Direction:** `stream-rerun-dispatch`

## Problem

Every stream invalidation re-executes the full query. Hash suppression
(exp 075/077) saves the decode and the emission, never the execution: a
write that provably cannot affect a stream's result still costs a
reader-pool round-trip (12 µs dispatch floor) plus a full SQLite
re-execution per affected stream. On A11c overlap that is 50 re-queries
per write — 25,000 per 500-write burst — of which exp 136 measured the
completion-handler chain alone at 28.6% of total wall. Exp 134 proved the
win class (keyed-PK writer-burst wall halved when re-queries were elided
by rowid precision) but was rejected because its *write-path SQL text
recognizer* was too fragile to trust. signals.json directed: revive
row-level precision "only through explicit API/design or real workload
evidence", and exp 149 (residual split) concluded the next stream work
needed "a workload-shape or scheduling-model change rather than another
sub-bucket optimization".

## Hypothesis

The preupdate hook already observes every modified row's old and new
values — today they are discarded. If the writer ships bounded per-row
deltas alongside the dirty-table set, the stream engine can maintain
admitted streams' materialized results *incrementally*: prove most writes
irrelevant with a few integer comparisons (no reader dispatch at all),
patch in-window changes locally, and fall back to the existing re-query
path for anything unprovable. Unlike exp 134's recognizer, admission is
decided once at stream registration against a sound-by-construction
grammar, and every uncertainty degrades to performance loss, never
correctness loss. No public API changes — `db.stream()` is unchanged.

## Approach

**Native capture** (`native/resqlite.c`): the preupdate hook serializes
op + rowids + old/new column values into a bounded buffer (256 rows / 32
columns / 256 KB per drain cycle; overflow or OOM poisons the cycle).
Savepoint rollback poisons the cycle too — stale deltas are unsafe where
stale dirty-tables are merely conservative. Drained alongside the dirty
sets at statement end / outermost commit; discarded on rollback.

**Plumbing**: `ExecuteResponse`/`BatchResponse` carry the raw bytes
(`null` = unreliable → fallback); the engine decodes them lazily, once
per write cycle, and only when at least one admitted stream watches a
dirty table.

**Tier-1 admission** (`lib/src/stream_ivm.dart`): at registration —
asynchronously, off the hot path — the engine fetches
`PRAGMA table_info` (cached per table) and classifies the stream's SQL
against a deliberately tiny grammar:
`SELECT <bare cols|*> FROM <table> [WHERE col op (int|?) [AND ...]]
[ORDER BY <pk> [ASC]]` — comparisons on INTEGER values only, table must
have a single-column INTEGER PRIMARY KEY (rowid alias) included in the
projection, and result order must be fully determined (ORDER BY pk, or a
pk-equality predicate). TEXT comparisons are excluded in tier 1 because
column collations are not mirrored. Anything outside the grammar stays on
the re-query path forever.

**Maintenance**: per delta row, evaluate the predicate conjunction
against old and new values (NULL cells fail predicates, matching SQL
semantics; non-INTEGER cells in a compared column bail). Proven miss →
nothing. In-window patch / entry / departure → clone-on-write the cached
rows (previously emitted lists are never mutated), emit, and store a hash
sentinel (−1) so the next fallback re-query can never be suppressed
against a pre-patch baseline. Any inconsistency (cache disagrees with a
delta, schema column-count drift, malformed buffer) bails: the cache is
dropped and the entry re-queries exactly as today.

**Honest divergence from exp 134's rejection**: this is still a SQL
recognizer. The differences that change the calculus: it runs once at
registration (not per write), admits a closed grammar where SQLite
semantics are provably mirrored (INTEGER-only comparisons, BINARY-free),
fails closed (unparsed → fallback; unprovable at apply time → bail), and
is paired with maintained-vs-requery equivalence tests. The risk profile
is "misses an optimization", not "skips a required re-query".

## Results

### Engagement check (profile counters, A11c-overlap shape)

50 streams × 500 writes, every write touching a projected column:
`ivm_skipped=24,500 ivm_applied=500 ivm_bail=0` — zero reader-pool
re-queries for the entire burst
(`benchmark/profile/ivm_engage_check.dart`).

### Writer wall split audit (exp 147 harness, single pass, back-to-back)

| workload | baseline wall | IVM wall | residual_us | emissions |
|---|---:|---:|---|---:|
| A11c baseline (0 streams) | 96.5 ms | 75.4 ms | 68,417 → 52,998 | — |
| A11c disjoint | 100.6 ms | 104.2 ms | 55,669 → 62,360 | 0 → 0 |
| A11c overlap | 186.5 ms | 132.0 ms | 135,071 → 47,966 | 44 → 500 |
| keyed PK subscriptions | 46.9 ms | 25.5 ms | 28,340 → 10,287 | 3 → 3 |

A11c overlap **−29%** wall with **11× more emissions delivered** (500 vs
44): under the baseline, re-query latency causes most per-write changes
to coalesce or hash-suppress; IVM delivers each write's patch
synchronously — the behavior an infinitely-fast re-query would produce.
Keyed-PK **−46%**, reproducing exp 134's archived result through the
explicit classifier. Disjoint is neutral: column elision (exp 106)
already skips those streams before IVM is consulted. `invalidate_us`
rises on overlap (29,974 → 67,340) because patch+emit work now runs
inline in the invalidation pass — more than paid for by the residual
collapse (135,071 → 47,966).

### Tracelite A/B (stream-rerun-dispatch direction, formal gate)

**Pass 1 (baseline first, candidate second), 3 runs per side:**

| scenario | delta | 95% CI | p | per-run medians (baseline → candidate) |
|---|---:|---|---|---|
| many-streams-writer-throughput | **−18.5%** | −122..−96.3 ms | 3.4e-6 | 591.6/583.5/578.6 → 476.9/491.0/480.3 ms |
| keyed-pk-subscriptions | **−14.1%** | −60.0..−27.4 ms | 1.6e-10 | 280.9/301.7/283.7 → 267.3/261.5/261.4 ms |
| high-cardinality-fanout | +2.11% | +2.59..+12.8 ms | 0.009 | 361.5/363.9/366.4 → 379.4/367.4/372.4 ms |

Both wins are consistent across every run with tight CVs — and the
keyed-PK *within-run CV itself drops* from 0.13–0.15 to 0.02–0.05:
removing reader-pool contention removes its variance. The
high-cardinality +2.11% flag has a CI excluding zero but was collected
with the candidate phase second; per the exp 159 journal lesson, an
order-flipped second pass adjudicates it.

**Pass 2 (order flipped: exp-160 collected first, main second).** With
the sign inverted to match pass 1's orientation (main slower → win):

| scenario | main vs exp-160 | 95% CI | per-run medians (exp-160 → main) |
|---|---:|---|---|
| many-streams-writer-throughput | **+22.2% slower** | +100..+113 ms | 477.7/483.8/477.0 → 584.5/582.7/587.5 ms |
| keyed-pk-subscriptions | **+9.4% slower** | +13.0..+37.0 ms | 261.6/265.8/268.4 → 279.3/282.8/279.2 ms |
| high-cardinality-fanout | +0.80% | −3.63..+9.56 ms (straddles zero) | neutral |

Both wins reproduce with the collection order flipped — exp-160's
absolute medians are essentially identical across passes (many-streams
477–491 ms, keyed-PK 261–268 ms), as are main's (579–592 / 279–302 ms).
The keyed-PK variance reduction follows the code, not the phase: exp-160
runs at CV 0.01–0.05 in both passes while main runs at CV 0.10–0.15. The
pass-1 high-cardinality +2.11% flag **did not reproduce** (CI straddles
zero, p=0.868) — drift, exactly the exp 159 journal pattern.

## Decision

**In Review (accept-shaped).** Two large, twice-reproduced measured-
elapsed wins on the canonical stream gate — many-streams −18.5%/+22.2%
(pass 1/pass 2 orientation), keyed-PK −14.1%/+9.4% — with the third
scenario neutral after order-flipped adjudication, zero bails on every
measured workload, dedicated equivalence tests (26) and the full suite
green, and no public API change. This is the first stream experiment to
remove re-query *execution* rather than tuning its constant: 98% of
A11c-overlap invalidation decisions become proven misses that never
touch the reader pool.

### Admission on an app-shaped stream mix

`benchmark/profile/ivm_admission_audit.dart` (new) builds the workload
the suite was missing: chat + feed schemas mirroring the tracelite
app-shaped scenarios (which exercise `select()`, not `stream()`), eight
reactive-UI stream shapes × 10 instances, and a chat-shaped write burst
(70% new message + conversation bump, 15% feed like, 10% profile edit,
5% message edit).

| stream shape | admitted | burst emissions |
|---|---|---:|
| message pane (JOIN + DESC + LIMIT) | no | 56 |
| message pane, denormalized (DESC + LIMIT) | no | 47 |
| conversation list (DESC + LIMIT) | no | 650 |
| unread badge (aggregate) | no | 46 |
| user card (pk equality) | **yes** | 1 |
| full transcript (int equality + ORDER BY pk) | **yes** | 48 |
| feed page (DESC + LIMIT) | no | 20 |
| author drafts (int equality + ORDER BY pk) | **yes** | 3 |

Counters: 30/62 distinct entries admitted (`ivm_admitted_total=30`,
`ivm_rejected_total=32`; dedup collapses identical-SQL instances). Burst:
`ivm_skipped=2,948 / applied=52 / bail=0` — 3,000 invalidation decisions
resolved without a reader re-query — against `completion_handler_count`
≈ 3,138 reader replies still generated by the unadmitted entries.

The read: tier-1 admits roughly half the distinct entries in a realistic
mix, but the **rejected set holds the highest-churn screens** (message
panes, conversation list, feed — all `ORDER BY <col> DESC LIMIT N`
shapes). Tier-2's first two steps (composite-key ordering with pk
tiebreak + LIMIT windows with a K+buffer cache) would convert exactly
those, flipping most of the remaining ~3,100 re-queries per burst into
skips/patches. That is the quantified case for tier-2 — and the bound on
what tier-1 alone can claim in real apps.

### Surfaced pre-existing bug: diagnostics × reader data race

CI caught a flaky reader-isolate SEGV (~1-in-30 stream_test runs) that
bisected to the admission PRAGMA — but the root cause predates this
experiment. `resqlite_db_status_total` skips readers whose `in_use` flag
is set, and that flag has been dead code since exp 030 moved workers to
dedicated reader assignment (exp 051 even documented the acquire path as
dead). `Database.diagnostics()` was therefore calling `sqlite3_db_status`
on live NOMUTEX reader connections from the main isolate; the
`SCHEMA_USED` op measures memory via the connection's `pnBytesFreed`
dry-run mechanism, and toggling that under a reader mid-query corrupts
the reader's own allocation accounting (crash: `sqlite3VdbeDelete` →
allocation-size read, null). Exp 160's detached admission reads made
"reader busy while a test polls `Diagnostics.streamLength`" the common
case, blowing the window open. Fixed here: read workers bracket each
request with `resqlite_reader_set_busy` (two ~ns leaf FFI calls), making
the existing busy guard real; the sacrifice path clears the bracket
before `Isolate.exit`. Validation: crash reproduced locally pre-fix;
100/100 clean stress iterations post-fix.

## Tier expansion (v2 stream engine)

Building on tier 1's foundation, the classifier generalized into three
fail-closed admission modes sharing one strict grammar (string literals,
aggregate calls, AS aliases, DESC, LIMIT/OFFSET, DISTINCT):

- **Full maintenance** gained composite ordering
  (`ORDER BY intCol [DESC], pk [DESC]` — explicit pk tiebreak required so
  tie order is exact) and `LIMIT K` windows: a top-K cache with
  complete-set tracking. Entries and in-window patches are O(delta);
  departures from a full incomplete window and boundary-crossing moves
  fall back (the replacement row is unknown). TEXT equality predicates
  admit when the table's CREATE statement (sqlite_master, cached per
  table) contains no COLLATE clause, making BINARY semantics provable.
- **Tier 1.5 skip-only**: shapes whose results cannot be maintained
  (DESC without tiebreak, OFFSET, DISTINCT, unprojected keys, aggregate
  mixes) but whose WHERE is an evaluable conjunction get proven-miss
  elision with no cached state; any hit or unprovable cell re-queries.
- **Tier 3 aggregates**: `COUNT(*)/COUNT/SUM/MIN/MAX/AVG(col) AS alias`
  over an evaluable (possibly empty) predicate, seeded exactly by a
  writer-ordered snapshot and maintained per delta (SQL NULL semantics;
  exact integer sums; AVG = sum/count; a departing MIN/MAX extremum
  bails and re-seeds).

Hot path: predicate conjunctions compile to flattened primitive arrays
(`IvmPredicateProgram`), and full states keep a pk set for O(1) presence
checks on the proven-miss path.

### Two ordering defects the equivalence harness caught

Both surfaced only under `dart test` scheduling load (~1-in-5 runs) and
were invisible to deterministic same-seed replays:

1. **Reader-built baselines race late writer replies.** An aggregate
   snapshot (or cache build) executed on a reader can observe a commit
   whose delta is then applied on top of it — cross-port event delivery
   gives no happens-before between a reader result and the writer reply
   for a write it already saw. Fix: all IVM state is built through
   **writer-ordered reads** (a `writer.locked` select hook wired by
   `Database`): the writer port is FIFO with the writes themselves, so a
   snapshot's port position totally orders it against every delta.
2. **A maintained state only survives an unbroken chain of processed
   cycles.** A delta-bearing write routed to the re-query fallback
   (dirty/in-flight guard, absent or malformed deltas, capture overflow)
   leaves the state's baseline permanently stale — and a hash-suppressed
   re-query validates *emissions* without re-syncing *state* (captured
   in an event ledger: seed lands at 2784, the next insert is swallowed
   by an unchanged-hash re-query, every later apply walks the −1
   forward). Fix: the engine drops maintained state whenever a cycle
   bypasses it; the writer-ordered rebuild restores an exact baseline.
   Known trade: churn cycles (overflow batches, unknown-deps fallbacks)
   trigger rebuild storms; steady state is untouched.

The randomized equivalence harness
(`test/stream_ivm_equivalence_test.dart`: 3 seeds × 12 rounds × 9
streams across every admission mode, with rowid changes, NULLs,
savepoint rollbacks, and overflow batches; every emission compared to a
fresh select) is the load-bearing safety net — 20/20 clean full-loop
runs post-fix.

### Admission audit, v2 (app-shaped stream mix)

| stream shape | mode | burst emissions |
|---|---|---:|
| message pane (JOIN + DESC + LIMIT) | no | 57 |
| message pane, denormalized (DESC + LIMIT) | **skip-only** | 47 |
| conversation list (no tiebreak) | no | ~1,900 |
| conversation list (pk tiebreak) | **windowed** | ~2,160 |
| unread badge | **aggregate** | 47 |
| user card | **full** | 1 |
| full transcript | **full** | 48 |
| feed page (`created_at DESC, id DESC LIMIT 50`) | **windowed** | 30 |
| author drafts | **full** | 3 |

7/9 shapes admitted (was 3/8 at tier 1); 52/63 distinct entries.
Burst: `ivm_skipped=7,325 / applied=318 / bail=0 / hit_fallback=48` —
**7,643 invalidation decisions resolved without a reader re-query**
(tier 1: 3,000) at a burst wall of 132.9 ms (main's equivalent ~200 ms
while delivering a fraction of the emissions). The two remaining
re-query shapes have documented upgrade paths: the JOIN pane (tier 4)
and the tiebreak-less conversation list (add `, id DESC`).

## Future Notes

- **Emission cadence**: IVM emits per write where the re-query path
  naturally coalesces bursts behind reader latency. Subscribers see more
  timely (and more numerous) emissions. If a workload prefers coalescing,
  a microtask-batched emit (exp 045 pattern applied to IVM emissions) is
  the tunable — measure before adding it.
- **Tier-2 candidates, in evidence order**: TEXT equality under known
  BINARY collation (needs `PRAGMA table_info` + collation introspection);
  LIMIT windows with a K+buffer cache (unlocks top-K queries; boundary
  departures currently can't exist because LIMIT is not admitted);
  SQLite-side predicate evaluation against a bound delta row (exact
  semantics for arbitrary predicates at O(1) per delta).
- **Capture overhead**: writes pay two bounded row-value serializations
  per modified row even with no admitted streams. Batches poison the
  buffer at 256 rows and stop paying. If release-suite write benchmarks
  ever flag it, gate capture on a writer-side "admitted streams exist"
  flag (one control message when the first stream is admitted).
- **Schema changes**: `ALTER TABLE ADD/DROP COLUMN` changes the capture
  column count and demotes admitted streams to fallback on their next
  delta (correct, self-healing). The cached `PRAGMA table_info` is keyed
  per table and cleared on engine close; a same-count column rename
  leaves predicates evaluating the same cid positions, which is
  positionally correct until the stream's own SQL breaks on re-query.
