import 'package:resqlite/src/profile_counters.dart';
import 'package:test/test.dart';

void main() {
  tearDown(ProfileCounters.reset);

  test('snapshot, diff, and reset include stream counters', () {
    ProfileCounters.rowsDecoded = 3;
    ProfileCounters.cellsDecoded = 12;
    ProfileCounters.streamInvalidationsReceived = 4;
    ProfileCounters.streamAffectedEntries = 10;
    ProfileCounters.streamRerunsRequested = 7;
    ProfileCounters.streamRerunsDeferredInflight = 2;
    ProfileCounters.streamRerunsStarted = 5;
    ProfileCounters.streamResultsUnchanged = 3;
    ProfileCounters.streamResultsStale = 1;
    ProfileCounters.streamEmitsDelivered = 9;

    final before = ProfileCounters.snapshot();

    ProfileCounters.rowsDecoded += 2;
    ProfileCounters.cellsDecoded += 8;
    ProfileCounters.streamInvalidationsReceived += 1;
    ProfileCounters.streamAffectedEntries += 4;
    ProfileCounters.streamRerunsRequested += 3;
    ProfileCounters.streamRerunsDeferredInflight += 1;
    ProfileCounters.streamRerunsStarted += 2;
    ProfileCounters.streamResultsUnchanged += 2;
    ProfileCounters.streamResultsStale += 1;
    ProfileCounters.streamEmitsDelivered += 5;

    expect(ProfileCounters.diff(before, ProfileCounters.snapshot()), {
      'rows_decoded': 2,
      'cells_decoded': 8,
      'stream_invalidations_received': 1,
      'stream_affected_entries': 4,
      'stream_reruns_requested': 3,
      'stream_reruns_deferred_inflight': 1,
      'stream_reruns_started': 2,
      'stream_results_unchanged': 2,
      'stream_results_stale': 1,
      'stream_emits_delivered': 5,
    });

    ProfileCounters.reset();

    expect(ProfileCounters.snapshot(), {
      'rows_decoded': 0,
      'cells_decoded': 0,
      'stream_invalidations_received': 0,
      'stream_affected_entries': 0,
      'stream_reruns_requested': 0,
      'stream_reruns_deferred_inflight': 0,
      'stream_reruns_started': 0,
      'stream_results_unchanged': 0,
      'stream_results_stale': 0,
      'stream_emits_delivered': 0,
    });
  });
}
