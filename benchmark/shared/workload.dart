/// Workload metadata + versioning convention for scenario benchmarks.
///
/// Every new scenario-level workload (A5 chat sim, A6 feed paging, A10
/// column-disjoint streams, etc.) declares a [WorkloadMeta] constant with
/// a slug, version, human title, and brief description.
///
/// Rationale (see METHODOLOGY.md § Workload versioning):
///
/// When a workload's op mix, schema, or seed changes materially, bump
/// [version]. The markdown section heading and all emitted metric keys
/// include the version, so the old data trajectory on the dashboard is
/// preserved as a separate series and the new data starts a fresh one.
/// Silent drift in workload meaning is the single biggest risk to the
/// credibility of trend charts; versioning makes changes explicit.
///
/// "Materially" means any of: schema change, seed-row count change >2×,
/// op-mix ratio change >10%, distribution change (uniform → Zipfian),
/// or any new operation type added to the rotation.
///
/// Cosmetic changes (comments, formatting, test-only refactors) do NOT
/// bump the version.

/// Metadata for a versioned benchmark workload.
final class WorkloadMeta {
  const WorkloadMeta({
    required this.slug,
    required this.version,
    required this.title,
    required this.description,
  })  : assert(version >= 1, 'Workload versions start at 1'),
        assert(slug.length > 0, 'Slug required');

  /// Snake-case machine identifier. Used in metric keys.
  /// Example: `chat_sim`, `column_disjoint_streams`.
  final String slug;

  /// Monotonically increasing integer version. Starts at 1. Bump on
  /// material changes; do not reset.
  final int version;

  /// Human-readable display name used in markdown section headings.
  /// Example: `Chat Sim`, `Column-Disjoint Streams`.
  final String title;

  /// One-sentence description of what the workload measures and why it
  /// exists. Emitted as a paragraph under the section heading so readers
  /// of the markdown results and the dashboard see the intent next to
  /// the numbers.
  final String description;

  /// Canonical markdown section heading. Example: `Chat Sim (v1)`.
  ///
  /// Workloads emit this as `## ${meta.sectionHeading}` at the top of
  /// their markdown output so parsers and the dashboard route metrics
  /// under the versioned key.
  String get sectionHeading => '$title (v$version)';

  /// Canonical metric key prefix used by `generate_history.dart` pattern
  /// matching. Example: `chat_sim_v1`.
  String get metricKey => '${slug}_v$version';
}
