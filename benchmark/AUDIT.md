# Benchmark Pipeline Audit

**Purpose:** document how benchmark results propagate from Dart code to the
public dashboard, so future workload additions are planned against accurate
constraints (not assumptions). Produced as Phase 0.1 of the Track A plan.

## Pipeline overview

```
benchmark/suites/*.dart
    │
    │  dart run benchmark/run_release.dart <label>
    ▼
benchmark/results/YYYY-MM-DDTHH-MM-SS-<label>.md   (per-run markdown)
benchmark/results/YYYY-MM-DDTHH-MM-SS-<label>.json (summary sidecar)
    │
    ├──► generate_history.dart ──► docs/experiments/history.json
    │                              │
    │                              └──► docs/experiments/index.html
    │                                   (chart.js line charts over time)
    │
    └──► generate_devices.dart ──► docs/benchmarks/devices.json
         (reads HARDWARE_RESULTS.md   │
          to select the canonical     │
          result per device)          └──► docs/benchmarks/index.html
                                           (chart.js cross-library charts
                                            for the selected device)
```

`generate_blog.dart` is unrelated — it generates `docs/blog/*.html` from
architecture docs. Not part of the benchmark pipeline.

## Markdown result file contract

Every result file under `benchmark/results/` follows this shape (enforced
implicitly by the parsers; changes here break the pipeline):

```markdown
# resqlite Benchmark Results

Generated: 2026-04-16T23:42:22

## Section Title

Optional description.

### Subsection Title

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.41 | 0.53 | 0.10 | 0.13 |
| sqlite3 select() | 0.81 | 1.02 | 0.81 | 1.02 |
| sqlite_async getAll() | 0.74 | 0.92 | 0.17 | 0.19 |
```

Rules the parsers enforce:
- `## Section` starts a new section
- `### Subsection` (optional) further qualifies
- Table rows must start with `| ` and library name; header rows
  (`library`, `rows`, `concurrency`, `n`) are skipped
- Numeric cells parsed left-to-right; first is wall-med (primary metric)
- `Comparison vs Previous Run`, `Repeat Stability`, `resqlite Benchmark`
  sections are deliberately skipped by the device parser
- **The `Concurrent Reads` section is special-cased** in
  `parse_results.dart:51` — its rows are parsed as `| N | wall_med | ...`
  (concurrency number, not library name, in the first cell)

## Structured summary sidecar contract

New release benchmark runs now emit a structured sidecar next to the markdown:

```text
benchmark/results/YYYY-MM-DDTHH-MM-SS-<label>.md
benchmark/results/YYYY-MM-DDTHH-MM-SS-<label>.json
```

This is the current contract:

- The **markdown** file remains the human-readable artifact.
  It is the narrative report and the legacy compatibility format for older
  runs that predate sidecars.
- The **JSON sidecar** is the canonical machine-readable summary for new runs.
  Generators and dashboards should prefer it when present.
- The sidecar is intentionally a **summary artifact**, not a raw dump.
  It should stay compact enough to check in.

Current sidecar fields (`schemaVersion: 3`):

- `kind`: identifies the artifact as a release benchmark run
- `generatedAt`, `label`, `repeatCount`
- `environment`: runtime / OS / git provenance
- `metrics`: flat resqlite median metrics used by `history.json`
- optional namespaced metrics:
  - `memoryMetrics`
  - `sqliteDiagnosticsMetrics`
  - `streamingColumnMetrics`
- `repeatAggregates`: compact repeat-run stability summary
  - `median`
  - `madPct`
  - `stability`
  - `comparisonThresholdPct`
- `benchmarkSummary`: compact structured benchmark sections used by
  `devices.json`

Intentionally **not** included in the checked-in summary artifact:

- parsed copies of every markdown section under a `benchmarks` key
- raw per-repeat sample arrays
- min/max/range debug stats that are useful for investigation but not
  needed by dashboards or experiment history

Fallback policy:

- `generate_history.dart` prefers sidecar metrics/environment and falls back
  to markdown parsing for historical runs with no sidecar
- `generate_devices.dart` prefers `benchmarkSummary` and falls back to markdown
  section parsing when the sidecar is missing or predates that field

Schema evolution policy:

- Additive fields are preferred.
- Bumping `schemaVersion` is required when the meaning of an existing field
  changes or when consumers must branch on the new shape.
- Backward compatibility we intentionally preserve today:
  - legacy sidecars with embedded `benchmarks`
  - slimmed sidecars with no `benchmarkSummary`, via markdown fallback
- New code should avoid making historical checked-in sidecars unreadable unless
  there is a strong migration plan and fixture coverage for it.

Practical rule:

- If a change would force machine consumers to scrape markdown again for new
  runs, that is a regression
- If a change adds large debug-only payloads to the checked-in sidecar, that is
  also a regression unless there is a strong reason and a documented schema bump

## Parser #1 — `generate_history.dart`

**Produces:** `docs/experiments/history.json`

**Used by:** `docs/experiments/index.html` — experiment timeline charts

**What it extracts:**
- **Runs**: one entry per result file, each with a flat `metrics` map
  (keys like `Select → Maps / 1000 rows / resqlite select()` → wall-med value)
- **Optional namespaced metrics**: `memoryMetrics` and
  `sqliteDiagnosticsMetrics` from the non-timing `## Memory` and
  `## SQLite Diagnostics` sections
- **Experiments**: parses `experiments/README.md` table rows + reads each
  individual `experiments/NNN-*.md` for date, commit, sections (Problem,
  Hypothesis, What We Built, Results, Decision)
- **Tracked**: curated metric registry for default dashboard display,
  including short labels and chart grouping, resolved via
  `benchmark/shared/workload_registry.dart`

**Extension points:**
- `curatedMetricDefinitions` in
  `benchmark/shared/workload_registry.dart` — add a new tracked metric,
  short display label, and destination chart group for the experiments
  page
- `_extractSection()` — whitelist of accepted experiment-doc headings.
  Already covers 10+ variants (Problem, Hypothesis, What We Built, etc.).
- The `metrics` map extraction in `extractResqliteMedians()` is already
  general for timing sections, but explicit non-timing sections must be
  excluded there and parsed by dedicated extractors. Today those are
  `## Memory`, `## SQLite Diagnostics`, and
  `## Streaming (Column Granularity)`.

## Parser #2 — `generate_devices.dart`

**Produces:** `docs/benchmarks/devices.json`

**Used by:** `docs/benchmarks/index.html` — cross-library comparison charts

**Device selection:** reads `benchmark/HARDWARE_RESULTS.md`, which has a
"## Devices" table mapping device name → canonical result filename. Each
device prefers the sidecar `benchmarkSummary` when present and only falls
back to parsing the markdown tables for older runs.

**Extension points:**
- **Sections skipped** at line 116–120: `Comparison`, `Repeat`,
  `resqlite Benchmark`. Any section starting with these is ignored.
- **Header rows skipped** at line 138–140: first cell `library`, `rows`,
  `concurrency`, `n`.
- **Full-cell parsing** — all numeric cells after column 0 become a `values`
  array. So adding a 5th column (e.g., emission count) is natively supported;
  it becomes `values[4]` in the JSON.

**Conclusion:** adding a new scenario workload as standard `## Section /
### Subsection / table` requires *zero generator changes*. Only the
dashboard's `index.html` needs updates to render the new data.

## Dashboard #1 — `docs/benchmarks/index.html`

489-line single-page app. No build step. Fetches `devices.json` via
`fetch('./devices.json')` at page load; builds all charts in JS.

**Structure:** device selector dropdown + "Callouts" summary tiles + a
series of hardcoded sections. Walk `docs/benchmarks/index.html` for the
authoritative list; as of this audit it looks approximately like:

| Section | Chart functions | Canvas IDs |
|---|---|---|
| Scaling Curves | `buildScaling()` | `cScaleMaps`, `cScaleBytes` |
| Main-Isolate Cost | `buildMainIsolate()` | `cMainMaps`, `cMainBytes` |
| Schema Shapes | `buildGroupedBar()` | `cSchemas` |
| Write Performance | `buildSingleBar()`, `buildGroupedBar()` | `cSingleInserts`, `cBatchInserts`, `cTxWrites`, `cTxReads` |
| Concurrent & Parameterized | `buildConcurrent()`, `buildSingleBar()` | `cConcurrent`, `cParam` |
| Streaming | `buildStreaming()` | `cStreaming` |
| Streaming (Column Granularity) | dedicated chart builder | driven by `disjoint_columns.dart` markdown |
| Memory (RSS) | dedicated chart builder | driven by `memory.dart` markdown |

**How chart builders match sections:** by `title` substring filter over
the `benchmarks` array. Example:
```js
function buildScaling(B, titleMatch, canvasId) {
  const sections = B.filter(s =>
    s.title?.includes(titleMatch) && s.subtitle);
  // ...
}
```

**This means adding a new workload that follows the existing format
(section → subsection → table) works "natively" in JSON but will not render
on the dashboard until an HTML/JS edit adds:**
1. A `<div class="card">` with a new canvas ID
2. A `buildXxx(B, 'Title Match', 'canvasId')` function call
3. Optionally, a new `buildXxx()` function if the chart shape is new

**Callouts logic** at lines 262–293 is hardcoded: reads specific benchmark
keys (`Select Maps 1000`, `Single Inserts`, `Point Query`) to compute
speedup ratios. New callouts need edits here too.

## Dashboard #2 — `docs/experiments/index.html`

915-line single-page app. Fetches `history.json`. Renders experiment
timeline: line charts of tracked metrics over time (x-axis = experiment
number/date, y-axis = ms), plus filterable experiment list.

**Tab structure:** Reads, Writes, Transactions, Concurrency, Scenarios,
Reactive Micros, Throughput. The chart-group assignments now come from
`history.json` (`chartGroups`), which is generated from
`benchmark/shared/workload_registry.dart`.

**Changing tracked metrics:** edit `curatedMetricDefinitions` in
`benchmark/shared/workload_registry.dart`, then regenerate
`docs/experiments/history.json`.

## What changes for planned Phase 1–3 workloads

### A10 column-disjoint streams, A11 keyed PK subs (Phase 1)

Structure as `## Reactive / Column-disjoint streams` and
`## Reactive / Keyed PK subscriptions`. Standard 4-column table.

**Extra metric needed: emission count.** Options:
- **Option A (recommended):** emit as a 5th column in the standard table:
  `| Library | Wall med | Wall p90 | Main med | Main p90 | Emissions |`
  — native parser support via `values[4]`. Dashboard chart builder needs
  a new `buildEmissionChart()` function that reads `values[4]` as the
  primary bar metric.
- **Option B:** emit as a separate `### Emissions` subsection. More markdown
  overhead; harder to correlate with timing.

Option A wins on both parser simplicity and dashboard plot simplicity.

### A5 chat sim, A6 feed paging (Phase 2)

Per-op-type breakdown. Structure:
```
## Chat Sim
### Read last-20 messages (conversation query)
| resqlite select() | ... |
...
### Update conversation last_msg_at
| ... |
```

Each op type becomes a separate section/subsection. Parser handles this
natively.

**Dashboard additions:**
- New section "Scenarios" near the top
- `buildScenarioBreakdown(B, 'Chat Sim', 'cChatSim')` — per-op grouped bar
  chart showing all three libraries across all op types in the scenario

### Phase 3 workloads (behind `--include-slow`)

Same format. No special treatment needed beyond the `--include-slow` flag
in `run_release.dart` to opt in.

## Generator changes needed (summary)

| Task | Which generator | Change |
|---|---|---|
| A10/A11 emission counts | `generate_history.dart` | Add patterns to `_trackedPatterns` for new keyed metrics |
| A10/A11 emission counts | `generate_devices.dart` | No change — 5th column parsed natively |
| A5/A6 per-op metrics | Both | No change — sections parsed natively |
| Scenarios tab on exp dashboard | `generate_history.dart` + `docs/experiments/index.html` | Categorize Scenario workloads; add tab |
| Scenarios section on bench dashboard | `docs/benchmarks/index.html` | New section + `buildScenarioBreakdown()` function |
| Emission-count chart | `docs/benchmarks/index.html` | New `buildEmissionChart()` function |
| SCOPE.md scope banner | `docs/benchmarks/index.html` | Static HTML insert at top, reading `SCOPE.md` content |

**The generator changes are small.** The dashboard HTML is where the real
(non-zero but bounded) work lives. Estimate for Phase 0.3 scope:
~150–250 LOC of JS across 4–6 new chart builders + one Scenarios section
+ scope banner.

## Extension-point cheatsheet (line refs for later)

Line numbers are approximate — files evolve. Use `grep` to find them
fresh if the anchors have drifted:

- Curated metric registry: `benchmark/shared/workload_registry.dart`
  — search for `const curatedMetricDefinitions = [`
- `_extractSection` heading variants: `benchmark/generate_history.dart`
  — search for `String? _extractSection`
- Skip-sections list: `benchmark/generate_devices.dart` — search for
  `currentSection.startsWith('Comparison')`
- Header-row skip: `benchmark/generate_devices.dart` — search for
  `firstCell == 'library'`
- Concurrent-reads special case: `benchmark/shared/parse_results.dart`
  — search for `Concurrent Reads`
- Dashboard chart sections: `docs/benchmarks/index.html` — search for
  `section-title` and `chartsContainer`
- Callouts logic: `docs/benchmarks/index.html` — search for `callouts`

## Recommendations for Phase 0.3 (dashboard extensions)

1. **Do not change parser output formats.** Structure all new workloads as
   standard `## Section / ### Subsection / table` with 4 or 5 numeric
   columns. Parsers handle this natively.

2. **Add new chart builders next to existing ones** in `index.html`.
   Don't refactor existing ones unless a bug emerges.

3. **Add a new "Scenarios" section** in the benchmarks dashboard for
   A5/A6/A7/A9 between Streaming and bottom. Keeps the "ops" sections
   (Scaling, Schema Shapes, Writes) separate from full scenarios.

4. **Emission-count column**: add to every reactive-workload table. New
   `buildEmissionChart()` function renders it as a grouped bar chart
   (lower is better — tells the "we don't over-fire" story).

5. **Scope banner**: static HTML near the top of `docs/benchmarks/index.html`,
   reading content from `SCOPE.md`. Either inline-copied at generator time
   or loaded via fetch; inline is simpler.

6. **Callouts**: revisit after the Scenarios section is in place. Possibly
   surface one scenario-level number (e.g., "Chat Sim main-isolate time").

## Known gaps in existing pipeline (noted for future)

- **No machine-variance data.** Only one device in `HARDWARE_RESULTS.md`
  today. When we add a second, the dashboard selector already supports it.
- **No noise bars on dashboard charts.** The `--repeat=5` p90 values exist
  in the markdown and JSON but aren't visualized. Worth a follow-up.
  *(Partially mitigated:* `generate_history.dart` flags runs as `noisy`
  when `Repeats: 1` or when sqlite3's single-insert control is elevated,
  and both the experiments timeline and the public benchmarks "Last N
  runs" mode skip those runs. The original methodology gap — showing
  per-run uncertainty inline — is still open.*)*
- **Callouts are hardcoded.** Moving them to config (a JSON block in
  `SCOPE.md` or similar) would keep them fresh as workloads evolve.
- **No "methodology" link** on the benchmarks page. Phase 4.1 addresses
  this.
- **`generate_blog.dart` is coupled to specific arch doc paths** — not a
  benchmark problem but worth noting if we reorganize `doc/`.

## Conclusion

The pipeline is straightforward: the bottleneck isn't the parsers, it's
the hand-written dashboard HTML/JS that filters the parsed JSON by
substring. Adding workloads in the existing markdown shape is cheap;
adding dashboard sections is a small but non-zero HTML edit per workload
category. Phase 0.3 should budget ~200 LOC of JS and is entirely
well-understood based on this audit.
