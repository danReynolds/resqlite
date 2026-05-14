# Tracelite graph data

This directory is the GitHub Pages handoff for tracelite artifacts.

Generate/update the latest profile graph-data bundle without copying raw trace
or legacy profile JSON into `docs/`:

```bash
dart run benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/path/to/tracelite \
  --label=<run-id> \
  --graph-data-dir=docs/benchmarks/data/tracelite/latest
```

The benchmark dashboard reads `docs/benchmarks/data/tracelite/latest/index.json`
when present. Missing graph data is allowed; the dashboard falls back to the
legacy `devices.json` charts.

The profile wrapper validates the bundle with `tracelite validate-graph-data`
after export. If you copy or edit graph-data manually, run that command before
committing it for Pages.

Commit graph-data JSON when it is meant to power Pages. Keep raw
`*.tlt-region`, legacy profile JSON, and parity diffs in `build/` or another
scratch artifact location.
