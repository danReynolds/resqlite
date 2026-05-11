import 'package:resqlite/src/profile_counters.dart';
import 'package:test/test.dart';

void main() {
  tearDown(ProfileCounters.reset);

  test('snapshot, diff, and reset include decode counters', () {
    ProfileCounters.rowsDecoded = 3;
    ProfileCounters.cellsDecoded = 12;

    final before = ProfileCounters.snapshot();

    ProfileCounters.rowsDecoded += 2;
    ProfileCounters.cellsDecoded += 8;

    expect(ProfileCounters.diff(before, ProfileCounters.snapshot()), {
      'rows_decoded': 2,
      'cells_decoded': 8,
      'invalidate_us': 0,
      'invalidate_count': 0,
      'intersection_us': 0,
      'intersection_entries': 0,
      'dispatcher_parked_total': 0,
      'dispatcher_wake_retry_total': 0,
      'dispatcher_max_parked_concurrent': 0,
      'writer_handler_us': 0,
      'writer_sqlite_us': 0,
      'writer_handler_count': 0,
      'stream_complete_us': 0,
      'stream_complete_count': 0,
      'stream_emit_us': 0,
      'stream_emit_count': 0,
    });

    ProfileCounters.reset();

    expect(ProfileCounters.snapshot(), {
      'rows_decoded': 0,
      'cells_decoded': 0,
      'invalidate_us': 0,
      'invalidate_count': 0,
      'intersection_us': 0,
      'intersection_entries': 0,
      'dispatcher_parked_total': 0,
      'dispatcher_wake_retry_total': 0,
      'dispatcher_max_parked_concurrent': 0,
      'writer_handler_us': 0,
      'writer_sqlite_us': 0,
      'writer_handler_count': 0,
      'stream_complete_us': 0,
      'stream_complete_count': 0,
      'stream_emit_us': 0,
      'stream_emit_count': 0,
    });
  });

  test('dispatcher park counters round-trip through snapshot/diff/reset', () {
    ProfileCounters.dispatcherParkedTotal = 12;
    ProfileCounters.dispatcherWakeRetryTotal = 8;
    ProfileCounters.dispatcherMaxParkedConcurrent = 5;

    final snap = ProfileCounters.snapshot();
    expect(snap['dispatcher_parked_total'], 12);
    expect(snap['dispatcher_wake_retry_total'], 8);
    expect(snap['dispatcher_max_parked_concurrent'], 5);

    ProfileCounters.reset();
    expect(ProfileCounters.dispatcherParkedTotal, 0);
    expect(ProfileCounters.dispatcherWakeRetryTotal, 0);
    expect(ProfileCounters.dispatcherMaxParkedConcurrent, 0);
    expect(ProfileCounters.dispatcherCurrentParked, 0);
  });

  // Writer-isolate counters added by EXP-135. Snapshot/reset round-trip
  // is exercised here; cross-isolate population is covered by the
  // benchmark/profile audit harnesses.
  test('writer dispatch counters round-trip through snapshot/reset', () {
    ProfileCounters.writerHandlerUs = 1234;
    ProfileCounters.writerSqliteUs = 800;
    ProfileCounters.writerHandlerCount = 50;

    final snap = ProfileCounters.snapshot();
    expect(snap['writer_handler_us'], 1234);
    expect(snap['writer_sqlite_us'], 800);
    expect(snap['writer_handler_count'], 50);

    ProfileCounters.reset();
    expect(ProfileCounters.writerHandlerUs, 0);
    expect(ProfileCounters.writerSqliteUs, 0);
    expect(ProfileCounters.writerHandlerCount, 0);
  });

  // Stream completion counters added by EXP-136. Same round-trip
  // shape as the writer counters above; cross-workload population
  // lives in `benchmark/profile/stream_completion_audit.dart`.
  test('stream completion counters round-trip through snapshot/reset', () {
    ProfileCounters.streamCompleteUs = 4500;
    ProfileCounters.streamCompleteCount = 200;
    ProfileCounters.streamEmitUs = 800;
    ProfileCounters.streamEmitCount = 25;

    final snap = ProfileCounters.snapshot();
    expect(snap['stream_complete_us'], 4500);
    expect(snap['stream_complete_count'], 200);
    expect(snap['stream_emit_us'], 800);
    expect(snap['stream_emit_count'], 25);

    ProfileCounters.reset();
    expect(ProfileCounters.streamCompleteUs, 0);
    expect(ProfileCounters.streamCompleteCount, 0);
    expect(ProfileCounters.streamEmitUs, 0);
    expect(ProfileCounters.streamEmitCount, 0);
  });
}
