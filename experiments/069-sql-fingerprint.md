# Experiment 069: SQL fingerprint in stmt cache

**Date:** 2026-04-16
**Status:** Deferred (proper normalization requires SQL rewriter)

## Problem

The C statement cache keys on the raw SQL string. Applications that build
SQL with string concatenation instead of bind parameters thrash the cache:

```dart
db.execute('SELECT * FROM users WHERE id = 5');
db.execute('SELECT * FROM users WHERE id = 6');
db.execute('SELECT * FROM users WHERE id = 7');
```

Each SQL string is distinct → each creates a separate cache entry → with a
32-entry cap, a tight loop like this evicts useful entries and re-prepares
constantly. The fix in principle: normalize literals to `?` before caching,
so all three variants share one prepared statement.

## Analysis (Why Deferred, Not Rejected)

The team's proposal: "Normalize literals → ? before stmt_cache_lookup…
SQLite's own `sqlite3_normalize()` is an option if you enable that build
flag."

Two problems with implementation:

1. **`sqlite3_normalized_sql()` takes a prepared statement as input, not
   raw SQL.** It's designed to tell you what a *compiled* statement's
   normalized form looks like — useful for logging and statement tracing,
   not for pre-prepare lookup. To use it as a cache key, we'd have to
   prepare first, normalize, then look up — by which point we've already
   paid the prepare cost we were trying to avoid.

2. **Even if we had a pre-prepare normalizer, reusing a prepared statement
   across different literal values requires rewriting the SQL + binding
   the extracted literals as parameters.** A prepared stmt compiled for
   `WHERE id = 5` has the literal `5` baked into its bytecode; we can't
   step it with `id = 6` without preparing a new statement. So
   normalization must be accompanied by actual SQL rewriting — replace
   each literal with a `?`, collect literals into a parameter list, and
   bind them before step.

SQL rewriting requires a full tokenizer that handles:
- String literals (single-quoted), with embedded escaped quotes
- Blob literals (`X'…'`)
- Numeric literals including negative, hex, and scientific forms
- Comments (`--` and `/* */`)
- Identifiers (which may look like literals if unquoted)
- Multi-statement SQL (DDL + DML mixes)

This is ~300-500 lines of careful C with significant edge-case risk.
Not a "quick win."

## Simpler Variants Considered

- **Hash-based lookup** (replace `memcmp(sql)` with int compare): doesn't
  improve hit rate, only lookup speed. Current 32-entry linear scan with
  memcmp is already cache-resident and fast. Below noise.
- **Grow cache size 32→128** (team's idea 10): doesn't solve the thrashing
  problem for apps that generate unbounded distinct queries; just postpones
  the eviction. Measure eviction rate first to decide if this is worth it.

## Decision

**Deferred.** The impact is real for apps that don't use bind parameters,
but a proper implementation is a 300+-line SQL rewriter with edge-case
risk that doesn't match the "quick win" framing. Revisit if:

1. A production app surfaces prepare-storm telemetry suggesting this is
   the bottleneck.
2. We build out a proper `sqlite3_normalize()` wrapper (possibly via
   `SQLITE_ENABLE_NORMALIZE` compile flag + a custom pre-prepare pass).

## Related

- Experiment 003 (C-level connection + statement cache) — original design
- Experiment 059 (row count hint) — adjacent; also about cache metadata
