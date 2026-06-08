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
      'writer_sqlite_us': 0,
      'writer_sqlite_count': 0,
      'dispatcher_parked_total': 0,
      'dispatcher_wake_retry_total': 0,
      'dispatcher_max_parked_concurrent': 0,
      'completion_handler_us': 0,
      'completion_handler_count': 0,
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
      'writer_sqlite_us': 0,
      'writer_sqlite_count': 0,
      'dispatcher_parked_total': 0,
      'dispatcher_wake_retry_total': 0,
      'dispatcher_max_parked_concurrent': 0,
      'completion_handler_us': 0,
      'completion_handler_count': 0,
      'stream_emit_us': 0,
      'stream_emit_count': 0,
    });
  });

  test('completion counters round-trip through snapshot/diff/reset', () {
    ProfileCounters.completionHandlerUs = 240;
    ProfileCounters.completionHandlerCount = 24;
    ProfileCounters.streamEmitUs = 35;
    ProfileCounters.streamEmitCount = 7;

    final snap = ProfileCounters.snapshot();
    expect(snap['completion_handler_us'], 240);
    expect(snap['completion_handler_count'], 24);
    expect(snap['stream_emit_us'], 35);
    expect(snap['stream_emit_count'], 7);

    ProfileCounters.reset();
    expect(ProfileCounters.completionHandlerUs, 0);
    expect(ProfileCounters.completionHandlerCount, 0);
    expect(ProfileCounters.streamEmitUs, 0);
    expect(ProfileCounters.streamEmitCount, 0);
  });

  test('writer sqlite counters round-trip through snapshot/diff/reset', () {
    ProfileCounters.writerSqliteUs = 420;
    ProfileCounters.writerSqliteCount = 12;

    final snap = ProfileCounters.snapshot();
    expect(snap['writer_sqlite_us'], 420);
    expect(snap['writer_sqlite_count'], 12);

    ProfileCounters.reset();
    expect(ProfileCounters.writerSqliteUs, 0);
    expect(ProfileCounters.writerSqliteCount, 0);
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
}
