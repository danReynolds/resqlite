/// Compile-time flag that enables experiment-mode diagnostic
/// instrumentation in resqlite's internal code paths.
///
/// **Default: false.** A normal `dart run` / `dart compile` / Flutter
/// release build produces a resqlite binary with zero diagnostic
/// overhead — the `if (kProfileMode)` branches tree-shake away at AOT
/// compile time, leaving no bytes and no cycles on the hot path.
///
/// **Enable by passing `-DRESQLITE_PROFILE=true` at build / run time.**
/// Example:
///
/// ```bash
/// # Peer-comparison benchmarks — pristine production code:
/// dart run benchmark/run_release.dart my-label
///
/// # Experiment-vs-baseline diagnostics — preferred tracelite wrapper:
/// dart run benchmark/profile/run_tracelite_profile.dart \
///   --tracelite-root=/path/to/tracelite \
///   --label=exp-N
/// ```
///
/// **What the flag currently gates:**
/// - `Timeline.startSync` / `finishSync` markers around per-message
///   dispatch in the writer and reader isolates. See
///   `lib/src/writer/write_worker.dart` and `lib/src/reader/read_worker.dart`.
/// - `ProfileCounters` increments in the benchmark harness wrapper
///   (`benchmark/profile/profiled_database.dart`). The counters
///   themselves live in `lib/src/profile_counters.dart` and are
///   public API — but increments only fire when the flag is on.
/// - Optional tracelite spans and counters when the run also passes
///   `-DRESQLITE_TRACELITE=true` and attaches to a runtime region via
///   `TRACELITE_REGION`. Tracelite remains disabled for ordinary profile
///   runs unless both flags are present.
///
/// **Design contract.** This flag exists so the main peer-comparison
/// benchmarks (`run_release.dart`) can measure resqlite's actual
/// production behavior — the same code paths downstream apps execute —
/// without diagnostic overhead distorting the comparison against
/// sqlite3 / sqlite_async / drift. Profile-mode diagnostics compile both the
/// experiment branch AND its baseline with the flag on, so the per-call
/// overhead of Timeline markers and optional tracelite emitters cancels out in
/// the A/B delta.
///
/// **If you add new diagnostic instrumentation,** gate it behind this
/// flag the same way:
///
/// ```dart
/// if (kProfileMode) {
///   // diagnostic work
/// }
/// ```
///
/// Never introduce unconditional instrumentation to production code
/// paths unless the cost is provably sub-nanosecond per call AND
/// symmetric across all peers being compared.
const bool kProfileMode = bool.fromEnvironment(
  'RESQLITE_PROFILE',
  defaultValue: false,
);
