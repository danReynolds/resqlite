---
component: meta
title: Measurement & method
kicker: meta
zone: native
order: 7
directions: [measurement-system]
---

How we know what we know. Every number in this document came through a harness discipline that had to be learned the hard way — and is now enforced in code rather than convention.

## The discipline

A/B gates run order-flipped pairs with drift detection built in: CV asymmetry and sign reversal — the two signatures that once had to be re-derived by hand in every writeup — now flag automatically [[177.1]]. Profile runs emit structured, validated evidence with stable insight IDs, so a half-empty artifact fails loudly [[143.1]] [[169.1]]. Every chartable experiment must link its benchmark run or declare why not [[178.1]]. And the deepest lesson: a treatment that mutates its own environment — like sacrifice killing the pool it runs in — cannot be A/B’d in place; it must be split into estimands measured in isolation [[241.1]].
