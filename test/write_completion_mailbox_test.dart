@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';
import 'package:test/test.dart';

void main() {
  test('write completion mailbox publishes and resets atomically', () {
    final mailbox = calloc<ffi.Uint8>(resqliteWriteCompletionSize());
    final affectedRows = calloc<ffi.Int>();
    final lastInsertId = calloc<ffi.Int64>();
    final writerSqliteUs = calloc<ffi.Int64>();
    try {
      affectedRows.value = -1;
      lastInsertId.value = -1;
      writerSqliteUs.value = -1;
      resqliteWriteCompletionInit(mailbox.cast());

      expect(
        resqliteWriteCompletionTryRead(
          mailbox.cast(),
          affectedRows,
          lastInsertId,
          writerSqliteUs,
        ),
        0,
      );
      expect(affectedRows.value, -1);
      expect(lastInsertId.value, -1);
      expect(writerSqliteUs.value, -1);

      resqliteWriteCompletionPublish(mailbox.cast(), 7, 0x100000002, 987654);
      expect(
        resqliteWriteCompletionTryRead(
          mailbox.cast(),
          affectedRows,
          lastInsertId,
          writerSqliteUs,
        ),
        1,
      );
      expect(affectedRows.value, 7);
      expect(lastInsertId.value, 0x100000002);
      expect(writerSqliteUs.value, 987654);

      resqliteWriteCompletionReset(mailbox.cast());
      expect(
        resqliteWriteCompletionTryRead(
          mailbox.cast(),
          affectedRows,
          lastInsertId,
          writerSqliteUs,
        ),
        0,
      );
    } finally {
      calloc.free(writerSqliteUs);
      calloc.free(lastInsertId);
      calloc.free(affectedRows);
      calloc.free(mailbox);
    }
  });

  test(
    'release/acquire publication never exposes a mixed generation',
    () async {
      const iterations = 50000;
      final mailbox = calloc<ffi.Uint8>(resqliteWriteCompletionSize());
      final affectedRows = calloc<ffi.Int>();
      final lastInsertId = calloc<ffi.Int64>();
      final writerSqliteUs = calloc<ffi.Int64>();
      final done = ReceivePort();
      final producerExit = ReceivePort();
      Isolate? producer;
      try {
        resqliteWriteCompletionInit(mailbox.cast());
        producer = await Isolate.spawn(_publishGenerations, <Object>[
          mailbox.address,
          iterations,
          done.sendPort,
        ], onExit: producerExit.sendPort);
        final waitClock = Stopwatch()..start();

        for (var generation = 1; generation <= iterations; generation++) {
          while (resqliteWriteCompletionTryRead(
                mailbox.cast(),
                affectedRows,
                lastInsertId,
                writerSqliteUs,
              ) ==
              0) {
            if (waitClock.elapsed > const Duration(seconds: 10)) {
              throw StateError(
                'Producer stopped before publishing generation $generation.',
              );
            }
          }

          final payload = generation * 1000003;
          if (affectedRows.value != generation ||
              lastInsertId.value != payload ||
              writerSqliteUs.value != (payload ^ 0x5a5a5a5a)) {
            throw StateError(
              'Mixed mailbox generation $generation: '
              'affected=${affectedRows.value}, '
              'lastId=${lastInsertId.value}, '
              'sqliteUs=${writerSqliteUs.value}.',
            );
          }
          resqliteWriteCompletionReset(mailbox.cast());
        }
        expect(await done.first.timeout(const Duration(seconds: 10)), true);
      } finally {
        producer?.kill(priority: Isolate.immediate);
        if (producer != null) {
          await producerExit.first.timeout(
            const Duration(seconds: 2),
            onTimeout: () => null,
          );
        }
        producerExit.close();
        done.close();
        calloc.free(writerSqliteUs);
        calloc.free(lastInsertId);
        calloc.free(affectedRows);
        calloc.free(mailbox);
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

void _publishGenerations(List<Object> arguments) {
  final mailbox = ffi.Pointer<ffi.Void>.fromAddress(arguments[0] as int);
  final iterations = arguments[1] as int;
  final done = arguments[2] as SendPort;
  final nullInt = ffi.nullptr.cast<ffi.Int>();
  final nullInt64 = ffi.nullptr.cast<ffi.Int64>();

  for (var generation = 1; generation <= iterations; generation++) {
    while (resqliteWriteCompletionTryRead(
          mailbox,
          nullInt,
          nullInt64,
          nullInt64,
        ) !=
        0) {}
    final payload = generation * 1000003;
    resqliteWriteCompletionPublish(
      mailbox,
      generation,
      payload,
      payload ^ 0x5a5a5a5a,
    );
  }
  done.send(true);
}
