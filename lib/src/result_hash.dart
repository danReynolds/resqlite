/// FNV-1a hash for result change detection.
///
/// Used by both the read worker (hashing raw flat values on the worker isolate)
/// and the stream engine (hashing via Row.values on main). Both must produce
/// identical hashes for the same data — this shared module ensures one source
/// of truth.
///
/// **Important:** uses [stableValueHash] for individual values instead of
/// `Object.hashCode`. This matters for `Uint8List` (blobs) whose default
/// `hashCode` is identity-based — two lists with identical bytes would
/// produce different hashes, defeating change detection.

import 'dart:typed_data';

/// FNV-1a 64-bit combine step.
@pragma('vm:prefer-inline')
int fnvCombine(int hash, int value) {
  hash ^= value;
  hash = (hash * 0x100000001B3) & 0x7FFFFFFFFFFFFFFF;
  return hash;
}

/// FNV-1a offset basis (64-bit, masked to positive Dart int).
const int fnvOffsetBasis = 0xcbf29ce484222325 & 0x7FFFFFFFFFFFFFFF;

/// Content-based hash for a single query result value.
///
/// `int`, `double`, `String`, and `null` use their built-in `hashCode`
/// (which is deterministic and content-based in Dart). `Uint8List` gets
/// a byte-content FNV-1a hash since its default `hashCode` is identity-
/// based and would differ across isolates and invocations even for
/// identical data.
@pragma('vm:prefer-inline')
int stableValueHash(Object? v) {
  if (v == null) return 0;
  if (v is Uint8List) {
    var h = fnvOffsetBasis;
    for (var i = 0; i < v.length; i++) {
      h = fnvCombine(h, v[i]);
    }
    return h;
  }
  return v.hashCode;
}

/// Hash a list of values using FNV-1a. Used for result change detection.
int hashValues(int rowCount, List<Object?> values) {
  if (rowCount == 0) return 0;
  var hash = fnvOffsetBasis;
  hash = fnvCombine(hash, rowCount);
  for (var i = 0; i < values.length; i++) {
    hash = fnvCombine(hash, stableValueHash(values[i]));
  }
  return hash;
}
