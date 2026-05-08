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
      'writer_roundtrip_us': 0,
      'writer_write_call_us': 0,
      'writer_batch_param_pack_us': 0,
      'writer_batch_native_write_us': 0,
      'writer_dirty_fetch_us': 0,
      'writer_request_count': 0,
      'stream_requery_await_us': 0,
      'stream_requery_count': 0,
      'stream_requery_changed_count': 0,
      'stream_requery_unchanged_count': 0,
      'stream_requery_discarded_count': 0,
      'stream_emit_us': 0,
      'stream_emit_count': 0,
      'reader_dispatch_wait_us': 0,
      'reader_reply_delivery_us': 0,
      'reader_reply_delivery_count': 0,
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
      'writer_roundtrip_us': 0,
      'writer_write_call_us': 0,
      'writer_batch_param_pack_us': 0,
      'writer_batch_native_write_us': 0,
      'writer_dirty_fetch_us': 0,
      'writer_request_count': 0,
      'stream_requery_await_us': 0,
      'stream_requery_count': 0,
      'stream_requery_changed_count': 0,
      'stream_requery_unchanged_count': 0,
      'stream_requery_discarded_count': 0,
      'stream_emit_us': 0,
      'stream_emit_count': 0,
      'reader_dispatch_wait_us': 0,
      'reader_reply_delivery_us': 0,
      'reader_reply_delivery_count': 0,
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

  test('writer profile counters round-trip through snapshot/diff/reset', () {
    ProfileCounters.writerRoundtripUs = 100;
    ProfileCounters.writerWriteCallUs = 70;
    ProfileCounters.writerBatchParamPackUs = 40;
    ProfileCounters.writerBatchNativeWriteUs = 25;
    ProfileCounters.writerDirtyFetchUs = 3;
    ProfileCounters.writerRequestCount = 2;

    final snap = ProfileCounters.snapshot();
    expect(snap['writer_roundtrip_us'], 100);
    expect(snap['writer_write_call_us'], 70);
    expect(snap['writer_batch_param_pack_us'], 40);
    expect(snap['writer_batch_native_write_us'], 25);
    expect(snap['writer_dirty_fetch_us'], 3);
    expect(snap['writer_request_count'], 2);

    ProfileCounters.reset();
    expect(ProfileCounters.writerRoundtripUs, 0);
    expect(ProfileCounters.writerWriteCallUs, 0);
    expect(ProfileCounters.writerBatchParamPackUs, 0);
    expect(ProfileCounters.writerBatchNativeWriteUs, 0);
    expect(ProfileCounters.writerDirtyFetchUs, 0);
    expect(ProfileCounters.writerRequestCount, 0);
  });

  test('stream and reader completion counters round-trip', () {
    ProfileCounters.streamRequeryAwaitUs = 100;
    ProfileCounters.streamRequeryCount = 4;
    ProfileCounters.streamRequeryChangedCount = 3;
    ProfileCounters.streamRequeryUnchangedCount = 1;
    ProfileCounters.streamRequeryDiscardedCount = 2;
    ProfileCounters.streamEmitUs = 12;
    ProfileCounters.streamEmitCount = 3;
    ProfileCounters.readerDispatchWaitUs = 80;
    ProfileCounters.readerReplyDeliveryUs = 7;
    ProfileCounters.readerReplyDeliveryCount = 4;

    final snap = ProfileCounters.snapshot();
    expect(snap['stream_requery_await_us'], 100);
    expect(snap['stream_requery_count'], 4);
    expect(snap['stream_requery_changed_count'], 3);
    expect(snap['stream_requery_unchanged_count'], 1);
    expect(snap['stream_requery_discarded_count'], 2);
    expect(snap['stream_emit_us'], 12);
    expect(snap['stream_emit_count'], 3);
    expect(snap['reader_dispatch_wait_us'], 80);
    expect(snap['reader_reply_delivery_us'], 7);
    expect(snap['reader_reply_delivery_count'], 4);

    ProfileCounters.reset();
    expect(ProfileCounters.streamRequeryAwaitUs, 0);
    expect(ProfileCounters.streamRequeryCount, 0);
    expect(ProfileCounters.streamRequeryChangedCount, 0);
    expect(ProfileCounters.streamRequeryUnchangedCount, 0);
    expect(ProfileCounters.streamRequeryDiscardedCount, 0);
    expect(ProfileCounters.streamEmitUs, 0);
    expect(ProfileCounters.streamEmitCount, 0);
    expect(ProfileCounters.readerDispatchWaitUs, 0);
    expect(ProfileCounters.readerReplyDeliveryUs, 0);
    expect(ProfileCounters.readerReplyDeliveryCount, 0);
  });
}
