# Experiment 086: Architectural capabilities — research + ideation

**Date:** 2026-04-19
**Status:** Research pass. No implementation. Proposes concrete
architectural directions organized by strategic fit, ranked by
effort × impact × EV, with first-step recommendations for the
highest-EV picks.

## 0. Framing

Exp 085 concluded: **performance is at the architectural ceiling** on
every measured workload. The isolate round-trip is ~2 μs above sqlite3
for reads and ~8 μs above for writes, and both gaps map to
feature-enabling overhead rather than waste. Further time-axis
investment has diminishing returns and zero user-perceptible impact
at 60 fps frame budgets.

That raises a strategic question: **if we're not competing on raw
throughput anymore, what ARE we competing on?** This doc surveys the
landscape, identifies where resqlite could add disproportionate value,
and proposes directions ranked by leverage.

## 1. Competitive landscape

What users in the Flutter/Dart SQLite ecosystem actually choose today:

### drift (formerly moor) — the incumbent ORM
- **Schema-first via codegen.** Users annotate Dart classes; drift
  generates typed query builders, DAOs, migrations.
- **Typed reactive queries** (`db.users.select().watch()`) — return
  streams typed to the schema.
- **Custom SELECTs require explicit `readsFrom`** — reactive
  dependencies aren't inferred.
- **Migrations framework** — step-based, type-safe, composable.
- **Isolate support** via `NativeDatabase.createInBackground`.
- **Mature ecosystem**, large user base, active development.

### sqlite_async
- Thin async wrapper over SQLite via worker pool.
- Reactive queries via `watch()` with explicit `triggerOnTables`.
- Transactions, savepoints, basic query builder.
- No ORM, no codegen, no migrations framework.
- Popular because it's simple.

### PowerSync
- Open-source sync layer atop `sqlite_async`. Bidirectional replication
  to Postgres / MySQL / MongoDB / MS SQL.
- Schema-first but config-driven (not full ORM).
- Handles online/offline transitions, conflict resolution.
- Attachment handling.
- Leverages FTS5 for search.
- Specific to the sync use case; thin on ORM features.

### Firestore (Firebase) offline mode
- Cloud-native, works offline with local cache.
- Document-oriented, not SQL.
- Strong real-time sync, proprietary backend.
- Auth + security rules + UI.
- The default for many Flutter apps despite the lock-in cost.

### sqflite
- Old-school synchronous wrapper.
- Large legacy install base.
- No reactive queries, no isolate story.
- Not a competitor strategically but a compat target.

### What's NOT well-served in this landscape

Three gaps that nothing handles well today:

1. **Transparent reactive queries with automatic invalidation.**
   drift and sqlite_async both require the user to declare
   dependencies for non-trivial queries. resqlite's authorizer-based
   auto-dependency tracking is structurally unique.

2. **Incremental re-computation for aggregate streams.** Every
   library re-executes the full query on every relevant write.
   No one does IVM.

3. **A proper local-first reactive primitives toolkit.** PowerSync
   layers sync on top of a dumb reactive layer; Firestore bundles
   sync with a proprietary backend. There's no "build-your-own-sync"
   kit that gives you clean change feeds + reactive reads +
   transactional writes as composable primitives.

### resqlite's current moat

- **Reactive streams at the SQLite layer with transparent dependency
  tracking.** Users write SQL; dependencies are inferred via the
  SQLite authorizer hook. Nothing else does this.
- **Hash-based result-change suppression (exp 075) and row-count
  short-circuit (exp 077).** Unchanged result sets don't re-emit,
  even when the underlying write "could have" changed them.
- **Decode path 2–3× faster than sqlite3** on medium-to-large
  selects (exp 085).
- **sqlite3mc encryption compiled in** (just needs Dart API surface).
- **FTS5 compiled in** (same story).

### resqlite's gaps

- No schema-first API / codegen / type safety.
- No migrations framework.
- No sync or change-feed primitives.
- No FTS5 Dart API (though the extension is linked).
- No encryption API (though sqlite3mc is linked).
- No DevTools integration.
- No Flutter lifecycle hooks.
- No query cancellation / timeout.

## 2. Architectural directions

Eight candidates organized by strategic axis. For each: what it is,
who it serves, effort, fit with existing architecture.

### A. Extending the stream engine (differentiation)

#### A1. Row-level subscriptions (`watchRow`, `watchRowById`)

**What.** First-class API for "observe a specific record by primary
key":

```dart
// Today: requires writing SQL
db.stream('SELECT * FROM users WHERE id = ?', [userId]);

// Proposed:
db.watchRow('users', userId);  // → Stream<Row?>
```

**Who.** Every mobile app that renders a detail screen bound to a
record. Probably the single most common reactive pattern in CRUD apps.

**Effort.** Modest — sugar over the existing `stream()` with
schema lookup to construct the SELECT. ~3–5 days including error
handling (bad table name, composite PKs, view handling).

**Fit.** Perfect — leverages existing hash suppression, row-count
short-circuit, and authorizer path. No new engine mechanism needed.

**Dependencies.** If we want typed results (`Stream<User?>` instead of
`Stream<Row?>`), we need some schema representation — couples to
codegen/ORM direction. The untyped version is standalone.

**Risk.** Low. It's already achievable via raw SQL; this is surface
polish.

#### A2. Stream composition via query transformation

**What.** Chainable transformations that push down to SQL where
possible:

```dart
db.watch('users')
  .where((u) => u.role == 'admin')   // pushes to WHERE role = ?
  .orderBy('name')                    // pushes to ORDER BY
  .limit(10)                          // pushes to LIMIT
  .watch();                           // Stream<List<User>>
```

**Who.** Apps that build dynamic filter/sort UIs on top of DB
results. Today they have to construct SQL strings by hand.

**Effort.** Significant — requires a query builder with pushdown
logic (what can go to SQL vs what runs in Dart). ~3–4 weeks for a
basic version, ~2 months for comprehensive coverage.

**Fit.** Stream engine supports it; adds a large surface area of
query-builder semantics. Starts looking like an ORM.

**Dependencies.** Essentially requires the ORM direction. If we
commit here, we commit to drift-like scope.

**Risk.** High. This is a multi-month investment in a direction
drift already occupies. Differentiation thin.

#### A3. Incremental view maintenance (IVM)

**What.** For aggregate streams (COUNT, SUM, AVG, MIN, MAX), maintain
the aggregate as a running delta instead of re-executing on every
write.

```dart
// Today on INSERT with 10k rows: re-execute SELECT COUNT(*) = 100μs
// With IVM: SELECT COUNT(*) = 0 (cached, delta already applied) + <1μs
// overhead per INSERT to increment the counter
db.stream('SELECT COUNT(*) FROM tasks WHERE done = false');
```

**Who.** Any app with dashboard widgets on aggregate stats (unread
count, total revenue, active users, etc.) running over tables with
high write rates.

**Effort.** Research-level. Narrow case (COUNT(*) on predicate-free
tables) is maybe 2 weeks of focused work. Full IVM with predicates,
UPDATE/DELETE, composite aggregates is months.

**Fit.** Natural extension of the stream engine. Detects "this query
is structurally aggregable" and routes it through an IVM path instead
of the full re-query path.

**Dependencies.** Would probably want to split into narrow
well-defined cases (COUNT without predicates, SUM on static columns)
and accept that complex aggregates fall back to re-execution.

**Risk.** Correctness is the hard part. Easy to produce wrong
aggregates under concurrency, UPDATE of grouping columns, etc.
Would need comprehensive property-based testing.

**Payoff.** If it works: **10–100× speedup** for aggregate streams on
high-write workloads. Genuinely differentiated capability — no other
Dart SQLite library does this. And unlike ORM competition, this is
research-level engineering that's hard to copy.

#### A4. Change feed (observable write log)

**What.** A stream of all writes as they commit, with
(table, rowid, operation) tuples:

```dart
db.changes.listen((change) {
  // change: (table: 'users', rowid: 42, op: OpType.insert)
  // — fires for every write, in commit order
});
```

Builds on SQLite's `sqlite3_update_hook`. Optionally filterable by
table or operation.

**Who.** Sync engines (build replication on top), audit logs,
analytics pipelines, cache invalidation for external caches, CQRS
read-side builders.

**Effort.** Small — SQLite already provides the hook; we just expose
it as a Dart stream through the writer isolate. ~1 week.

**Fit.** Natural — the writer isolate already installs update hooks
for dirty-table tracking. Change feed is a slightly different
subscription on the same mechanism.

**Dependencies.** None. Clean addition.

**Risk.** Low. Semantics are clear (commit order, at-least-once).

**Payoff.** Opens the sync/replication ecosystem. PowerSync-like
layers become possible as external packages. Doesn't commit resqlite
to building a full sync protocol; just provides the primitives.

### B. SQLite surface expansion (user-value)

#### B1. FTS5 full-text search API

**What.** Dart API for creating and querying FTS5 tables:

```dart
await db.createFtsTable('docs_fts', ['title', 'body']);
final results = db.stream<DocRow>(
  'SELECT * FROM docs_fts WHERE docs_fts MATCH ?',
  ['cooking recipes'],
);
```

**Who.** Any app with search functionality. Universal.

**Effort.** Tiny — FTS5 is already compiled in. Just need:
- Schema helpers for FTS5 table creation
- Query helpers that handle MATCH syntax safely
- Docs + examples

~3–5 days.

**Fit.** Drop-in. Users can already use FTS5 via raw SQL; this is
ergonomic surface.

**Dependencies.** None.

**Risk.** Near-zero.

**Payoff.** Direct user value. Search is table stakes for notes apps,
wikis, message logs, etc.

#### B2. JSON1 helpers

**What.** Dart-side sugar for JSON1 operators and functions
(`->`, `->>`, `json_extract`, `json_array_length`, etc.):

```dart
// Today: raw SQL with JSON operators
db.select("SELECT name, json_extract(data, '\$.age') FROM users");

// Proposed:
db.select(SqlBuilder()
    .column('name')
    .jsonPath('data', r'$.age', as: 'age')
    .from('users'));
```

**Who.** Apps using JSON columns for semi-structured data
(preferences, analytics blobs, feature flags).

**Effort.** Modest — ~1–2 weeks for a useful subset of JSON1.

**Fit.** Adjacent to query builder territory. Could be standalone or
part of A2.

**Dependencies.** If A2 happens, this rolls in. Otherwise it's a
mini query builder for JSON specifically.

**Risk.** Low.

**Payoff.** Solid but niche. Users today just write raw SQL.

#### B3. Vector search (sqlite-vec)

**What.** Embedding-based similarity search via sqlite-vec
(the maintained successor to sqlite-vss). Enables RAG-style apps,
semantic search, local recommendation.

```dart
await db.createVectorTable('items_emb', dimensions: 768);
final similar = await db.select(
  'SELECT * FROM items_emb WHERE embedding MATCH ? LIMIT 10',
  [queryEmbedding],
);
```

**Who.** AI-integrated apps: local semantic search, on-device
recommendations, RAG-over-local-data. Growing demand.

**Effort.** Moderate — needs to link sqlite-vec as an additional C
dependency (~2 KLOC of C), add schema helpers, handle Float32List
binding and reading.

**Fit.** Natural extension of the SQL surface. The reactive layer
also "just works" once vectors are a table column.

**Dependencies.** Sqlite-vec is MIT-licensed, well-maintained. Native
build hook modification.

**Risk.** Low-medium. Sqlite-vec is still young; API may evolve.

**Payoff.** Differentiated feature: no other Dart SQLite library
ships this. Could be a major draw for LLM-adjacent apps.

### C. Ecosystem integration (compatibility)

#### C1. Flutter lifecycle hooks

**What.** Auto-pause streams when the app backgrounds; resume on
foreground. Currently, streams keep firing on background, wasting
CPU + battery.

```dart
Database.open(path: ..., flutterLifecycle: true);
// Streams automatically suspend on AppLifecycleState.paused
// and resume on .resumed
```

**Who.** Every production Flutter app that opens a database in the
main isolate.

**Effort.** Small — wrap `WidgetsBindingObserver`, expose a hook on
the stream engine to pause re-query dispatch. Probably 1–2 days.

**Fit.** Natural but cross-cuts the lib/Flutter boundary. Might want
to live in a separate `resqlite_flutter` package to keep the core
Flutter-free.

**Dependencies.** Requires a Flutter integration package.

**Risk.** Low. Opt-in.

**Payoff.** Battery + CPU savings for users. Real production win.

#### C2. DevTools integration

**What.** Custom DevTools panel showing:
- Active streams and their dependencies
- Per-stream emission counts / latencies
- Slow-query log
- Connection pool state

**Who.** Developers debugging performance issues or stream lifecycle
bugs.

**Effort.** Significant — DevTools extensions involve VM service
integration, their own UI, plumbing. ~4–6 weeks for a useful one.

**Fit.** Leverages the Diagnostics API + Timeline markers we already
have. Good structural fit.

**Dependencies.** DevTools extension protocol (stable but evolving).

**Risk.** Medium — DevTools extensions are a separate product
surface with their own distribution / maintenance cost.

**Payoff.** Developer-experience differentiator. Especially valuable
for debugging reactive-stream issues which are hard to reason about.

#### C3. Hot-reload resilience

**What.** Currently, hot reload can leave streams in bad states
(subscribers orphaned, writer isolate still running). Formalize
handling so hot-reload is a supported workflow.

**Who.** Every Flutter developer.

**Effort.** Modest — 1 week to design + implement, mostly plumbing
through `reassemble` and lifecycle hooks.

**Fit.** Adjacent to C1.

**Risk.** Low.

**Payoff.** Quality-of-life win for contributors + small users.

### D. Production robustness (infrastructure)

#### D1. Dedicated checkpoint isolate (exp 083 deferred)

**What.** Move WAL checkpoint work off the writer isolate to a
dedicated mini-isolate. Writer never blocks on a checkpoint; p99
tail shrinks substantially.

**Effort.** 1–2 weeks. Known design (exp 083 laid it out):
- Checkpoint isolate owns its own SQLite connection.
- Writer signals when WAL crosses threshold.
- Checkpoint runs in parallel with writer; returns SQLITE_BUSY if
  readers hold snapshots; retries with backoff.

**Fit.** Clean — new isolate, doesn't touch existing hot paths.

**Dependencies.** None.

**Risk.** Medium — reader-snapshot interaction, connection
lifecycle, SQLITE_BUSY handling.

**Payoff.** Per exp 083: 57% p99 reduction on sustained merge
workloads. Modest at 60 fps but matters under sustained load.

#### D2. Query cancellation / timeout

**What.** `db.select(sql, params, timeout: Duration(seconds: 5))`.
Calls `sqlite3_interrupt` when timeout elapses. Also: caller can
cancel via a token (drift has CancellationToken).

**Who.** Any app where a long-running query (full-text search on a
huge corpus, bad plan on a scaled-up table) could block UI forever.

**Effort.** Modest — ~1 week. SQLite's `sqlite3_interrupt` is
straightforward; Dart-side plumbing for tokens / timeouts is the
work.

**Fit.** Natural. Already used by drift.

**Risk.** Low.

**Payoff.** Production robustness. Small but real.

#### D3. Backpressure on stream subscribers

**What.** If a subscriber's StreamController buffer grows beyond
threshold (listener is slow, pauses), emit a signal or drop-oldest
semantics instead of accumulating unbounded.

**Who.** Apps with heavy UI rebuilds driven by streams; production
systems dealing with bursty writes.

**Effort.** Modest — ~1 week design + implement.

**Fit.** Inside stream engine.

**Risk.** Low-medium — semantics have to be well-defined.

**Payoff.** Quality-of-life; prevents OOM under pathological load.

#### D4. Reader pool auto-sizing

**What.** Currently the reader pool has a fixed size. Apps with
bursty read load could benefit from dynamic scaling.

**Effort.** Moderate — ~2 weeks.

**Fit.** Inside reader pool.

**Risk.** Medium — scaling heuristics need care. Isolate spawn cost
is 10-50 ms, so the threshold matters.

**Payoff.** Low-to-moderate. Fixed pool is adequate for most
workloads.

### E. Tablestakes (parity)

#### E1. Schema migrations framework

**What.** Versioned schema migrations with up/down semantics:

```dart
Database.open(path: ..., migrations: [
  Migration(1, up: (tx) => tx.execute('CREATE TABLE users(...)')),
  Migration(2, up: (tx) => tx.execute('ALTER TABLE users ADD email')),
]);
```

**Who.** Every production app that evolves its schema over time.

**Effort.** Modest — ~1–2 weeks for a robust version (migration
tracking table, transactional application, failure recovery).

**Fit.** Self-contained.

**Dependencies.** None.

**Risk.** Low. Design space is well-understood (drift and every
other DB library has this).

**Payoff.** Tablestakes. Users currently have to roll their own or
use raw user_version pragmas.

#### E2. Encryption API (sqlite3mc already linked)

**What.** Expose encryption since sqlite3mc is already compiled in:

```dart
final db = await Database.open(path: ..., encryptionKey: 'secret');
await db.rekey('new-secret');
```

**Effort.** Small — ~3–5 days. sqlite3mc's API is already there;
just needs Dart surface + docs.

**Fit.** Drop-in on `Database.open`.

**Dependencies.** None; already compiled in.

**Risk.** Low. Well-tested underlying engine.

**Payoff.** Production feature for apps with sensitive data.
Today users can't easily enable this even though the engine is ready.

## 3. Evaluation matrix

Ranked across effort × impact × strategic fit.

| # | Direction | Effort | User value | Strategic fit | Notes |
|---|---|:---:|:---:|:---:|---|
| **A1** | Row-level subs (`watchRow`) | Low | High | Extend moat | Perfect fit, common pattern |
| **B1** | FTS5 Dart API | Low | High | Parity+ | Already compiled in |
| **E2** | Encryption API | Low | High | Parity | Already compiled in |
| **A4** | Change feed | Low | Medium | Extend moat | Opens sync ecosystem |
| **D1** | Checkpoint isolate | Med | Medium | Infra | Known design from exp 083 |
| **E1** | Migrations framework | Med | High | Parity | Tablestakes |
| **D2** | Query cancellation | Low | Medium | Infra | Straightforward |
| **C1** | Flutter lifecycle | Low | Medium | Integration | Needs separate package |
| **A3** | Incremental view maintenance | High | Huge (if it works) | Extend moat | Research bet, huge differentiator |
| **B3** | Vector search | Med | Niche-but-rising | Extend moat | AI apps |
| **A2** | Query composition DSL | High | Medium | Overlap with drift | Thin differentiation |
| **C2** | DevTools integration | High | Medium | Extend moat | Separate surface |
| **B2** | JSON1 helpers | Med | Niche | Parity | Can fold into A2 |
| **D3** | Backpressure | Low | Low-med | Infra | Quality-of-life |
| **D4** | Reader pool auto-scale | Med | Low | Infra | Probably not worth it |
| **C3** | Hot-reload resilience | Low | Low-med | Integration | DX win |

## 4. Recommended priorities

Three tiers based on EV and strategic fit:

### Tier 1: ship in the next ~4 weeks

These have small effort and large or high-confidence user impact.
Doing them quickly earns goodwill and fills glaring gaps, without
committing to any particular strategic direction.

1. **B1 — FTS5 Dart API.** 3–5 days. Already compiled in. Universal
   user value.

2. **E2 — Encryption API.** 3–5 days. Already compiled in. Production
   users need this.

3. **A1 — Row-level subscriptions (`watchRow`).** 3–5 days. The most
   common reactive pattern in mobile CRUD, currently has no syntactic
   sugar.

4. **A4 — Change feed.** ~1 week. Opens the sync ecosystem without
   committing resqlite to a specific sync protocol.

**Total effort:** ~4 weeks. **Combined value:** large. All four are
additive (don't conflict with anything), low-risk, and deliver
features users are probably already asking for in GitHub issues.

### Tier 2: next ~2 months

One medium-effort win and one strategic bet.

5. **E1 — Schema migrations framework.** 1–2 weeks. Tablestakes.
   Every user needs this eventually; ship before a third-party
   solution crystallizes.

6. **A3 — Incremental view maintenance (narrow scope).** 2–3 weeks
   for COUNT(*) on predicate-free tables. This is the **biggest
   potential differentiator** — no other Dart SQLite library does
   this, and the payoff for high-write-rate aggregate streams is
   10–100×. Start narrow to bound risk; expand only if the narrow
   case lands cleanly.

### Tier 3: build-when-demand-lands

These are good ideas but contingent on concrete pull from users /
production pathologies:

- **D1 (checkpoint isolate)** — ship when a user reports sustained-
  write p99 pain.
- **C1 (Flutter lifecycle)** — ship when we decide to launch
  `resqlite_flutter`.
- **B3 (vector search)** — ship when an AI-integrated app hits the
  lack of it.
- **D2 (query cancellation)** — ship alongside any long-running
  query work (full-text search scales this up).

### Tier 4: explicitly deprioritize

- **A2 (query composition DSL)** — overlaps with drift; multi-month
  investment. Let drift do ORM. resqlite's value is below the ORM
  layer.
- **D4 (reader pool auto-scaling)** — low upside.

## 5. First-step proposal for Tier 1

If you want concrete "what to ship first" — my call:

**Start with A4 (change feed).** Reasons:
- Smallest architectural addition (~1 week).
- Opens a genuinely new ecosystem direction (sync, replication,
  cache invalidation).
- No user-facing API changes to existing code; purely additive.
- Validates the "resqlite as primitive, not full solution"
  positioning.

**Design sketch for A4:**

```dart
// lib/src/database.dart (new)
Stream<TableChange> get changes;

// lib/src/table_change.dart (new)
final class TableChange {
  final String table;
  final ChangeOp op;  // insert / update / delete
  final int rowid;
  final String database; // "main" for primary db, attached name otherwise
}

enum ChangeOp { insert, update, delete }
```

**Implementation path:**
1. Writer isolate installs `sqlite3_update_hook` (already partially
   in place for dirty-tables). Hook fires per-row-change on INSERTs /
   UPDATEs / DELETEs, **before** commit.
2. Accumulate (table, op, rowid) tuples into a per-transaction buffer.
3. On commit, send the buffer as a batch to main isolate via a
   dedicated change-feed port.
4. On rollback, discard.
5. Main isolate exposes as a broadcast `Stream<TableChange>` —
   subscribers are independent from regular stream engine.

**Testing path:**
- Unit: single INSERT fires one (users, insert, N).
- Transactional: multi-row transaction fires all rows together post-
  commit; rollback fires nothing.
- Ordering: commit order is preserved in the stream.
- Backpressure: no subscribers → buffer doesn't grow unbounded.

**Success criteria:**
- End-to-end tests pass.
- Zero perf impact on write throughput when no subscriber is
  attached (the native update_hook is already firing for dirty-
  tables; we just tee off).
- Documentation + a sample sync package skeleton in
  `example/change_feed_sync/`.

Following A4, the sequencing I'd suggest:
- **Week 2:** B1 (FTS5) + E2 (encryption) — both are surface-only
  work that can go in parallel.
- **Week 3:** A1 (watchRow) — builds on the engine, but doesn't
  depend on A4/B1/E2.
- **Week 4–6:** E1 (migrations) — larger commit, after Tier 1 items
  are in.

## 6. Meta: strategic positioning

Stepping back from specific features to what resqlite should stand
for:

**If I were picking a 12-month narrative** for resqlite, it would
be: *"The reactive primitives layer for local-first Dart apps."*

- **Primitives, not a solution.** Unlike Firestore (which bundles
  backend) or PowerSync (which bundles sync), resqlite offers clean
  composable primitives: reactive reads, transactional writes,
  change feed. Other packages build the opinionated solutions on
  top.
- **Reactive-first semantics.** Transparent dependency tracking,
  hash-based suppression, optional IVM. Other DB libraries bolted
  reactivity on top; resqlite was designed for it.
- **Production-grade, Flutter-native.** Isolate model, lifecycle
  hooks, encryption, migrations. All the boring stuff that
  production apps need.

This positioning says:
- Invest in the reactive engine (A1, A3, A4) — that's the moat.
- Ship the table-stakes stuff (E1, E2, D2) so users don't have to
  work around missing pieces.
- Add surface-level user value cheaply (B1).
- **Don't** chase ORM surface — let drift do that, integrate with
  it.
- **Don't** chase sync layers directly — expose change feed, let
  sync packages build.
- **Don't** compete on raw throughput — exp 085 says we're at the
  ceiling.

If that positioning feels right, Tier 1 + Tier 2 above implement it
within ~3 months of focused work. If the positioning feels wrong,
the priority list needs to shift.

## 7. Open questions for decision

Before committing to any Tier-1 item, worth answering:

1. **Scope of Flutter integration.** Do we eventually ship a
   `resqlite_flutter` package (C1), or keep resqlite Flutter-free
   and let users wire lifecycle themselves? This affects the
   positioning.

2. **ORM stance.** Are we cooperating with drift (resqlite as an
   engine drift can sit atop), or competing with drift (A2 query
   composition)? The Tier-1/2 picks above assume cooperation.

3. **IVM risk appetite.** A3 is a research bet. If it pays off, it's
   a major differentiator. If it doesn't, it's 2–3 weeks of wasted
   work. Worth running? My vote: yes, in Tier 2, with narrow scope.

4. **Sync ecosystem ambitions.** A4 (change feed) is the first step.
   Do we want to eventually build a first-party sync package, or is
   resqlite core + external packages the permanent split?

5. **Migration urgency.** Is the lack of E1 actually hurting
   adoption, or are users just rolling their own user_version
   scripts? Worth a GitHub-issues scan before committing.

No one right answer. These are steering questions for the next
sprint planning session.

## 8. Out of scope for this doc

Not covered here:
- Specific APIs (leave for design docs on the chosen directions).
- Perf (exp 085 covered that; perf is at the ceiling).
- Testing strategy (each item deserves its own testing plan).
- Documentation / marketing (downstream of shipping).
