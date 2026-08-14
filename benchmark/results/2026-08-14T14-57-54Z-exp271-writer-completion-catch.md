# Experiment 271: bounded writer completion catch

Collected 2026-08-14 on arm64 macOS with Dart 3.12.2. The decisive
comparison used native-asset-aware AOT CLI bundles built from an identical
public-API harness. Baseline was `origin/main` at `5555dfa`; candidate source is
preserved at `archive/exp-271` (`cbc6a7f`). Complete per-sample JSON, guard
output, jitter samples, and provenance are in
[`2026-08-14T14-57-54Z-exp271-writer-completion-catch.json`](2026-08-14T14-57-54Z-exp271-writer-completion-catch.json).

> **Verdict: rejected.** A native atomic mailbox did catch completed scalar
> writes before their reply-port event, but bounded polling cost more than the
> event it tried to avoid. No target win reproduced in both run orders. The
> cheapest write regressed 84.1% and 62.7%, errors regressed 205.1% and 368.4%,
> and sustained write throughput fell 65.6% and 37.3%.

## Candidate

The writer isolate remained the sole SQLite executor. For one standalone
`ExecuteRequest`, and only when there were no active streams and profile mode
was off, the main isolate sent the normal request and synchronously polled one
C11-atomic completion slot for at most 24 us per attempt and 48 us across at
most two attempts in an event-loop turn. The worker harvested native dirty
dependencies, release-published affected rows and last insert ID, and still sent
the canonical reply. A caught request left a completed FIFO tombstone for that
reply to remove. Transactions, batches, coalesced groups, active streams,
errors, and profiling retained their port path.

The acceptance gate was a reproduced improvement of at least 15% on sequential
no-stream writes in both orders, with errors, slow writes, transactions,
concurrent writes, active streams, result fidelity, close, and a continuous
16 ms heartbeat guarded.

## Decisive AOT A/B

Pass order was baseline B1, candidate A1, candidate A2, baseline B2. Values are
median microseconds per operation within each seven-sample pass; lower is
better. Deltas compare the adjacent order pair.

| lane | B1 | A1 | delta | A2 | B2 | delta | verdict |
|---|---:|---:|---:|---:|---:|---:|---|
| no-op update | 5.921 | 10.900 | **+84.1%** | 16.615 | 10.213 | **+62.7%** | reproduced regression |
| point update | 16.917 | 19.453 | +15.0% | 25.585 | 31.515 | -18.8% | order-dependent |
| small insert | 16.052 | 17.225 | +7.3% | 19.538 | 21.935 | -10.9% | below gate, order-dependent |
| constraint error | 11.823 | 36.073 | **+205.1%** | 40.010 | 8.542 | **+368.4%** | reproduced regression |
| concurrent burst | 9.861 | 9.969 | +1.1% | 12.131 | 13.314 | -8.9% | neutral/noisy |
| transaction | 42.867 | 35.017 | -18.3% | 39.917 | 27.883 | +43.2% | neutral/noisy |
| slow write | 6116 | 6592 | +7.8% | 6812 | 9316 | -26.9% | neutral/noisy |

All correctness guards passed in every run: the active stream reached 2320,
all 672 expected constraint failures preserved SQLite code 19 plus SQL and
parameters, and the writer recovered afterward.

The timer callback stream stayed live, but it did not make the throughput loss
acceptable:

| pair | baseline writes/s | candidate writes/s | delta |
|---|---:|---:|---:|
| B1 / A1 | 53,204 | 18,314 | **-65.6%** |
| A2 / B2 | 45,892 | 28,757 | **-37.3%** |

The requested 16,667 us period was truncated by Dart 3.12.2 to an effective
16 ms heartbeat. A1 delivered 278 of 279 effective deadlines (one missed), and
A2 delivered 279/279. Their p99/max gaps were 21.094/33.609 ms and
19.803/25.729 ms. The originally emitted `missed_frames` and reported-period
fields are not interpreted: they divided elapsed time by 16,667 us while the
timer actually ran at 16,000 us. Later callbacks may also arrive less than one
period apart, so aggregate count can hide an earlier long gap. The retained
harness now requests 16 ms explicitly and emits full gaps plus a conservative
long-gap lower bound.

B2 suffered one unrelated host spike (270/279 effective deadlines and a
95.692 ms maximum callback gap), so bypass-lane and tail values are not used as
favorable evidence. The target and error failures reproduce without relying on
that pass.

## Tuning and mechanism checks

A full AOT run with a 32 us per-attempt budget made every target worse: no-op
21.702 us, point update 37.214 us, insert 34.617 us, and constraint error
44.833 us. Its heartbeat delivered 279/279 effective deadlines with p99/max
gaps of 16.861/19.945 ms, but it did not rescue wall time.

A separate 5,000-write diagnostic at the 24 us default caught 2,669 of 3,818
poll attempts (69.9%) with 17.8 us mean polling time. Against the same candidate
compiled with polling disabled, that diagnostic improved 38.33 to 35.14 us per
write, only 8.3%. The decisive AOT baseline already completes a no-op write in
5.9-10.2 us. The mailbox can therefore win against its own fixed machinery while
still losing badly to the existing reply-port path. Errors never publish, so
each one pays the full bounded poll before receiving its canonical error; the
reproduced 3-5x error latency is structural, not a tuning miss.

An earlier JIT B-A-A-B agreed on direction but showed within-run warm-up drift,
so it is supporting evidence only: pooled target deltas were +57.2% no-op,
+14.4% point update, +3.6% insert, and +97.7% constraint error.

## Disposition

The prototype is rejected and all runtime, native ABI, build-hook, diagnostic,
and test changes are reverted from the publication branch. The exact prototype
and its adversarial tests remain at `archive/exp-271`; the reusable public-API
harness remains in the repository.

Do not retry a longer spin window or a richer success predictor. Reopen this
direction only if a completion primitive can avoid burning caller-isolate time,
or if representative downstream evidence shows a sequential writer floor much
larger than the 6-32 us AOT range measured here. Any successor must retain the
error miss-path and continuous 16 ms heartbeat guards and clear the 15% target
in both run orders.
