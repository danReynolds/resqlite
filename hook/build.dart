// resqlite native build hook.
//
// This script runs automatically during `dart run` or `flutter build`, before
// any Dart code compiles. It compiles our C sources (SQLite amalgamation +
// resqlite.c) into a shared library (libresqlite.dylib/so/dll) and registers
// it as a native asset.
//
// How the pieces connect:
//
//   1. This hook compiles C → shared library, registered under the asset name
//      'src/native/resqlite_bindings.dart'.
//
//   2. In Dart, @ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
//      tells FFI to load the library registered under that same name.
//
//   3. The Dart toolchain matches them — FFI calls in Dart resolve to the
//      compiled C functions in the shared library.
//
// Platform-specific handling:
//   - Linux: version script + -Bsymbolic to prevent symbol conflicts with
//     system SQLite (loaded via Flutter's libgtk dependency).
//   - Android: links libm for math functions.
//   - iOS/macOS: @rpath dylib naming for proper framework loading.
//   - Windows: no special flags — sqlite3_mutex replaces pthread for
//     cross-platform threading.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final packageRoot = input.packageRoot.path;
    final targetOS = input.config.code.targetOS;

    // -----------------------------------------------------------------------
    // Linux: generate a linker version script to control symbol exports.
    //
    // On Linux, Flutter's libgtk dependency dynamically links against the
    // system SQLite. Without this script, our SQLite symbols can be resolved
    // against the system library instead of ours, causing crashes.
    //
    // The version script exports only the symbols we use and hides everything
    // else. Combined with -Bsymbolic, this prevents cross-library symbol
    // resolution issues.
    //
    // See: https://github.com/dart-lang/native/issues/2724
    // -----------------------------------------------------------------------
    String? linkerScript;
    if (targetOS == OS.linux) {
      linkerScript = input.outputDirectory.resolve('resqlite.map').path;
      await File(linkerScript).writeAsString('''
{
  global:
${_exportedSymbols.map((s) => '    $s;').join('\n')}
  local:
    *;
};
''');
    }

    final library = CBuilder.library(
      name: 'resqlite',
      packageName: 'resqlite',
      assetName: 'src/native/resqlite_bindings.dart',
      sources: [
        // sqlite3mc: SQLite with Multiple Ciphers — drop-in replacement
        // for plain SQLite that adds encryption support. Zero runtime
        // overhead when no encryption key is set.
        p.join(packageRoot, 'third_party', 'sqlite3mc', 'sqlite3mc_amalgamation.c'),
        p.join(packageRoot, 'native', 'resqlite.c'),
      ],
      includes: [
        p.join(packageRoot, 'third_party', 'sqlite3mc'),
        p.join(packageRoot, 'native'),
      ],
      defines: {
        // -----------------------------------------------------------------
        // SQLite compile options
        // -----------------------------------------------------------------

        // Performance: disable unused features, enable useful ones.
        'SQLITE_DQS': '0',
        'SQLITE_DEFAULT_MEMSTATUS': '0',
        'SQLITE_DEFAULT_LOOKASIDE': '1200,128',
        'SQLITE_DEFAULT_PCACHE_INITSZ': '128',
        'SQLITE_TEMP_STORE': '2',
        'SQLITE_MAX_EXPR_DEPTH': '0',
        'SQLITE_USE_ALLOCA': null,
        'SQLITE_LIKE_DOESNT_MATCH_BLOBS': null,

        // WAL mode defaults: readers get synchronous=NORMAL automatically
        // without a PRAGMA call. Safe in WAL mode (committed txns survive
        // power loss; only uncommitted data is at risk).
        'SQLITE_DEFAULT_WAL_SYNCHRONOUS': '1',


        // Platform hints for sqlite3mc — tell SQLite which C library
        // functions are available. Required for correct operation.
        'SQLITE_HAVE_ISNAN': null,
        'SQLITE_HAVE_LOCALTIME_R': null,
        'SQLITE_HAVE_LOCALTIME_S': null,
        'SQLITE_HAVE_MALLOC_USABLE_SIZE': null,
        'SQLITE_HAVE_STRCHRNUL': null,
        'SQLITE_UNTESTABLE': null,

        // Threading: multi-thread mode (we manage our own locking via
        // sqlite3_mutex). This is the minimum required for our architecture
        // where multiple Dart isolates call into the same C connection pool.
        'SQLITE_THREADSAFE': '2',

        // Features we use.
        'SQLITE_ENABLE_BATCH_ATOMIC_WRITE': null, // F2FS (Android 9+): eliminates journal I/O for 2-3x write speedup
        'SQLITE_ENABLE_FTS5': null,
        'SQLITE_ENABLE_MATH_FUNCTIONS': null,
        'SQLITE_ENABLE_PREUPDATE_HOOK': null,
        'SQLITE_ENABLE_STAT4': null,

        // Features we don't use — strip from binary.
        'SQLITE_OMIT_AUTOINIT': null, // we call sqlite3_initialize() once in resqlite_open
        'SQLITE_OMIT_COMPLETE': null,
        'SQLITE_OMIT_DECLTYPE': null,
        'SQLITE_OMIT_DEPRECATED': null,
        'SQLITE_OMIT_GET_TABLE': null,
        'SQLITE_OMIT_PROGRESS_CALLBACK': null,
        'SQLITE_OMIT_SHARED_CACHE': null,
        'SQLITE_OMIT_TCL_VARIABLE': null,
        'SQLITE_OMIT_TRACE': null,
        'SQLITE_OMIT_UTF16': null, // we only use UTF-8 via FFI
      },
      flags: [
        // ---------------------------------------------------------------
        // Linux: prevent symbol conflicts with system SQLite.
        // ---------------------------------------------------------------
        if (targetOS == OS.linux) ...[
          '-Wl,-Bsymbolic',
          '-Wl,--version-script=$linkerScript',
          // Strip unused code sections for smaller binary.
          '-ffunction-sections',
          '-fdata-sections',
          '-Wl,--gc-sections',
        ],

        // ---------------------------------------------------------------
        // iOS / macOS: dylib configuration.
        // ---------------------------------------------------------------
        if (targetOS case OS.iOS || OS.macOS) ...[
          '-headerpad_max_install_names',
          '-install_name',
          '@rpath/libresqlite.dylib',
        ],
      ],
      libraries: [
        // ---------------------------------------------------------------
        // Android: SQLite uses math functions (ceil, floor, etc.) which
        // require linking against libm on Android's Bionic libc.
        // ---------------------------------------------------------------
        if (targetOS == OS.android) 'm',
      ],
    );

    await library.run(input: input, output: output);
  });
}

// ---------------------------------------------------------------------------
// Exported symbols for the Linux linker version script.
//
// These are all the SQLite and resqlite symbols referenced via FFI from Dart.
// Everything else is hidden (local) to prevent conflicts with system SQLite.
// ---------------------------------------------------------------------------
const _exportedSymbols = [
  // SQLite core (used by database.dart FFI bindings)
  'sqlite3_open_v2',
  'sqlite3_close_v2',
  'sqlite3_errmsg',
  'sqlite3_exec',
  'sqlite3_prepare_v2',
  'sqlite3_step',
  'sqlite3_reset',
  'sqlite3_finalize',
  'sqlite3_column_count',
  'sqlite3_column_name',
  'sqlite3_column_type',
  'sqlite3_column_int64',
  'sqlite3_column_double',
  'sqlite3_column_text',
  'sqlite3_column_blob',
  'sqlite3_column_bytes',
  'sqlite3_bind_int64',
  'sqlite3_bind_double',
  'sqlite3_bind_text',
  'sqlite3_bind_blob64',
  'sqlite3_bind_null',
  'sqlite3_bind_parameter_count',
  'sqlite3_changes',
  'sqlite3_last_insert_rowid',
  'sqlite3_sleep',
  // SQLite mutex (used by resqlite.c for cross-platform threading)
  'sqlite3_mutex_alloc',
  'sqlite3_mutex_enter',
  'sqlite3_mutex_leave',
  'sqlite3_mutex_free',
  // SQLite hooks (used for stream invalidation + dependency tracking)
  'sqlite3_preupdate_hook',
  'sqlite3_set_authorizer',
  // resqlite custom functions
  'resqlite_open',
  'resqlite_close',
  'resqlite_errmsg',
  'resqlite_exec',
  'resqlite_execute',
  'resqlite_run_batch',
  'resqlite_run_batch_nested',
  'resqlite_get_dirty_tables',
  'resqlite_get_read_tables',
  'resqlite_db_status_total',
  'resqlite_writer_handle',
  'resqlite_stmt_acquire',
  'resqlite_stmt_acquire_on',
  'resqlite_stmt_acquire_writer',
  'resqlite_stmt_release',
  'resqlite_query_bytes',
  'resqlite_step_row',
  'resqlite_free',
];
