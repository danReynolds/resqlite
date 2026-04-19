/// Composition wrapper around [Database] that records per-call timing
/// (and, when kProfileMode is compiled in, decoder allocation counts)
/// for the benchmark-harness subset of the Database API.
///
/// Composition (not subclassing) because `Database` is `final class`.
/// The wrapper exposes the three benchmarked methods the harness calls
/// directly — `execute`, `executeBatch`, `select` — plus a `close`
/// passthrough. No attempt to reproduce the full Database surface, and
/// no production code is modified. Pure streams (`Database.stream`) are
/// not wrapped; the profile harnesses don't exercise them at this layer.
///
/// Paired with `Timeline` markers inside the production worker isolates
/// (gated behind `kProfileMode`) so a profile run produces both the
/// external wall time (from this wrapper) AND the cross-isolate
/// breakdown (from DevTools timeline).
///
/// Allocation counter increments live in [select] and are gated
/// behind `kProfileMode` — tree-shaken out of release builds.
library;

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';

import 'profile_sample.dart';

class ProfiledDatabase {
  ProfiledDatabase(this._db);

  final Database _db;

  /// Collected samples from every call routed through this wrapper.
  /// The harness flushes these to JSON after the workload runs.
  final List<ProfileSample> samples = [];

  /// Expose the underlying Database for operations this wrapper doesn't
  /// instrument (e.g., streams, transactions). Those are out of scope
  /// for the small-op dispatch-budget pass.
  Database get raw => _db;

  Future<void> execute(
    String sql, [
    List<Object?> parameters = const [],
    String? tag,
  ]) async {
    final sw = Stopwatch()..start();
    await _db.execute(sql, parameters);
    sw.stop();
    samples.add(ProfileSample(
      op: 'execute',
      sql: sql,
      totalMicros: sw.elapsedMicroseconds,
      paramCount: parameters.length,
      tag: tag,
    ));
  }

  Future<void> executeBatch(
    String sql,
    List<List<Object?>> paramSets, {
    String? tag,
  }) async {
    final sw = Stopwatch()..start();
    await _db.executeBatch(sql, paramSets);
    sw.stop();
    samples.add(ProfileSample(
      op: 'executeBatch',
      sql: sql,
      totalMicros: sw.elapsedMicroseconds,
      paramCount: paramSets.isEmpty ? 0 : paramSets.first.length,
      batchSize: paramSets.length,
      tag: tag,
    ));
  }

  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> parameters = const [],
    String? tag,
  ]) async {
    final sw = Stopwatch()..start();
    final rows = await _db.select(sql, parameters);
    sw.stop();
    samples.add(ProfileSample(
      op: 'select',
      sql: sql,
      totalMicros: sw.elapsedMicroseconds,
      paramCount: parameters.length,
      rowsReturned: rows.length,
      tag: tag,
    ));
    // Feed the shared decoder-allocation counters so the harness can
    // snapshot main-visible aggregates around a workload. Tree-shaken
    // out in release builds via the `kProfileMode` const gate.
    if (kProfileMode && rows.isNotEmpty) {
      ProfileCounters.rowsDecoded += rows.length;
      ProfileCounters.cellsDecoded += rows.length * rows.first.length;
    }
    return rows;
  }

  Future<void> close() async {
    await _db.close();
  }
}
