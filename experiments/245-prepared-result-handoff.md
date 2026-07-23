# Experiment 245: Prepared-result handoff — intrinsic send vs Isolate.exit (measurement)

**Date:** 2026-07-23
**Status:** Accepted (measurement)
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused, process-isolated harness
  [`benchmark/experiments/prepared_result_handoff.dart`](../benchmark/experiments/prepared_result_handoff.dart);
  raw table in
  [`benchmark/results/2026-07-23-exp245-prepared-handoff.md`](../benchmark/results/2026-07-23-exp245-prepared-handoff.md).

## Problem

This is **Experiment A** of the peer-recommended estimand split (see
[exp 241](241-sacrifice-reeval.md) for the confound and
[exp 244](244-pool-burst-eager-respawn.md) for Experiment B, the pool-capacity
half). It measures the **intrinsic transfer** estimand: for a given result object
graph, is `SendPort.send` or `Isolate.exit` the cheaper handoff — with spawn,
SQLite stepping, decode, and result *construction* all moved outside the timed
interval? Exp 241 could not answer this because its through-the-pool harness
folded transfer, pool lifecycle, decode, and cross-sample heap state into one
noisy number.

## Approach

Peer-designed prepared-result barrier protocol. A worker isolate builds the real
production `ResultSet` graph — the flat row-major values list + `RowSchema` +
wrapper that actually crosses the boundary (per `row.dart`) — and holds it live.
It sends a tiny `Ready(goPort)` to main; main records `t0` (VM-timeline µs) and
sends `Go`; the worker immediately does `resultPort.send(result)` **or**
`Isolate.exit(resultPort, result)`; main's result-port handler records `t1` as
its **first** statement. `handoffWall = t1 − t0`, both timestamps on main (one
monotonic clock).

**One fresh process per observation** — no receiver-heap accumulation, no mode
carryover, neither mode inheriting the other's GC state (exactly the confounds
exp 241 suffered). An orchestrator runs matched send/exit children in ABBA
blocks; process startup is outside the timed interval. An **empty-envelope
control** isolates fixed overhead from payload cost:
`payloadExcess = handoff(result) − handoff(empty)`. 16 samples/mode/shape.

## Results

`handoffWall` (Go-sent → received), median µs, Apple M1 Pro:

| shape | send | exit | exit−send | send payload | exit payload |
|---|---:|---:|---:|---:|---:|
| empty (fixed cost) | 100 | 147 | +47 | 0 | 0 |
| num10k×20 (200k slots) | 736 | 391 | **−345** | 636 | 244 |
| mixed10k×8 (80k slots) | 501 | 298 | **−203** | 401 | 151 |
| str400k (1 string) | 96 | 167 | +71 | −4 | 20 |
| str1m (1 string) | 118 | 157 | +39 | 18 | 10 |
| num2k slots | 87 | 157 | +70 | −13 | 10 |
| num8k slots | 108 | 171 | +63 | 8 | 24 |
| num20k slots | 127 | 189 | +62 | 27 | 42 |
| num48k slots | 263 | 241 | **−22** | 163 | 94 |

Three mechanistic facts, each isolated by the controls:

1. **`Isolate.exit` carries a ~47 µs fixed-overhead premium** over `send` (empty
   envelope: 147 vs 100 µs) — its sendability walk plus isolate teardown/message
   reassignment. For any small payload, send wins on this alone.

2. **Strings (immutable leaves) are *shared* on send, not copied.** A 400 KB
   string adds **−4 µs** to send (payload ≈ 0) and a 1 MB string +18 µs — both
   noise. Send's copy cost is driven by the **mutable flat-list slot count** (the
   pointer-array backing), *not* the payload bytes: send payload rises 27 → 163 →
   636 µs across 20k → 48k → 200k slots, but is ~zero for a single huge string.

3. **`Isolate.exit` is zero-copy**, so it wins once the structural copy exceeds
   its 47 µs premium. The **crossover is ~48k slots** (num48k: exit −22 µs; send
   still wins by 62 µs at 20k), widening to **−345 µs at 200k slots**.

## Outcome — the send-vs-sacrifice question is resolved

Combined with exp 244 (pool capacity: no penalty at pool-4, sacrifice
neutral-to-favorable), the intrinsic result completes the picture:

- **Small-to-moderate results (< ~48k structural slots) and all string-heavy
  results: send ≈ exit within the pre-registered equivalence margin.** The
  differences (39–71 µs) sit inside ±75–100 µs / ±5%. The middle is a **declared
  wash**, with a slight lean to send on its lower fixed overhead. Per the peer's
  stop rule (A equivalent in the middle + B no pool penalty), the policy stands.
- **Large structural results (> ~48k slots): `Isolate.exit` materially wins**
  (−203 to −345 µs at 80k–200k slots). Sacrifice is correctly favored here, and
  the current policy's *intent* — sacrifice large results — is validated.
- **The one real defect is the trigger, not the policy.** Sacrifice fires on a
  **byte** threshold, but the true cost driver is **mutable structural slot
  count**: strings are shared free on send. So a large *string* (400 KB, one slot)
  is send-favored (96 vs 167 µs) yet is wrongly sacrificed at the 256 KB byte
  threshold — the text/shared-leaf misroute first seen in exp 241, now confirmed
  intrinsically.

**Actionable follow-up (its own experiment):** route the sacrifice decision on
mutable structural slot count rather than estimated bytes — or, minimally, a guard
that keeps shared-leaf-dominated (string-heavy) results on send. That fixes the
misroute without touching the large-structural regime where exit correctly wins.

This experiment ships no runtime change — it is the measurement that turns exp
241's confounded "keep sacrifice" into a mechanistic account: **send's cost ∝
mutable slot count; strings share free; exit is zero-copy with a fixed ~47 µs
premium; crossover ~48k slots.** The harness (prepared-result barrier, one process
per observation, ABBA, empty-envelope control) is the reusable pattern for any
future intrinsic isolate-transfer question.
