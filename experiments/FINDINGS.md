# Experiment Findings

This file is the human landing page for the Resqlite experiment research map.
The canonical direction and per-experiment signal data lives in
[`signals.json`](signals.json). Do not duplicate direction summaries here; update
`signals.json` when a run changes the research map.

The research map is context, not an allowed list, a backlog, or an approval
gate. Use it to understand the current terrain, then pursue the highest-signal
idea you can justify, including ideas outside the current map.

## How To Use This

Before starting a scheduled experiment:

- Read [`RUNNER_INSTRUCTIONS.md`](RUNNER_INSTRUCTIONS.md),
  [`README.md`](README.md), and [`signals.json`](signals.json).
- Decide whether the idea follows a known direction, revisits an area that
  recently looked weak, or opens a new speculative direction.
- Write down why the attempt is worth a bounded pass before implementing it.
- Prefer measuring the missing signal first when the likely bottleneck is not
  already visible.

After finishing:

- Update the experiment writeup with the record of what happened.
- Update `signals.json` if the run changes how future agents should interpret
  an area.
- Update this file only for process-level guidance that belongs outside the
  canonical direction map.

## Durable Guidance

- Measurement/profiling work is a valid experiment outcome when the missing
  signal is the real bottleneck.
- Rejected experiments are useful when they explain why a direction looked
  plausible, what was measured, and what would make the area interesting again.
- Direction status labels in `signals.json` are descriptive, not restrictive.
  They should steer future runners without narrowing the search space.
- Keep markdown records readable. Put machine-oriented direction metadata in
  `signals.json`.
