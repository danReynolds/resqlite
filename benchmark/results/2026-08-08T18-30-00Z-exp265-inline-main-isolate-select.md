# Experiment 265: inline main-isolate `select()`

> The candidate these numbers measure was **rejected** — see
> [`experiments/265-inline-main-isolate-select.md`](../../experiments/265-inline-main-isolate-select.md).
> The measurements stand and are the reason the receipt is kept: they price the
> `select()` isolate round trip at 6.3 us of an 8.4 us point read, which four
> earlier experiments argued against without measuring. What does not stand is
> the safety argument built on top of them — every lane below is small integers
> and short TEXT on a hot page cache, and none can see the three failure modes
> that killed it. Read the lane set as an incomplete guard set, which is itself
> one of the experiment's findings.

Collected 2026-08-08 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.
Baseline is `origin/main` at `4b963ad`; candidate is the same tree plus the
inline read path in `ReaderPool`, the `inlineRowCap` parameter on `decodeQuery`,
the reserved reader connection, and the new harness. Both arms were built as
native-asset-aware AOT CLI bundles, per exp 193's requirement for any
decode-path result:

```console
dart build cli --target=bin/select_inline_dispatch.dart --output=<arm>
<arm>/bundle/bin/select_inline_dispatch --lane=<lane> --warmup=12 --samples=51
```

The harness source is
[`benchmark/experiments/select_inline_dispatch.dart`](../experiments/select_inline_dispatch.dart);
`bin/` holds only a two-line entry point, because that is where `dart build cli`
requires the target to live. The baseline arm was built from the candidate's copy
of the harness, so the source is identical in both arms and only `lib/` differs.

Every lane is **lane-isolated** — one fresh process per lane per arm — and each
collection is four passes in alternating collection order (baseline-first,
candidate-first, baseline-first, candidate-first). Values are microseconds per
*sample*, not per execution: `point1` and `point1-wide20` time 200 executions per
sample, `page20` times 50, `page64` 20, `point-under-load` 10, and `concurrent8`
ten groups of eight concurrent reads.

Two collections were taken. The first (41 samples/lane) timed one group of eight
in the `concurrent8` sample, which lands near 30 us — too coarse for the lane that
had to decide whether losing pool parallelism costs anything — so the lane was
changed to ten groups and everything was re-collected at 51 samples. Both arms
were rebuilt from the amended source. The second collection is the authoritative
one; the first agrees on every lane and is reproduced below because it is
independent evidence for the primaries.

## Host conditions

The machine was **not quiet**. `top` reported 0.0-38.8% idle across the session
with a load average near 37, driven by unrelated processes — a Codex renderer at
101% CPU, a Claude helper at 30%, `syspolicyd` at 77%, `WindowServer` at 58%. The
volume also started the session with 138 MB free of 460 GB; 5.9 GB of stale
`dart_test.kernel.*` directories under `$TMPDIR` were removed to make the AOT
builds possible.

This is the second experiment in a row collected under claim 264.6's conditions,
and the mitigation is the same: alternating collection order, and two lanes that
*cannot reach the changed code* reporting what the host is doing to the numbers.
Those controls came in at +0.1% and +3.2% mean against primaries of −35% to −95%,
so the effects here are between ten and a thousand times the observed control
drift. The precise percentages should still be treated as approximate; the signs,
magnitudes and orderings are not in doubt.

## Lanes

| lane | shape | role |
|---|---|---|
| `point1` | `WHERE id = ?` on the canonical 6-column row, 1 row, ×200/sample | primary — least work a query can do, so the largest share of hop |
| `point1-wide20` | the same on a 21-column INTEGER row, ×200/sample | primary — separates per-request cost from per-slot cost |
| `page20` | `LIMIT 20` on the canonical row, ×50/sample | primary — a paged list view |
| `page64` | `LIMIT 64`, at the row cap, ×20/sample | primary — where the win should start decaying |
| `point-under-load` | 1 point read ×10 while four 1,000-row reads hold the pool | primary — admission cost, not transfer cost |
| `concurrent8` | 8 distinct point reads via `Future.wait`, ×10 groups/sample | guard — the lane written to kill the idea |
| `mixed6-1k` | 1,000 rows of the canonical row | control — past the cap, identical code both arms |
| `int20-10k` | 10,000 × 21 INTEGER | control — same, and where the added per-row compare would show |
| `cap-abort` | fresh SQL armed at 1 row, timed at 400 | guard — the mispredict, once per statement |

## Collection 2 — 51 samples/lane, authoritative

Median microseconds per sample, baseline / candidate:

| lane | pass 1 | pass 2 | pass 3 | pass 4 |
|---|---|---|---|---|
| `point1` | 1685 / 427 | 1864 / 548 | 1579 / 427 | 2201 / 416 |
| `point1-wide20` | 1881 / 481 | 1909 / 533 | 1842 / 431 | 1160 / 455 |
| `page20` | 664 / 344 | 485 / 305 | 494 / 354 | 478 / 338 |
| `page64` | 435 / 317 | 429 / 621 | 469 / 329 | 397 / 315 |
| `point-under-load` | 533 / 42 | 954 / 52 | 982 / 37 | 1169 / 39 |
| `concurrent8` | 619 / 203 | 950 / 203 | 943 / 208 | 463 / 198 |
| `mixed6-1k` | 232 / 234 | 264 / 275 | 258 / 256 | 261 / 251 |
| `int20-10k` | 6013 / 5870 | 7910 / 7377 | 10237 / 10305 | 6006 / 7287 |
| `cap-abort` | 129 / 163 | 124 / 143 | 131 / 194 | 122 / 133 |

As deltas:

| lane | role | p1 | p2 | p3 | p4 | mean |
|---|---|---:|---:|---:|---:|---:|
| `point1` | primary | −74.7% | −70.6% | −73.0% | −81.1% | **−74.8%** |
| `point1-wide20` | primary | −74.4% | −72.1% | −76.6% | −60.8% | **−71.0%** |
| `page20` | primary | −48.2% | −37.1% | −28.3% | −29.3% | **−35.7%** |
| `page64` | primary | −27.1% | +44.8% | −29.9% | −20.7% | −8.2% |
| `point-under-load` | primary | −92.1% | −94.5% | −96.2% | −96.7% | **−94.9%** |
| `concurrent8` | guard | −67.2% | −78.6% | −77.9% | −57.2% | **−70.3%** |
| `mixed6-1k` | control | +0.9% | +4.2% | −0.8% | −3.8% | +0.1% |
| `int20-10k` | control | −2.4% | −6.7% | +0.7% | +21.3% | +3.2% |
| `cap-abort` | guard | +26.4% | +15.3% | +48.1% | +9.0% | **+24.7%** |

### `ab_drift_check.dart` verdicts

Passes were paired (1,2) and (3,4) and classified by
`benchmark/ab_drift_check.dart`:

| lane | pair 1 | pair 2 |
|---|---|---|
| `point1` | REPRODUCED | REPRODUCED |
| `point1-wide20` | REPRODUCED | REPRODUCED |
| `page20` | REPRODUCED | REPRODUCED |
| `page64` | drift-suspected (sign reversal) | REPRODUCED |
| `point-under-load` | REPRODUCED | REPRODUCED |
| `concurrent8` | REPRODUCED | REPRODUCED |
| `mixed6-1k` | neutral | neutral |
| `int20-10k` | neutral | neutral |
| `cap-abort` | REPRODUCED | REPRODUCED |

`page64` is the only lane that does not classify cleanly, and its pass-2
candidate median (621 us) is roughly double its other three (317/329/315 us)
while the baseline holds at 397-469 us throughout. Read as a single contaminated
phase rather than as a real reversal: the lane is at the cap, where the decode is
large enough that the removed hop is no longer the dominant term, so its true
effect is the smallest of the primaries and the easiest for a saturated host to
swamp.

## Collection 1 — 41 samples/lane

Independent, on the same host, before the `concurrent8` resolution fix:

| lane | p1 | p2 | p3 | p4 | mean |
|---|---:|---:|---:|---:|---:|
| `point1` | −78.0% | −69.1% | −70.7% | −75.8% | −73.4% |
| `point1-wide20` | −79.6% | −79.6% | −68.8% | −68.2% | −74.1% |
| `page20` | −50.2% | −52.3% | −50.7% | −27.7% | −45.2% |
| `page64` | −32.7% | −30.3% | −25.3% | +3.7% | −21.1% |
| `point-under-load` | −91.2% | −95.0% | −89.2% | −91.6% | −91.7% |
| `concurrent8` | −47.4% | −84.8% | −76.0% | −47.2% | −63.8% |
| `mixed6-1k` | +28.3% | −0.8% | +3.8% | −12.6% | +4.6% |
| `int20-10k` | −11.6% | +6.1% | −26.9% | −1.4% | −8.5% |
| `cap-abort` | +17.0% | +29.5% | +35.8% | +32.2% | +28.6% |

Every primary agrees with collection 2 in sign and magnitude. The controls are
looser here (+4.6% and −8.5% mean, against +0.1% and +3.2%), which is what a
41-sample lane on a saturated host buys, and `concurrent8` swings between −47%
and −85% at a sample size of ~30 us where a single stopwatch tick is 3% — the
reason it was re-cut into ten groups per sample.

## Memory

`maxRss` per lane, one process per lane, collection 2 pass 1:

| lane | baseline | candidate |
|---|---:|---:|
| `point1` | 30.0 MB | 30.1 MB |
| `point1-wide20` | 23.8 MB | 25.5 MB |
| `page20` | 29.9 MB | 30.6 MB |
| `page64` | 29.9 MB | 30.7 MB |
| `point-under-load` | 54.7 MB | 58.7 MB |
| `concurrent8` | 30.3 MB | 30.2 MB |
| `mixed6-1k` | 29.7 MB | 30.0 MB |
| `int20-10k` | 65.9 MB | 65.1 MB |
| `cap-abort` | 29.7 MB | 31.3 MB |

The reserved reader connection costs +0.1 to +1.7 MB, and two lanes read down —
at or below what exp 261's guard resolves (claim 261.2). A connection's page cache
is demand-filled and the inline connection reads pages the workers have already
made resident.

## No release-suite run

Not attempted. Exps 260, 261 and 264 each established that the suite dies inside
the sqlite_async peer at the `Memory` scenario (#282) and wedges the parent
process rather than exiting, and this host was already at 0% idle with a nearly
full volume. A single-sample partial artifact with no paired baseline would not
be evidence for this experiment in any case — no release lane resolves a
microsecond of per-read scheduling, which is why `**Benchmark Run:** none` is
declared in the writeup and the focused harness is the durable gate.

## Validation

- `dart analyze` clean across the package.
- `dart test` — 463 tests, all passing, including the nine routing and
  correctness tests in `test/inline_select_test.dart` (reverted with the
  prototype; preserved at `archive/exp-265`).
- `dart run build_runner build --delete-conflicting-outputs` before both, since
  `benchmark/drift/*.g.dart` is gitignored.
