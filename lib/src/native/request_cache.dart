import 'dart:collection';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

const _sqlCacheMax = 32;
const _maxReusableParamBufBytes = 64 * 1024;

final Map<String, ffi.Pointer<Utf8>> _sqlUtf8Cache =
    LinkedHashMap<String, ffi.Pointer<Utf8>>();

ffi.Pointer<Utf8> cachedSqlUtf8(String sql) {
  final cached = _sqlUtf8Cache.remove(sql);
  if (cached != null) {
    _sqlUtf8Cache[sql] = cached;
    return cached;
  }

  final native = sql.toNativeUtf8();
  _sqlUtf8Cache[sql] = native;
  if (_sqlUtf8Cache.length > _sqlCacheMax) {
    final oldestKey = _sqlUtf8Cache.keys.first;
    final evicted = _sqlUtf8Cache.remove(oldestKey);
    if (evicted != null) calloc.free(evicted);
  }
  return native;
}

ffi.Pointer<ffi.Uint8> _reusableParamStructBuf = ffi.nullptr;
int _reusableParamStructBufBytes = 0;

/// When [owned] is set the caller takes ownership of a fresh allocation
/// instead of borrowing this isolate's shared scratch buffer. The scratch
/// buffer is isolate-local, so a buffer that will be freed by a *different*
/// isolate must be owned — otherwise the freeing isolate compares it against
/// its own scratch pointer, misses, and frees memory this isolate still holds.
ffi.Pointer<ffi.Uint8> allocateReusableParamStructBuf(
  int byteCount, {
  bool owned = false,
}) {
  if (owned || byteCount > _maxReusableParamBufBytes) {
    return calloc<ffi.Uint8>(byteCount);
  }
  if (_reusableParamStructBuf == ffi.nullptr ||
      byteCount > _reusableParamStructBufBytes) {
    if (_reusableParamStructBuf != ffi.nullptr) {
      calloc.free(_reusableParamStructBuf);
    }
    _reusableParamStructBuf = calloc<ffi.Uint8>(byteCount);
    _reusableParamStructBufBytes = byteCount;
  }
  return _reusableParamStructBuf;
}

void freeReusableParamStructBuf(ffi.Pointer<ffi.Uint8> buf) {
  if (buf.address != _reusableParamStructBuf.address) {
    calloc.free(buf);
  }
}
