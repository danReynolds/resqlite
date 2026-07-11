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

ffi.Pointer<ffi.Uint8> allocateReusableParamStructBuf(int byteCount) {
  if (byteCount > _maxReusableParamBufBytes) {
    // The parameter packer overwrites every struct field and payload byte that
    // native code reads before the buffer crosses FFI. Large arenas are
    // one-shot allocations, so zero-filling their untouched padding is wasted
    // work.
    return malloc<ffi.Uint8>(byteCount);
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
    malloc.free(buf);
  }
}
