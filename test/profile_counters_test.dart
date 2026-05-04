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

  test(
    'writer-isolate counters are excluded from main-isolate snapshot but reset by reset()',
    () {
      // Writer counters (exp 123) live in `ProfileCounters` but are
      // mutated only inside the writer isolate. Cross-isolate access
      // goes through `Database.writerProfileSnapshot()`. They are
      // deliberately omitted from `snapshot()` — that map is the
      // main-isolate aggregate.
      ProfileCounters.writerHandlerUs = 1000;
      ProfileCounters.writerHandlerCount = 5;
      ProfileCounters.writerNativeUs = 700;
      ProfileCounters.writerNativeCount = 5;

      final snap = ProfileCounters.snapshot();
      expect(snap.containsKey('writer_handler_us'), isFalse);
      expect(snap.containsKey('writer_handler_count'), isFalse);
      expect(snap.containsKey('writer_native_us'), isFalse);
      expect(snap.containsKey('writer_native_count'), isFalse);

      // reset() must still clear them — the writer isolate calls
      // reset() in the same way the main isolate does.
      ProfileCounters.reset();
      expect(ProfileCounters.writerHandlerUs, 0);
      expect(ProfileCounters.writerHandlerCount, 0);
      expect(ProfileCounters.writerNativeUs, 0);
      expect(ProfileCounters.writerNativeCount, 0);
    },
  );
}
