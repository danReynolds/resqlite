---
component: meta
title: Measurement & method
kicker: meta
zone: native
diagram: meta
directions: [measurement-system]
feeds: []
section: architecture
---

Every number in this documentation came through a measurement discipline that had to be learned by getting it wrong first. This chapter is about how resqlite knows what it knows — and it is part of the architecture, because a performance library whose measurements cannot be trusted is a library whose design decisions cannot be trusted either.

## The gates

Every A/B runs as order-flipped pairs, and drift detection is built into the statistics rather than applied by judgment. Two signatures kept recurring in writeups until they were encoded: CV asymmetry, where the flagged phase's coefficient of variation is several times its clean phase's, and sign reversal across the flip. Both now classify automatically [[177.1]]. Before that, every A/B re-derived the same reasoning by hand, and the failure mode was silent — an experiment that measured drift and reported a win.

Profile runs emit structured, validated evidence with stable insight IDs, so a half-empty artifact exits non-zero instead of looking complete [[143.1]] [[169.1]]. Every chartable experiment must link a benchmark run or explicitly declare why it has none; a silently unmapped result is a CI error, which closed a gap where roughly eighteen accepted experiments had quietly dropped off the charts [[178.1]].

## The lesson that generalized

The deepest methodological result came from a question that resisted measurement for months: is sacrificing a reader worth it?

The obvious experiment — alternate send and sacrifice inside one live pool — is invalid, and understanding *why* is the transferable part. Sacrifice is a state-changing treatment: each firing kills a worker, triggers a respawn, and clears statement caches. Measurement *i* therefore changes the conditions of measurement *i+1*, and the accumulated respawn state biases toward the sacrifice lane. No amount of re-running fixes it, because the instrument is confounded rather than noisy.

The answer came from splitting the question into estimands and measuring each in isolation: intrinsic transfer via a prepared-result barrier with one fresh process per observation, and pool capacity via a barrier burst with the pool rebuilt between samples [[241.1]]. That decomposition is now the standard approach for anything that mutates its own environment.

A second habit came out of the same arc: when a candidate has a mechanically unreachable configuration, add it as an explicit control lane. Lanes running identical code on both sides read the harness's noise floor directly, which settles verdicts without collecting more primary-lane samples.

## Proportion, before optimization

The most useful thing measurement has produced recently is not a win but a ratio. Intrinsic transfer of a 200k-slot result costs roughly 391 µs against an end-to-end select of about 6,100 µs — so the entire cross-isolate transfer question, four experiments deep, governs 6–12% of a large read.

The other ~90% — SQLite stepping plus building the Dart object graph — has never been decomposed. That measurement is the current frontier, and it is deliberately sequenced before any further transport work, because it decides whether the next optimization belongs in native code or in Dart at all.

## Why this is documented at all

Knowledge decays. This project's failure mode is not forgetting results — they are written down — but citing them after they stop being true. That is what the claims layer beneath this documentation exists to prevent: every assertion above carries a citation into an addressable, dated claim, and when future work supersedes one, the citation turns amber and CI reports which passage needs repair. The facts are machine-owned; the story is human-owned; the seam between them is linted.
