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
      'writer_request_us': 0,
      'writer_request_count': 0,
      'writer_sqlite_us': 0,
      'writer_dirty_drain_us': 0,
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
      'writer_request_us': 0,
      'writer_request_count': 0,
      'writer_sqlite_us': 0,
      'writer_dirty_drain_us': 0,
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

  test('writer timing counters round-trip through snapshot/diff/reset', () {
    ProfileCounters.writerRequestUs = 100;
    ProfileCounters.writerRequestCount = 2;
    ProfileCounters.writerSqliteUs = 70;
    ProfileCounters.writerDirtyDrainUs = 8;

    final before = ProfileCounters.snapshot();

    ProfileCounters.writerRequestUs += 40;
    ProfileCounters.writerRequestCount += 1;
    ProfileCounters.writerSqliteUs += 30;
    ProfileCounters.writerDirtyDrainUs += 4;

    final diff = ProfileCounters.diff(before, ProfileCounters.snapshot());
    expect(diff['writer_request_us'], 40);
    expect(diff['writer_request_count'], 1);
    expect(diff['writer_sqlite_us'], 30);
    expect(diff['writer_dirty_drain_us'], 4);

    ProfileCounters.reset();
    expect(ProfileCounters.writerRequestUs, 0);
    expect(ProfileCounters.writerRequestCount, 0);
    expect(ProfileCounters.writerSqliteUs, 0);
    expect(ProfileCounters.writerDirtyDrainUs, 0);
  });
}
