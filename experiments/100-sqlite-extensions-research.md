# Experiment 100: SQLite extensions — applicability research

**Date:** 2026-04-20
**Status:** Research + audit pass. No implementation.

## Purpose

Survey SQLite extensions (official + third-party) for strategic fit with
resqlite. Ground in the *current* build state — what's compiled, what's
verified functional, what's missing — and rank candidates by effort ×
user value × binary cost. Output: a prioritized list of extensions
worth enabling, shipping Dart API for, or vendoring.

## 1. Current build state (audited)

### What's compiled in today

Probed via `sqlite_compileoption_used()` + functional tests against the
current build (sqlite3mc 3.51.3 on macOS arm64). Verified ON:

| Extension | Status | User-facing? |
|---|---|---|
| FTS5 full-text search (+porter, unicode61, trigram tokenizers) | ✅ compiled | ❌ no Dart API, no docs |
| Math functions (`sin`, `cos`, `ln`, `pi`, `pow`, …) | ✅ compiled | ❌ no docs |
| JSON1 (`json_extract`, `json_object`, etc. — core in 3.38+) | ✅ functional | ❌ no docs |
| Preupdate hook | ✅ compiled | internal only (dirty-tables) |
| STAT4 (advanced query planner stats) | ✅ compiled | transparent |
| Batch atomic write (F2FS optimization) | ✅ compiled | transparent |
| sqlite3mc encryption (AES-128/AES-256/ChaCha20 via PRAGMA key) | ✅ compiled | ✅ `Database.open(encryptionKey: ...)` |

**Four items are compiled but not surfaced:** FTS5, math functions,
JSON1, trigram tokenizer. These are the "free wins on the shelf"
noted in exp 086 — a Dart API layer + docs + examples turns them
from "raw SQL only" into discoverable features. FTS5 is the biggest
of these.

### What's NOT compiled in (but would be free-to-enable via compile flag)

Same probe, all returned `off`:

| Extension | What it does | Binary cost |
|---|---|---|
| `SQLITE_ENABLE_RTREE` | R*Tree 2D/3D spatial indexing | ~15–25 KB |
| `SQLITE_ENABLE_GEOPOLY` | Polygon queries (needs RTREE) | ~15 KB |
| `SQLITE_ENABLE_SESSION` | Changesets for sync/replication | ~50 KB |
| `SQLITE_ENABLE_DBSTAT_VTAB` | Virtual table exposing page-level stats | ~5 KB |
| `SQLITE_ENABLE_SERIES` | `generate_series(start, end)` table-valued function | <1 KB |
| `SQLITE_ENABLE_BLOOM_FILTER` | Query planner uses bloom filters on joins | ~10 KB, transparent |
| `SQLITE_ENABLE_STMT_SCANSTATUS` | Per-query plan runtime stats (scan cost, rows used) | ~5 KB |
| `SQLITE_ENABLE_COLUMN_METADATA` | `sqlite3_column_origin_name()` etc. — useful for ORMs | ~5 KB |
| `SQLITE_ENABLE_DESERIALIZE` | Load DB from memory buffer | ~5 KB |
| `SQLITE_ENABLE_SNAPSHOT` | Point-in-time read snapshots | ~15 KB |
| `SQLITE_ENABLE_NORMALIZE` | Normalize SQL (replace literals with `?`) for logging | ~5 KB |
| `SQLITE_ENABLE_FTS4` / `SQLITE_ENABLE_FTS3` | Older FTS versions | — |
| `SQLITE_ENABLE_ICU` | Unicode-aware collation + case folding | **2–5 MB** |
| `SQLITE_ENABLE_LOAD_EXTENSION` | Runtime `.load` of .so/.dylib extensions | ~5 KB + security surface |
| `SQLITE_ENABLE_OFFSET_SQL_FUNC` | `sqlite_offset()` function for row offsets | <1 KB |

**Total cost to enable everything except ICU and LOAD_EXTENSION:**
~120 KB to the compiled library. Current library is ~2.5 MB; this
would be ~5% growth.

### Third-party extensions considered

Surveyed the active SQLite extension ecosystem (primarily Alex Garcia's
family + official SQLite contrib + Benchmark-adjacent):

| Extension | What it does | Notable |
|---|---|---|
| [`sqlite-vec`](https://github.com/asg017/sqlite-vec) | Vector similarity search | MIT, C, stable, growing adoption for AI apps |
| [`sqlite-lembed`](https://github.com/asg017/sqlite-lembed) | Run LLM embeddings (llama.cpp) in SQL | Very heavy (includes llama.cpp) |
| [`sqlite-spellfix1`](https://sqlite.org/spellfix1.html) | Approximate string matching / spelling | Official contrib, ~50 KB |
| [`sqlite-regex`](https://github.com/asg017/sqlite-regex) | Rust regex engine | Requires Rust toolchain in build |
| [`sqlite-percentile`](https://sqlite.org/percentile.html) | Window-like percentile functions | Official contrib, ~5 KB |
| [`sqlite-zstd`](https://github.com/phiresky/sqlite-zstd) | Transparent ZSTD BLOB compression | Active, some production use |
| [`sqlite-ulid`](https://github.com/asg017/sqlite-ulid) | ULID generation function | Could be pure Dart instead |
| [`sqlite-uuid`](https://www.sqlite.org/src/file?name=ext/misc/uuid.c) | UUID functions | Official contrib, ~5 KB |
| [`sqlite-html`](https://github.com/asg017/sqlite-html) | HTML parsing / queries | Niche |
| [`sqlite-url`](https://github.com/asg017/sqlite-url) | URL parsing | Niche |
| [`sqlite-http`](https://github.com/asg017/sqlite-http) | HTTP client in SQL | **Anti-pattern for a mobile DB** |
| [`sqlite-csv`](https://sqlite.org/csv.html) | CSV as virtual table | Niche on mobile |

## 2. Evaluation criteria

Extensions are judged on five axes:

1. **User value.** How many resqlite users would actually use this? What
   does it unlock that's hard or impossible without it?
2. **Effort to ship.** Compile flag only? Vendored C? Dart API layer?
   Testing across platforms?
3. **Binary size cost.** Mobile apps care about IPA/APK size.
4. **Maintenance cost.** Is it a one-time addition or does it require
   ongoing keep-up?
5. **Strategic fit.** Does it extend resqlite's reactive-primitives
   positioning, or is it unrelated?

## 3. Ranked recommendations

### Tier 1 — ship now (highest leverage)

These have disproportionate user value for their cost.

#### 1.1 — FTS5 Dart API (B1 from exp 086)

**Effort:** 3–5 days. **Binary cost:** already paid. **User value:** huge.

Compiled in, fully functional, reactive streams already work on FTS5
tables (authorizer captures deps). Missing: Dart-side helpers,
MATCH-syntax quoting, schema sugar for `CREATE VIRTUAL TABLE`,
docs + examples. Covered in detail in exp 086.

The trigram tokenizer is a bonus finding from this audit — substring
search ("find any row containing 'cat'") works out of the box, which
most apps need and which isn't generally known to be available in FTS5.

#### 1.2 — Enable `SQLITE_ENABLE_RTREE` + `SQLITE_ENABLE_GEOPOLY`

**Effort:** 1 hour (compile flag + tests + brief docs). **Binary cost:** ~40 KB. **User value:** medium but sticky.

R*Tree is SQLite's official 2D/3D spatial index. Adds support for
efficient "find all points in bounding box" / "nearest neighbors"
queries. Every location-aware mobile app hits this eventually —
and today resqlite users who need it have to choose a different DB.

```sql
CREATE VIRTUAL TABLE poi USING rtree(id, minx, maxx, miny, maxy);
SELECT * FROM poi WHERE minx >= ? AND maxx <= ? AND miny >= ? AND maxy <= ?;
```

Geopoly is complementary — polygon-based queries (containment,
intersection). Same compile-flag + tests cost as RTREE.

Current state: `CREATE VIRTUAL TABLE ... USING rtree(...)` returns
"no such module: rtree" — verified. Users are blocked.

**Recommendation:** flip the flags. Tiny cost, unlocks a whole app
category (mapping, geofencing, location-filtered lists).

#### 1.3 — Enable `SQLITE_ENABLE_SERIES`

**Effort:** 10 minutes. **Binary cost:** <1 KB. **User value:** small but annoying-to-miss.

`generate_series(1, 10)` as a table-valued function. Universal utility
for reports, date ranges (`SELECT date('now', '-' || value || ' days')
FROM generate_series(1, 30)` gives you the last 30 days), test
fixtures. Verified missing — `SELECT * FROM generate_series(1, 3)` 
errors today.

No reason not to. Zero ongoing cost. Flip the flag.

### Tier 2 — worth considering (ship if there's a specific driver)

These have real value but not universal appeal.

#### 2.1 — Enable `SQLITE_ENABLE_SESSION` (changesets)

**Effort:** compile flag + eventual Dart API (~1–2 weeks total). **Binary cost:** ~50 KB.

SQLite's official changeset mechanism. Captures the set of changes
made during a "session" as a binary diff, then can replay that
changeset against another database with conflict handlers.

**Strategic value:** directly relevant to the change-feed discussion
earlier. If we ever ship a sync primitive (exp 086's A4 direction),
the Session extension is the correctness-maximizing base layer for
peer-to-peer sync. Would pair beautifully with the trigger-based
change feed for mobile-app use cases.

Not worth shipping *before* we decide on the sync direction, but
worth enabling preemptively — the compile flag is cheap and leaves
the option open.

#### 2.2 — Vendor `sqlite-vec` (vector search)

**Effort:** ~1.5 weeks. **Binary cost:** ~100 KB. **User value:** high but niche (AI apps).

First-class vector similarity search for on-device semantic search,
RAG, recommendations. MIT-licensed, actively maintained (Alex Garcia),
pure C, static-linkable. Cross-platform story is clean.

```sql
CREATE VIRTUAL TABLE items_vec USING vec0(embedding float[1536]);
SELECT rowid, distance FROM items_vec
  WHERE embedding MATCH ?
  ORDER BY distance LIMIT 10;
```

**Why it's strategically interesting right now:** AI-integrated apps
are a clear growth direction for Flutter/Dart (on-device LLM +
retrieval use cases). No Dart SQLite library ships vector search
today. resqlite would be first.

**Why to defer:** it's niche today relative to the user base. The
engineering load is real (link the C, add Float32List binding
helpers, document the embedding dimension choice, cross-platform
build testing). Ship if/when we see concrete demand, or as part of
a deliberate "AI-ready" release.

Open question: sqlite-vec is young enough that API may still evolve.
Worth checking their changelog cadence before committing.

#### 2.3 — Enable `SQLITE_ENABLE_DBSTAT_VTAB`

**Effort:** compile flag + docs (~1 day). **Binary cost:** ~5 KB. **User value:** specialist but valuable.

Exposes a `dbstat` virtual table that lets you query page-level
usage statistics. Useful for:
- Diagnosing slow queries ("why is this table so fragmented?")
- Monitoring index efficiency
- Production telemetry

Would strengthen the Diagnostics API surface resqlite already ships.
The existing `Database.diagnostics()` gives per-connection counters;
`dbstat` adds per-table/per-page inspection on top.

Recommend enabling and surfacing via a small helper:

```dart
// Future API
final stats = await db.pageStats();  // iterates dbstat for the main DB
```

#### 2.4 — Enable `SQLITE_ENABLE_STMT_SCANSTATUS`

**Effort:** compile flag + Dart API (~1 week). **Binary cost:** ~5 KB + slight runtime overhead when active.

Per-statement runtime stats: how many rows were scanned, how much
time in each query plan node, estimated vs actual cost deltas.
Extremely useful for production query-performance debugging.

Would pair well with the profile-mode harness (exp 080) — instead of
just "this query took 30 ms," you'd have "this query scanned 50k rows
in step 2 of the plan because the index wasn't used."

**Why tier 2 not tier 1:** the slight runtime overhead (tens of
nanoseconds per statement execution) hits the hot path. Gated behind
`kProfileMode` from our existing compile-time gate, this is clean.

#### 2.5 — Enable `SQLITE_ENABLE_COLUMN_METADATA`

**Effort:** 10 minutes. **Binary cost:** ~5 KB. **User value:** medium (for ORMs / codegen).

Exposes `sqlite3_column_origin_name()`, `sqlite3_column_database_name()`,
`sqlite3_column_table_name()`, `sqlite3_table_column_metadata()`. Lets
callers ask "which table does this SELECT column actually come from?"
— essential for type-safe query builders or codegen ORMs.

If we ever partner with drift (or build our own typed layer), this
is table stakes. Cheap to enable; leaves the option open.

### Tier 3 — probably not worth it

Thought-through and considered, but arguments against outweigh for:

#### 3.1 — `SQLITE_ENABLE_ICU` (internationalization)

**2–5 MB to binary.** That alone rules it out for a mobile-first
library by default. Users with international text + sort needs today
do it Dart-side (`collator.compare`) or accept ASCII-only sorting.
If someone needs it badly enough to accept the binary cost, they can
build resqlite with a custom flag — but don't ship it by default.

#### 3.2 — `SQLITE_ENABLE_LOAD_EXTENSION` (runtime extension loading)

Allows `.load '/path/to/thing.so'` at runtime. Security footgun
(arbitrary code execution via DB file attack surface). Mobile apps
shipping dynamic libraries is logistically painful (codesigning,
App Store review). **Intentionally off.** If anyone needs specific
extensions, they should be statically linked at build time.

#### 3.3 — `sqlite-regex` (Rust regex engine)

Requires Rust toolchain in the build. Our build hook is pure C.
Adding Rust means contributors need `cargo` installed, CI matrix
grows, cross-compilation gets harder (especially for iOS arm64 sim).
The incremental user value (full regex vs `LIKE`/`GLOB`/FTS5 trigram)
doesn't justify the build complexity. If demand is strong later,
revisit; meanwhile, FTS5 trigram covers most substring-match cases.

#### 3.4 — `sqlite-http` (HTTP from SQL)

Networking from the DB layer is an anti-pattern. Violates the
"local-first" value prop, introduces blocking network calls into
queries, creates timeout/error handling horror stories. **Explicitly
don't ship.**

#### 3.5 — `SQLITE_ENABLE_FTS3` / `SQLITE_ENABLE_FTS4`

Superseded by FTS5 which we have. Including them would bloat the
binary for features users shouldn't be choosing.

#### 3.6 — `sqlite-csv` / `sqlite-parquet` / `sqlite-arrow`

Data-engineering formats. resqlite's audience is Flutter apps, not
data pipelines. Users who need these have larger infrastructure.

### Deliberately deferred

- **`SQLITE_ENABLE_DESERIALIZE`** (in-memory DB from bytes) — useful
  for testing, DB-as-asset patterns. ~5 KB. Worth enabling if we add
  a "ship a seed database in your app bundle" helper. Not urgent.
- **`SQLITE_ENABLE_SNAPSHOT`** — point-in-time reads. Useful for
  migrations that need consistent views mid-schema-change. Niche
  unless we build a first-party migrations framework.
- **`SQLITE_ENABLE_NORMALIZE`** — SQL query normalization (`SELECT *
  FROM t WHERE x = ?` for logging). Useful for observability /
  query profiling. Pairs with scanstatus for a full telemetry story.
- **`sqlite-uuid`** (official contrib) — UUID functions. Could
  alternatively be pure Dart. If we want DB-side UUIDs for default
  values, enable it; otherwise leave to Dart-side.
- **`sqlite-spellfix1`** — approximate string matching. 50 KB.
  Useful for "did you mean?" features. Niche.

## 4. Proposed action plan

### Phase 1: "Enable and surface the free stuff" (~1 week total)

Small, cheap, strictly additive:

| # | Action | Effort | Binary Δ |
|---|---|---|---|
| 1 | Flip flags: `RTREE`, `GEOPOLY`, `SERIES`, `COLUMN_METADATA` | 30 min | +55 KB |
| 2 | Add tests proving each new capability works | 2 hours | — |
| 3 | Update docs: which extensions are in, with examples | 2 hours | — |
| 4 | FTS5 Dart API (Tier 1 from exp 086) | 3–5 days | — |

**Outcome:** Users gain spatial queries, polygon queries,
`generate_series`, better ORM-friendly column metadata, and a proper
FTS5 API. Binary grows by ~60 KB (~2.4%).

### Phase 2: "Strategic enablement" (~2 weeks, after Phase 1 lands)

Medium cost, real user impact:

| # | Action | Effort | Binary Δ |
|---|---|---|---|
| 5 | Flip flag: `SESSION` (no API yet; just preserve the option) | 15 min | +50 KB |
| 6 | Flip flag: `STMT_SCANSTATUS` + gate Dart API behind `kProfileMode` | 1 week | +5 KB |
| 7 | Flip flag: `DBSTAT_VTAB` + expose via Diagnostics API | 1 week | +5 KB |

**Outcome:** Changesets foundation laid (for future sync). Production
query profiling. Page-level DB stats for ops/debugging.

### Phase 3: "Vector search" (~1.5 weeks, if pulled)

Conditional on demand signal:

| # | Action | Effort | Binary Δ |
|---|---|---|---|
| 8 | Vendor `sqlite-vec` from upstream | 2 hours | +100 KB |
| 9 | Build hook: link sqlite-vec alongside sqlite3mc | 1 day | — |
| 10 | Dart API: Float32List binding helpers, schema sugar | 3 days | — |
| 11 | Cross-platform CI (macOS/iOS/Android/Linux/Windows) | 1 day | — |
| 12 | Sample app: `example/vector_search/` | 1 day | — |

**Outcome:** On-device vector search as a first-party feature. First
Dart SQLite library to ship this. Strategic signal for AI-integrated
Flutter apps.

## 5. Binary size summary

If all Phase 1 + 2 + 3 ship:

| Current library | ~2.5 MB |
| + RTREE / GEOPOLY / SERIES / COLUMN_METADATA | +55 KB |
| + SESSION / SCANSTATUS / DBSTAT_VTAB | +60 KB |
| + sqlite-vec | +100 KB |
| **Total after all** | **~2.7 MB** (+8%) |

Acceptable growth for a mobile library. Most of it is opt-in-able at
build time if someone wants to minimize further.

## 6. What changes in the library with each tier

- **Nothing breaks.** All extensions are additive. No existing API
  changes, no user migrations required.
- **Phase 1 binary growth is ~2.4%.** Below perception threshold.
- **Phase 3 adds Float32List support to the binding path** if we
  don't already have it — needs verification.
- **Session Extension compile flag** requires `ENABLE_PREUPDATE_HOOK`
  (which we already have). No other dependency chain.

## 7. What this doesn't cover

Out of scope for this doc:
- **Custom SQLite user-defined functions from Dart** — a separate
  design question. SQLite lets you register C functions; exposing that
  to Dart callers requires FFI + calling-convention work.
- **Virtual table implementations in Dart** — same story, harder.
  Users writing "tables backed by API calls" would love this; engineering
  is substantial.
- **Session + full sync protocol** — extension enables changesets;
  turning them into a sync engine is its own design project (per exp 086).

## 8. Reproduction

```bash
# Probe current build:
dart run benchmark/profile/columnar_spike.dart  # or similar standalone script
# See experiments/100-extensions-probe.dart for the full audit program.
```

## 9. Key findings summary

1. **Four extensions are compiled in but undocumented** (FTS5, math,
   JSON1, trigram tokenizer). Free user-value wins waiting for Dart
   ergonomics + docs.

2. **Four extensions are one compile flag away** with trivial cost:
   RTREE, GEOPOLY, SERIES, COLUMN_METADATA. ~1 hour of work for a
   set of features that unblock whole app categories (mapping,
   location apps, reports, ORM codegen).

3. **Session Extension** is strategically important for future sync
   work — enable the flag now even without shipping an API.

4. **sqlite-vec** is the one third-party extension worth vendoring
   proactively, for AI-integrated apps. Defer if no demand signal,
   but it's a clear "first-mover" opportunity for Dart ecosystem.

5. **ICU, regex, http, FTS3/4** are deliberately excluded — too
   heavy, anti-pattern, or superseded.

6. **Total binary growth** for the recommended additions: ~200 KB
   (8% of current library size). Acceptable for mobile.
