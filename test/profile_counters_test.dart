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

  group('WriterProfileCounters', () {
    tearDown(WriterProfileCounters.reset);

    test('snapshot exposes the documented key set with current values', () {
      WriterProfileCounters.writerHandleUs = 1234;
      WriterProfileCounters.writerStepUs = 567;
      WriterProfileCounters.writerHandleCount = 8;

      // The audit harness reads these by name; locking the key set
      // protects callers from accidental contract drift.
      expect(WriterProfileCounters.snapshot(), {
        'writer_handle_us': 1234,
        'writer_step_us': 567,
        'writer_handle_count': 8,
      });
    });

    test('reset clears every field exposed via snapshot', () {
      WriterProfileCounters.writerHandleUs = 99;
      WriterProfileCounters.writerStepUs = 11;
      WriterProfileCounters.writerHandleCount = 3;

      WriterProfileCounters.reset();

      expect(WriterProfileCounters.writerHandleUs, 0);
      expect(WriterProfileCounters.writerStepUs, 0);
      expect(WriterProfileCounters.writerHandleCount, 0);
      expect(WriterProfileCounters.snapshot(), {
        'writer_handle_us': 0,
        'writer_step_us': 0,
        'writer_handle_count': 0,
      });
    });
  });
}
