# Exp 245 — prepared-result handoff, intrinsic send vs Isolate.exit

Harness: `benchmark/experiments/prepared_result_handoff.dart`. Apple M1 Pro.
Worker builds the real production ResultSet graph and holds it; main records t0
(Go sent) and t1 (result received, first op in handler); handoffWall = t1 − t0,
both on main (one VM-timeline clock). One fresh process per observation, ABBA
blocks, 16 samples/mode/shape. Empty-envelope control isolates fixed overhead.

handoffWall, median µs:

| shape | send | exit | exit−send | send−empty (payload) | exit−empty |
|---|---:|---:|---:|---:|---:|
| empty | 100 | 147 | +47 | 0 | 0 |
| num10k×20 (200k slots) | 736 | 391 | −345 | 636 | 244 |
| mixed10k×8 (80k slots) | 501 | 298 | −203 | 401 | 151 |
| str400k | 96 | 167 | +71 | −4 | 20 |
| str1m | 118 | 157 | +39 | 18 | 10 |
| num2k | 87 | 157 | +70 | −13 | 10 |
| num8k | 108 | 171 | +63 | 8 | 24 |
| num20k | 127 | 189 | +62 | 27 | 42 |
| num48k | 263 | 241 | −22 | 163 | 94 |

Reading:
- Isolate.exit fixed premium ~47 µs (empty: 147 vs 100).
- Strings shared on send: a 400 KB string adds ~0 µs to send (payload −4).
- Send payload cost ∝ mutable slot count: 27 → 163 → 636 µs at 20k → 48k → 200k.
- Exit zero-copy wins past ~48k slots (num48k −22; num10k×20 −345).

See `experiments/245-prepared-result-handoff.md`.
