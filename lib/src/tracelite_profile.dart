import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'diagnostics.dart';
import 'profile_mode.dart';

/// Compile-time gate for tracelite profile events.
///
/// This is intentionally separate from [kProfileMode] so existing
/// `RESQLITE_PROFILE=true` runs do not start looking for tracelite runtime
/// symbols unless the harness explicitly opts in:
///
/// ```bash
/// dart run \
///   -DRESQLITE_PROFILE=true \
///   -DRESQLITE_TRACELITE=true \
///   benchmark/run_profile.dart
/// ```
const bool kTraceliteProfileMode = bool.fromEnvironment(
  'RESQLITE_TRACELITE',
  defaultValue: false,
);

const int _trackKindIsolate = 1;
const int _metadataKindAddSpan = 0x0001;
const int _stringOverflow = 0xFFFFFFFF;

/// User-range span IDs reserved by resqlite for tracelite profile mode.
abstract final class TraceliteResqliteSpans {
  static const int databaseSelect = 0x4000;
  static const int databaseSelectBytes = 0x4001;
  static const int databaseExecute = 0x4002;
  static const int databaseExecuteBatch = 0x4003;
  static const int writerHandle = 0x4010;
  static const int readerHandle = 0x4011;
  static const int readerPoolDispatch = 0x4012;
  static const int streamInvalidate = 0x4020;
  static const int profileWorkload = 0x4030;
  static const int profileSample = 0x4031;
}

/// User-range counter IDs reserved by resqlite for tracelite profile mode.
abstract final class TraceliteResqliteCounters {
  static const int rowsDecoded = 0x4100;
  static const int cellsDecoded = 0x4101;
  static const int invalidateUs = 0x4110;
  static const int invalidateCount = 0x4111;
  static const int intersectionUs = 0x4112;
  static const int intersectionEntries = 0x4113;
  static const int dispatcherParkedTotal = 0x4120;
  static const int dispatcherWakeRetryTotal = 0x4121;
  static const int dispatcherCurrentParked = 0x4122;
  static const int dispatcherMaxParkedConcurrent = 0x4123;
  static const int sqlitePageCacheBytes = 0x4130;
  static const int sqliteSchemaBytes = 0x4131;
  static const int sqliteStmtBytes = 0x4132;
  static const int walBytes = 0x4133;
  static const int streamCount = 0x4134;
  static const int readerBusy = 0x4135;
  static const int rssBeforeBytes = 0x4136;
  static const int rssAfterBytes = 0x4137;
  static const int rssPeakBytes = 0x4138;
  static const int profileRowsDecoded = 0x4140;
  static const int profileCellsDecoded = 0x4141;
  static const int profileInvalidateUs = 0x4142;
  static const int profileInvalidateCount = 0x4143;
  static const int profileIntersectionUs = 0x4144;
  static const int profileIntersectionEntries = 0x4145;
  static const int profileDispatcherParkedTotal = 0x4146;
  static const int profileDispatcherWakeRetryTotal = 0x4147;
  static const int profileDispatcherMaxParkedConcurrent = 0x4148;
  static const int fanoutWriterUs = 0x4150;
  static const int fanoutYieldUs = 0x4151;
  static const int fanoutTotalUs = 0x4152;
  static const int fanoutInvalidateUs = 0x4153;
  static const int fanoutIntersectionUs = 0x4154;
  static const int fanoutIntersectionEntries = 0x4155;
}

const Map<int, String> _spanNames = {
  TraceliteResqliteSpans.databaseSelect: 'resqlite.database.select',
  TraceliteResqliteSpans.databaseSelectBytes: 'resqlite.database.select_bytes',
  TraceliteResqliteSpans.databaseExecute: 'resqlite.database.execute',
  TraceliteResqliteSpans.databaseExecuteBatch:
      'resqlite.database.execute_batch',
  TraceliteResqliteSpans.writerHandle: 'resqlite.writer.handle',
  TraceliteResqliteSpans.readerHandle: 'resqlite.reader.handle',
  TraceliteResqliteSpans.readerPoolDispatch: 'resqlite.reader_pool.dispatch',
  TraceliteResqliteSpans.streamInvalidate: 'resqlite.stream.invalidate',
  TraceliteResqliteSpans.profileWorkload: 'resqlite.profile.workload',
  TraceliteResqliteSpans.profileSample: 'resqlite.profile.sample',
  TraceliteResqliteCounters.rowsDecoded: 'resqlite.rows_decoded',
  TraceliteResqliteCounters.cellsDecoded: 'resqlite.cells_decoded',
  TraceliteResqliteCounters.invalidateUs: 'resqlite.invalidate_us',
  TraceliteResqliteCounters.invalidateCount: 'resqlite.invalidate_count',
  TraceliteResqliteCounters.intersectionUs: 'resqlite.intersection_us',
  TraceliteResqliteCounters.intersectionEntries:
      'resqlite.intersection_entries',
  TraceliteResqliteCounters.dispatcherParkedTotal:
      'resqlite.dispatcher_parked_total',
  TraceliteResqliteCounters.dispatcherWakeRetryTotal:
      'resqlite.dispatcher_wake_retry_total',
  TraceliteResqliteCounters.dispatcherCurrentParked:
      'resqlite.dispatcher_current_parked',
  TraceliteResqliteCounters.dispatcherMaxParkedConcurrent:
      'resqlite.dispatcher_max_parked_concurrent',
  TraceliteResqliteCounters.sqlitePageCacheBytes:
      'resqlite.sqlite_page_cache_bytes',
  TraceliteResqliteCounters.sqliteSchemaBytes: 'resqlite.sqlite_schema_bytes',
  TraceliteResqliteCounters.sqliteStmtBytes: 'resqlite.sqlite_stmt_bytes',
  TraceliteResqliteCounters.walBytes: 'resqlite.wal_bytes',
  TraceliteResqliteCounters.streamCount: 'resqlite.stream_count',
  TraceliteResqliteCounters.readerBusy: 'resqlite.reader_busy',
  TraceliteResqliteCounters.rssBeforeBytes: 'resqlite.rss_before_bytes',
  TraceliteResqliteCounters.rssAfterBytes: 'resqlite.rss_after_bytes',
  TraceliteResqliteCounters.rssPeakBytes: 'resqlite.rss_peak_bytes',
  TraceliteResqliteCounters.profileRowsDecoded: 'resqlite.profile.rows_decoded',
  TraceliteResqliteCounters.profileCellsDecoded:
      'resqlite.profile.cells_decoded',
  TraceliteResqliteCounters.profileInvalidateUs:
      'resqlite.profile.invalidate_us',
  TraceliteResqliteCounters.profileInvalidateCount:
      'resqlite.profile.invalidate_count',
  TraceliteResqliteCounters.profileIntersectionUs:
      'resqlite.profile.intersection_us',
  TraceliteResqliteCounters.profileIntersectionEntries:
      'resqlite.profile.intersection_entries',
  TraceliteResqliteCounters.profileDispatcherParkedTotal:
      'resqlite.profile.dispatcher_parked_total',
  TraceliteResqliteCounters.profileDispatcherWakeRetryTotal:
      'resqlite.profile.dispatcher_wake_retry_total',
  TraceliteResqliteCounters.profileDispatcherMaxParkedConcurrent:
      'resqlite.profile.dispatcher_max_parked_concurrent',
  TraceliteResqliteCounters.fanoutWriterUs: 'resqlite.fanout.writer_us',
  TraceliteResqliteCounters.fanoutYieldUs: 'resqlite.fanout.yield_us',
  TraceliteResqliteCounters.fanoutTotalUs: 'resqlite.fanout.total_us',
  TraceliteResqliteCounters.fanoutInvalidateUs: 'resqlite.fanout.invalidate_us',
  TraceliteResqliteCounters.fanoutIntersectionUs:
      'resqlite.fanout.intersection_us',
  TraceliteResqliteCounters.fanoutIntersectionEntries:
      'resqlite.fanout.intersection_entries',
};

const Map<String, int> _profileCounterIds = {
  'rows_decoded': TraceliteResqliteCounters.profileRowsDecoded,
  'cells_decoded': TraceliteResqliteCounters.profileCellsDecoded,
  'invalidate_us': TraceliteResqliteCounters.profileInvalidateUs,
  'invalidate_count': TraceliteResqliteCounters.profileInvalidateCount,
  'intersection_us': TraceliteResqliteCounters.profileIntersectionUs,
  'intersection_entries': TraceliteResqliteCounters.profileIntersectionEntries,
  'dispatcher_parked_total':
      TraceliteResqliteCounters.profileDispatcherParkedTotal,
  'dispatcher_wake_retry_total':
      TraceliteResqliteCounters.profileDispatcherWakeRetryTotal,
  'dispatcher_max_parked_concurrent':
      TraceliteResqliteCounters.profileDispatcherMaxParkedConcurrent,
};

typedef _AttachNative = Int32 Function(Pointer<Utf8>);
typedef _AttachDart = int Function(Pointer<Utf8>);
typedef _RegisterProducerNative = Int32 Function(
    Uint8, Pointer<Utf8>, Pointer<Utf8>);
typedef _RegisterProducerDart = int Function(int, Pointer<Utf8>, Pointer<Utf8>);
typedef _InternStringNative = Uint32 Function(Pointer<Utf8>, Uint32);
typedef _InternStringDart = int Function(Pointer<Utf8>, int);
typedef _RecordOnTrackNative = Void Function(
    Uint8, Uint16, Pointer<Uint64>, Uint8);
typedef _RecordOnTrackDart = void Function(int, int, Pointer<Uint64>, int);
typedef _RecordCorrelatedOnTrackNative = Void Function(
    Uint8, Uint16, Uint64, Pointer<Uint64>, Uint8);
typedef _RecordCorrelatedOnTrackDart = void Function(
    int, int, int, Pointer<Uint64>, int);
typedef _CounterOnTrackNative = Void Function(Uint8, Uint16, Int64);
typedef _CounterOnTrackDart = void Function(int, int, int);
typedef _CounterCorrelatedOnTrackNative = Void Function(
    Uint8, Uint16, Uint64, Int64);
typedef _CounterCorrelatedOnTrackDart = void Function(int, int, int, int);
typedef _DetachTrackNative = Void Function(Uint8);
typedef _DetachTrackDart = void Function(int);

abstract final class TraceliteProfile {
  static int _nextCorrelationId = 1;
  static _AttachedRuntime? _runtime;
  static bool _attemptedAttach = false;
  static final Map<String, int> _internedStrings = <String, int>{};

  static bool get isEnabled => kProfileMode && kTraceliteProfileMode;

  static int nextCorrelationId() {
    final id = _nextCorrelationId++;
    if (_nextCorrelationId == 0) {
      _nextCorrelationId = 1;
    }
    return id;
  }

  static int internString(String value) {
    final runtime = _attachedRuntime;
    if (runtime == null) return _stringOverflow;
    final cached = _internedStrings[value];
    if (cached != null) return cached;
    final id = _internString(runtime, value);
    if (id != _stringOverflow) {
      _internedStrings[value] = id;
    }
    return id;
  }

  static void begin(
    int spanId, {
    List<int> args = const [],
    int? correlationId,
  }) {
    final runtime = _attachedRuntime;
    if (runtime == null) return;
    _withArgs(args, (ptr, count) {
      if (correlationId == null) {
        runtime.library.beginOnTrack(runtime.trackId, spanId, ptr, count);
      } else {
        runtime.library.beginCorrelatedOnTrack(
          runtime.trackId,
          spanId,
          correlationId,
          ptr,
          count,
        );
      }
    });
  }

  static void end(int spanId, {List<int> args = const [], int? correlationId}) {
    final runtime = _attachedRuntime;
    if (runtime == null) return;
    _withArgs(args, (ptr, count) {
      if (correlationId == null) {
        runtime.library.endOnTrack(runtime.trackId, spanId, ptr, count);
      } else {
        runtime.library.endCorrelatedOnTrack(
          runtime.trackId,
          spanId,
          correlationId,
          ptr,
          count,
        );
      }
    });
  }

  static Future<T> traceAsync<T>(
    int spanId,
    Future<T> Function() body, {
    required int correlationId,
    List<int> beginArgs = const [],
    List<int> Function(T value)? endArgs,
  }) async {
    asyncBegin(spanId, args: beginArgs, correlationId: correlationId);
    try {
      final result = await body();
      asyncEnd(
        spanId,
        args: endArgs == null ? const [] : endArgs(result),
        correlationId: correlationId,
      );
      return result;
    } catch (_) {
      asyncEnd(spanId, correlationId: correlationId);
      rethrow;
    }
  }

  static void asyncBegin(
    int spanId, {
    List<int> args = const [],
    required int correlationId,
  }) {
    final runtime = _attachedRuntime;
    if (runtime == null) return;
    _withArgs(
      args,
      (ptr, count) => runtime.library.asyncBeginOnTrack(
        runtime.trackId,
        spanId,
        correlationId,
        ptr,
        count,
      ),
    );
  }

  static void asyncEnd(
    int spanId, {
    List<int> args = const [],
    required int correlationId,
  }) {
    final runtime = _attachedRuntime;
    if (runtime == null) return;
    _withArgs(
      args,
      (ptr, count) => runtime.library.asyncEndOnTrack(
        runtime.trackId,
        spanId,
        correlationId,
        ptr,
        count,
      ),
    );
  }

  static void counter(int spanId, int value, {int? correlationId}) {
    final runtime = _attachedRuntime;
    if (runtime == null) return;
    if (correlationId == null) {
      runtime.library.counterOnTrack(runtime.trackId, spanId, value);
    } else {
      runtime.library.counterCorrelatedOnTrack(
        runtime.trackId,
        spanId,
        correlationId,
        value,
      );
    }
  }

  static void diagnostics(Diagnostics diagnostics, {int? correlationId}) {
    counter(
      TraceliteResqliteCounters.sqlitePageCacheBytes,
      diagnostics.sqlitePageCacheBytes,
      correlationId: correlationId,
    );
    counter(
      TraceliteResqliteCounters.sqliteSchemaBytes,
      diagnostics.sqliteSchemaBytes,
      correlationId: correlationId,
    );
    counter(
      TraceliteResqliteCounters.sqliteStmtBytes,
      diagnostics.sqliteStmtBytes,
      correlationId: correlationId,
    );
    counter(
      TraceliteResqliteCounters.walBytes,
      diagnostics.walBytes,
      correlationId: correlationId,
    );
    counter(
      TraceliteResqliteCounters.streamCount,
      diagnostics.streamLength,
      correlationId: correlationId,
    );
    counter(
      TraceliteResqliteCounters.readerBusy,
      diagnostics.readersBusyAtSnapshot ? 1 : 0,
      correlationId: correlationId,
    );
  }

  static void rss({
    required int beforeBytes,
    required int afterBytes,
    required int peakBytes,
    int? correlationId,
  }) {
    counter(
      TraceliteResqliteCounters.rssBeforeBytes,
      beforeBytes,
      correlationId: correlationId,
    );
    counter(
      TraceliteResqliteCounters.rssAfterBytes,
      afterBytes,
      correlationId: correlationId,
    );
    counter(
      TraceliteResqliteCounters.rssPeakBytes,
      peakBytes,
      correlationId: correlationId,
    );
  }

  static void profileCounters(Map<String, int> counters, {int? correlationId}) {
    for (final entry in counters.entries) {
      final counterId = _profileCounterIds[entry.key];
      if (counterId == null) continue;
      counter(counterId, entry.value, correlationId: correlationId);
    }
  }

  static void fanoutSample({
    required int writerUs,
    required int yieldUs,
    required int totalUs,
    required int invalidateUs,
    required int intersectionUs,
    required int intersectionEntries,
    int? correlationId,
  }) {
    counter(
      TraceliteResqliteCounters.fanoutWriterUs,
      writerUs,
      correlationId: correlationId,
    );
    counter(
      TraceliteResqliteCounters.fanoutYieldUs,
      yieldUs,
      correlationId: correlationId,
    );
    counter(
      TraceliteResqliteCounters.fanoutTotalUs,
      totalUs,
      correlationId: correlationId,
    );
    counter(
      TraceliteResqliteCounters.fanoutInvalidateUs,
      invalidateUs,
      correlationId: correlationId,
    );
    counter(
      TraceliteResqliteCounters.fanoutIntersectionUs,
      intersectionUs,
      correlationId: correlationId,
    );
    counter(
      TraceliteResqliteCounters.fanoutIntersectionEntries,
      intersectionEntries,
      correlationId: correlationId,
    );
  }

  static void detach() {
    final runtime = _runtime;
    if (runtime != null) {
      runtime.library.detachTrack(runtime.trackId);
    }
    _runtime = null;
    _attemptedAttach = false;
    _internedStrings.clear();
  }

  static _AttachedRuntime? get _attachedRuntime {
    if (!isEnabled) return null;
    if (_runtime case final runtime?) return runtime;
    if (_attemptedAttach) return null;
    _attemptedAttach = true;
    final region = Platform.environment['TRACELITE_REGION'];
    if (region == null || region.isEmpty) return null;

    final library = _Runtime.tryOpen();
    if (library == null) return null;

    final attachResult = _withNativeString(region, library.attach);
    if (attachResult != 0) return null;

    final processName = Platform.script.pathSegments.last;
    final threadName = Isolate.current.debugName ?? 'resqlite_isolate';
    final trackId = _withNativeString(
      processName,
      (processPtr) => _withNativeString(
        threadName,
        (threadPtr) =>
            library.registerProducer(_trackKindIsolate, processPtr, threadPtr),
      ),
    );
    if (trackId < 0) return null;

    final attached = _AttachedRuntime(library, trackId);
    _registerSpanNames(attached);
    return _runtime = attached;
  }

  static int _internString(_AttachedRuntime runtime, String value) {
    return _withNativeUtf8Bytes(
      value,
      (ptr, byteLength) => runtime.library.internString(ptr, byteLength),
    );
  }

  static void _registerSpanNames(_AttachedRuntime runtime) {
    final categoryId = _internString(runtime, 'resqlite');
    final counterCategoryId = _internString(runtime, 'resqlite.counter');
    for (final entry in _spanNames.entries) {
      final nameId = _internString(runtime, entry.value);
      final category = entry.key >= TraceliteResqliteCounters.rowsDecoded
          ? counterCategoryId
          : categoryId;
      _withArgs([entry.key, nameId, category], (ptr, count) {
        runtime.library.metadataOnTrack(
          runtime.trackId,
          _metadataKindAddSpan,
          ptr,
          count,
        );
      });
    }
  }
}

final class _AttachedRuntime {
  _AttachedRuntime(this.library, this.trackId);

  final _Runtime library;
  final int trackId;
}

final class _Runtime {
  _Runtime._(DynamicLibrary library)
      : attach =
            library.lookupFunction<_AttachNative, _AttachDart>('tlt_attach'),
        registerProducer = library
            .lookupFunction<_RegisterProducerNative, _RegisterProducerDart>(
          'tlt_register_producer',
        ),
        internString =
            library.lookupFunction<_InternStringNative, _InternStringDart>(
          'tlt_intern_string',
        ),
        beginOnTrack =
            library.lookupFunction<_RecordOnTrackNative, _RecordOnTrackDart>(
          'tlt_begin_on_track',
        ),
        endOnTrack =
            library.lookupFunction<_RecordOnTrackNative, _RecordOnTrackDart>(
          'tlt_end_on_track',
        ),
        beginCorrelatedOnTrack = library.lookupFunction<
            _RecordCorrelatedOnTrackNative,
            _RecordCorrelatedOnTrackDart>('tlt_begin_correlated_on_track'),
        endCorrelatedOnTrack = library.lookupFunction<
            _RecordCorrelatedOnTrackNative,
            _RecordCorrelatedOnTrackDart>('tlt_end_correlated_on_track'),
        asyncBeginOnTrack = library.lookupFunction<
            _RecordCorrelatedOnTrackNative,
            _RecordCorrelatedOnTrackDart>('tlt_async_begin_on_track'),
        asyncEndOnTrack = library.lookupFunction<_RecordCorrelatedOnTrackNative,
            _RecordCorrelatedOnTrackDart>('tlt_async_end_on_track'),
        counterOnTrack =
            library.lookupFunction<_CounterOnTrackNative, _CounterOnTrackDart>(
          'tlt_counter_on_track',
        ),
        counterCorrelatedOnTrack = library.lookupFunction<
            _CounterCorrelatedOnTrackNative,
            _CounterCorrelatedOnTrackDart>('tlt_counter_correlated_on_track'),
        metadataOnTrack =
            library.lookupFunction<_RecordOnTrackNative, _RecordOnTrackDart>(
          'tlt_metadata_on_track',
        ),
        detachTrack =
            library.lookupFunction<_DetachTrackNative, _DetachTrackDart>(
          'tlt_detach_track',
        );

  final _AttachDart attach;
  final _RegisterProducerDart registerProducer;
  final _InternStringDart internString;
  final _RecordOnTrackDart beginOnTrack;
  final _RecordOnTrackDart endOnTrack;
  final _RecordCorrelatedOnTrackDart beginCorrelatedOnTrack;
  final _RecordCorrelatedOnTrackDart endCorrelatedOnTrack;
  final _RecordCorrelatedOnTrackDart asyncBeginOnTrack;
  final _RecordCorrelatedOnTrackDart asyncEndOnTrack;
  final _CounterOnTrackDart counterOnTrack;
  final _CounterCorrelatedOnTrackDart counterCorrelatedOnTrack;
  final _RecordOnTrackDart metadataOnTrack;
  final _DetachTrackDart detachTrack;

  static _Runtime? tryOpen() {
    for (final candidate in _libraryCandidates()) {
      try {
        return _Runtime._(DynamicLibrary.open(candidate));
      } on Object {
        // Try the next candidate; tracing must stay best-effort.
      }
    }
    return null;
  }
}

List<String> _libraryCandidates() {
  final explicit = Platform.environment['TRACELITE_RUNTIME'];
  final names = switch (Platform.operatingSystem) {
    'macos' => const ['libtracelite_runtime.dylib'],
    'windows' => const ['tracelite_runtime.dll'],
    _ => const ['libtracelite_runtime.so'],
  };
  return [
    if (explicit != null && explicit.isNotEmpty) explicit,
    for (final name in names) name,
    for (final name in names) 'build/$name',
  ];
}

R _withNativeString<R>(String value, R Function(Pointer<Utf8>) body) {
  final ptr = value.toNativeUtf8();
  try {
    return body(ptr);
  } finally {
    calloc.free(ptr);
  }
}

R _withNativeUtf8Bytes<R>(
  String value,
  R Function(Pointer<Utf8>, int byteLength) body,
) {
  final ptr = value.toNativeUtf8();
  try {
    return body(ptr, utf8.encode(value).length);
  } finally {
    calloc.free(ptr);
  }
}

void _withArgs(List<int> args, void Function(Pointer<Uint64>, int) body) {
  if (args.isEmpty) {
    body(nullptr.cast<Uint64>(), 0);
    return;
  }

  final count = args.length > 255 ? 255 : args.length;
  final ptr = calloc<Uint64>(count);
  try {
    for (var i = 0; i < count; i++) {
      ptr[i] = args[i];
    }
    body(ptr, count);
  } finally {
    calloc.free(ptr);
  }
}
