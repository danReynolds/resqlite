import 'dart:io';

Future<void> main() async {
  final packageRoot = Directory.current.absolute.path;
  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite_trace_sqlite_smoke_',
  );

  try {
    final runtimePath = await _buildFakeTraceliteRuntime(tempDir);
    final traceLogPath = '${tempDir.path}/active-trace.log';

    await Directory('${tempDir.path}/bin').create(recursive: true);
    await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: resqlite_trace_sqlite_smoke
publish_to: none

environment:
  sdk: ^3.10.4

dependencies:
  resqlite:
    path: $packageRoot

hooks:
  user_defines:
    resqlite:
      trace_sqlite: true
      tracelite_root: $packageRoot/test/fixtures/tracelite_root
''');
    await File('${tempDir.path}/bin/main.dart').writeAsString('''
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/tracelite_profile.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_trace_sqlite_');
  try {
    final db = await Database.open('\${dir.path}/test.db');
    await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT)');

    final emissions = <List<Map<String, Object?>>>[];
    final sub = db.stream('SELECT name FROM t ORDER BY id').listen(
      emissions.add,
    );
    await _waitFor(() => emissions.isNotEmpty, 'initial stream emission');

    await db.execute('INSERT INTO t(name) VALUES (?)', ['trace']);
    await _waitFor(() => emissions.length >= 2, 'stream invalidation');

    await db.transaction((tx) async {
      await tx.execute('INSERT INTO t(name) VALUES (?)', ['tx']);
      await tx.select('SELECT COUNT(*) AS c FROM t');
      await tx.executeBatch('INSERT INTO t(name) VALUES (?)', [
        ['batch'],
      ]);
    });
    await _waitFor(() => emissions.length >= 3, 'transaction invalidation');

    final rows = await db.select('SELECT name FROM t ORDER BY id');
    if (rows.length != 3 || rows.first['name'] != 'trace') {
      throw StateError('unexpected rows: \$rows');
    }
    await sub.cancel();
    await db.close();
    TraceliteProfile.detach();
  } finally {
    await dir.delete(recursive: true);
  }
}

Future<void> _waitFor(bool Function() predicate, String label) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('timed out waiting for \$label');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
''');

    await _run('pub get', tempDir.path, ['pub', 'get']);
    await _run('run smoke', tempDir.path, [
      'run',
      '-DRESQLITE_PROFILE=true',
      '-DRESQLITE_TRACELITE=true',
      'bin/main.dart',
    ], environment: {
      'TRACELITE_REGION': traceLogPath,
      'TRACELITE_RUNTIME': runtimePath,
    });

    final traceLog = await File(traceLogPath).readAsString();
    _expectTrace(traceLog, 'attach');
    _expectTrace(traceLog, 'async_begin 16386'); // databaseExecute
    _expectTrace(traceLog, 'async_begin 16388'); // databaseTransaction
    _expectTrace(traceLog, 'begin_correlated 16400'); // writerHandle
    _expectTrace(traceLog, 'begin_correlated 16401'); // readerHandle
    _expectTrace(traceLog, 'async_begin 16402'); // readerPoolDispatch
    _expectTrace(traceLog, 'begin_correlated 16416'); // streamInvalidate
    _expectTrace(traceLog, 'counter_correlated 16656'); // invalidateUs
  } finally {
    await tempDir.delete(recursive: true);
  }
}

Future<String> _buildFakeTraceliteRuntime(Directory tempDir) async {
  if (Platform.isWindows) {
    throw UnsupportedError(
      'trace_sqlite_smoke active trace runtime is not wired for Windows',
    );
  }

  final source = File('${tempDir.path}/fake_tracelite_runtime.c');
  await source.writeAsString(r'''
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static char g_region_path[4096];
static uint32_t g_next_string_id = 1;

static void append_line(const char* line) {
  if (g_region_path[0] == '\0') return;
  FILE* file = fopen(g_region_path, "a");
  if (file == NULL) return;
  fputs(line, file);
  fputc('\n', file);
  fclose(file);
}

static void append_event(const char* kind, uint16_t span, uint64_t correlation, int64_t value) {
  if (g_region_path[0] == '\0') return;
  FILE* file = fopen(g_region_path, "a");
  if (file == NULL) return;
  if (correlation == 0) {
    fprintf(file, "%s %u %lld\n", kind, (unsigned)span, (long long)value);
  } else {
    fprintf(file, "%s %u %llu %lld\n", kind, (unsigned)span, (unsigned long long)correlation, (long long)value);
  }
  fclose(file);
}

int32_t tlt_attach(const char* region_path) {
  strncpy(g_region_path, region_path, sizeof(g_region_path) - 1);
  g_region_path[sizeof(g_region_path) - 1] = '\0';
  append_line("attach");
  return 0;
}

int32_t tlt_register_producer(uint8_t kind, const char* process, const char* thread) {
  (void)process;
  (void)thread;
  append_event("producer", kind, 0, 0);
  return 1;
}

uint32_t tlt_intern_string(const char* value, uint32_t byte_length) {
  if (g_region_path[0] != '\0') {
    FILE* file = fopen(g_region_path, "a");
    if (file != NULL) {
      fprintf(file, "intern %.*s\n", (int)byte_length, value);
      fclose(file);
    }
  }
  return g_next_string_id++;
}

void tlt_begin_on_track(uint8_t track, uint16_t span, uint64_t* args, uint8_t count) {
  (void)track;
  (void)args;
  append_event("begin", span, 0, count);
}

void tlt_end_on_track(uint8_t track, uint16_t span, uint64_t* args, uint8_t count) {
  (void)track;
  (void)args;
  append_event("end", span, 0, count);
}

void tlt_begin_correlated_on_track(uint8_t track, uint16_t span, uint64_t correlation, uint64_t* args, uint8_t count) {
  (void)track;
  (void)args;
  append_event("begin_correlated", span, correlation, count);
}

void tlt_end_correlated_on_track(uint8_t track, uint16_t span, uint64_t correlation, uint64_t* args, uint8_t count) {
  (void)track;
  (void)args;
  append_event("end_correlated", span, correlation, count);
}

void tlt_async_begin_on_track(uint8_t track, uint16_t span, uint64_t correlation, uint64_t* args, uint8_t count) {
  (void)track;
  (void)args;
  append_event("async_begin", span, correlation, count);
}

void tlt_async_end_on_track(uint8_t track, uint16_t span, uint64_t correlation, uint64_t* args, uint8_t count) {
  (void)track;
  (void)args;
  append_event("async_end", span, correlation, count);
}

void tlt_counter_on_track(uint8_t track, uint16_t counter, int64_t value) {
  (void)track;
  append_event("counter", counter, 0, value);
}

void tlt_counter_correlated_on_track(uint8_t track, uint16_t counter, uint64_t correlation, int64_t value) {
  (void)track;
  append_event("counter_correlated", counter, correlation, value);
}

void tlt_metadata_on_track(uint8_t track, uint16_t kind, uint64_t* args, uint8_t count) {
  (void)track;
  (void)args;
  append_event("metadata", kind, 0, count);
}

void tlt_detach_track(uint8_t track) {
  append_event("detach", track, 0, 0);
}
''');

  final ext = Platform.isMacOS ? 'dylib' : 'so';
  final runtimePath = '${tempDir.path}/libfake_tracelite_runtime.$ext';
  final args = Platform.isMacOS
      ? ['-dynamiclib', '-O2', source.path, '-o', runtimePath]
      : ['-shared', '-fPIC', '-O2', source.path, '-o', runtimePath];
  await _run(
    'compile fake tracelite runtime',
    tempDir.path,
    args,
    executable: 'cc',
  );
  return runtimePath;
}

Future<void> _run(
  String label,
  String workingDirectory,
  List<String> args, {
  String? executable,
  Map<String, String> environment = const {},
}) async {
  final command = executable ?? Platform.resolvedExecutable;
  final result = await Process.run(
    command,
    args,
    workingDirectory: workingDirectory,
    environment: {...Platform.environment, ...environment},
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(
      command,
      args,
      '$label failed with exit code ${result.exitCode}',
      result.exitCode,
    );
  }
}

void _expectTrace(String traceLog, String needle) {
  if (!traceLog.contains(needle)) {
    throw StateError(
      'active tracelite smoke did not record "$needle". Trace log:\n$traceLog',
    );
  }
}
