/// FNV-1a hash for result change detection.
///
/// Used by both the read worker (hashing raw flat values on the worker isolate)
/// and the stream engine (hashing via Row.values on main). Both must produce
/// identical hashes for the same data — this shared module ensures one source
/// of truth.

/// FNV-1a 64-bit combine step.
@pragma('vm:prefer-inline')
int fnvCombine(int hash, int value) {
  hash ^= value;
  hash = (hash * 0x100000001B3) & 0x7FFFFFFFFFFFFFFF;
  return hash;
}

/// FNV-1a offset basis (64-bit, masked to positive Dart int).
const int fnvOffsetBasis = 0xcbf29ce484222325 & 0x7FFFFFFFFFFFFFFF;

/// Hash a list of values using FNV-1a. Used for result change detection.
int hashValues(int rowCount, List<Object?> values) {
  if (rowCount == 0) return 0;
  var hash = fnvOffsetBasis;
  hash = fnvCombine(hash, rowCount);
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    hash = fnvCombine(hash, v == null ? 0 : v.hashCode);
  }
  return hash;
}
