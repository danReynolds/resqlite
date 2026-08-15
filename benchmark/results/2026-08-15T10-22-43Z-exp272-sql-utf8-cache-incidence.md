# Experiment 272: downstream SQL UTF-8 cache incidence

Collected 2026-08-15 on Apple M1 Pro, macOS 26.2, Dart 3.12.2. Resqlite base:
`2e182044a03c2e33244855844a00ad0afe42bd2c`. Downstream Dune source:
`75fd6467ca4ffbaa3da0f81d8545ab5e8486cf68`; its tracked tree was clean (two
untracked local `CLAUDE.md` files were not used). Dune's existing
`dependency_overrides` sibling path resolved to the exp 272 checkout.

> **Verdict: premise refuted.** Across 911 SQL-pointer-cache accesses in three
> captured flow traces spanning five test lifecycles, all 316 reuses had
> one-based LRU rank at most 32. Replaying the same
> per-isolate sequences at capacity 128 rescued 0 of 595 misses and 0 SQL
> bytes. No runtime candidate or timing A/B followed.

## Instrument

A temporary call in `cachedSqlUtf8` recorded, per access, process ID, isolate
role/name and identity, monotonic per-isolate sequence, actual hit/miss,
UTF-8 byte length, and collision-free SQL bytes. The retained
[`analyzer`](../../benchmark/experiments/sql_utf8_cache_trace_analyze.dart)
groups by process/isolate, computes the exact LRU stack, and replays capacities
32 and 128. Reuse rank is the one-based stack position (`index + 1`, where 1 is
immediate reuse), so a capacity-N cache hits exactly when rank is at most N.

The temporary placement recorded the result of the real lookup before the hit
was reinserted at MRU:

```dart
final cached = _sqlUtf8Cache.remove(sql);
_traceSqlCacheAccess(sql, hit: cached != null);
if (cached != null) {
  _sqlUtf8Cache[sql] = cached;
  return cached;
}
```

The logger writes synchronously and therefore invalidates latency comparisons.
It can also extend reader busy time and change availability-based dispatch, so
reader sequences describe the captured instrumented routing; the FIFO writer
sequences are stronger. Raw logs contain application SQL and remain temporary.
The committed anonymized
[`event stream`](2026-08-15T10-22-43Z-exp272-sql-utf8-cache-events.tsv)
retains per-isolate order, opaque SQL identity, byte length, actual hit and
reuse rank for independent replay.

## Commands

From the temporary Dune copy, after `dart pub get`:

```text
dart test test/api/admin_onboarding_flow_test.dart -r expanded
dart test test/p2p/message_roundtrip_test.dart -r expanded
dart test test/p2p/canvas_sync_test.dart -r expanded
```

From the Resqlite checkout, replay the anonymized artifact with:

```text
dart run benchmark/experiments/sql_utf8_cache_trace_analyze.dart \
  benchmark/results/2026-08-15T10-22-43Z-exp272-sql-utf8-cache-events.tsv
```

Each command passed. A preliminary flag-gated admin capture produced zero trace
events because the compile-time flag did not propagate into worker isolates; it
was excluded before analysis. The tracer was enabled directly in the temporary
copy and the hashed `trace2` rerun is the only admin input below.

## Aggregate result

| flow | tests | isolates | calls | cold | d1-32 | d33-128 | d129+ | misses32 | misses128 | rescued |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| admin onboarding | 2 | 10 | 201 | 191 | 10 | 0 | 0 | 191 | 191 | 0 |
| message round-trip | 1 | 5 | 318 | 139 | 179 | 0 | 0 | 139 | 139 | 0 |
| canvas sync/lifecycle | 2 | 10 | 392 | 265 | 127 | 0 | 0 | 265 | 265 | 0 |
| **total** | **5** | **25** | **911** | **595** | **316** | **0** | **0** | **595** | **595** | **0** |

The writer groups demonstrate why unique-count evidence is insufficient:

| group | calls | unique SQL | repeated calls | reuse beyond 32 |
|---|---:|---:|---:|---:|
| message writer | 146 | 77 | 69 | 0 |
| canvas writer, flow 1 | 116 | 79 | 37 | 0 |
| canvas writer, flow 2 | 104 | 79 | 25 | 0 |

The current 32-entry cache and simulated 128-entry cache both hit 316/911
accesses (34.69%) and miss 595/911 (65.31%). The larger cache's incremental hit
rate and rescued miss bytes are both zero. The replay matches the tracer's real
hit bit on 911/911 events. All groups start at sequence zero with no gaps or
duplicates; all encoded identities decode and match their recorded UTF-8 byte
length. Maximum one-based rank is 9 for admin, 19 for message and 16 for canvas.
The routing-insensitive writer subset independently has 498 calls, 136 reuses,
maximum rank 18 and zero candidate-only accesses. The analyzer's rescued-byte
total includes the native NUL terminator; it is also zero.

## Input hashes

```text
5123b80368298a5aef3056f4b718dd99b27e60434f4ca1633f5905b9664a43b5  admin_onboarding_trace2.log
686b357c31c01dfb307853233b1e1cfbeb1d2908948aa6915c870c8e133cdacd  message_roundtrip_trace.log
c4121aacaaca4534c7e8a27ca7c5e5abce3825cd6b9cc8fb9216555f1579e538  canvas_sync_trace.log
01658af8eaf3b931a8891aa189d8a9c2107c382f9d56ad020b00321ade2ffa0f  admin_onboarding_flow_test.dart
9c39d059a893dd3f7cab8b24cc4cfc0c08f1f8bc3b64d8e1a0310ef339010f3e  message_roundtrip_test.dart
52386976e9309cbd6d2368d217e245925ca2f6ded3560f38b75606e392e4edd8  canvas_sync_test.dart
acaf52d5f9da7fbdf27d6d69a71820bd9d55bf535adaa35bc732159d6e1bdbcd  sql_utf8_cache_trace_analyze.dart
f9d6901c38311a8180e55625caedc0c6b30b1f4d5c89a2f8735b7bb48adc1fb9  exp272-sql-utf8-cache-events.tsv
```

## Scope

These are deterministic JIT integration flows, not an hours-long dogfood or AOT
trace. Spawned-peer stderr is buffered, so the record covers the current Dune
runtime's reader/writer isolates rather than every peer process. Onboarding is
migration-heavy, and synchronous logging can perturb reader assignment. The
result proves zero allocation-avoidance opportunity for a 32-to-128 expansion
in the captured sequences; it does not claim that every application,
uninstrumented routing, or longer lifecycle stays within 32.
