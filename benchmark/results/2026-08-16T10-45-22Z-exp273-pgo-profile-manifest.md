# Exp 273 PGO profile manifest

This manifest identifies the frozen counter-only profile used for Exp 273's
candidate binaries. The profile itself is preserved only on
`archive/exp-273`; the publication branch intentionally does not ship it.

## Identity

- Source: `02592093e6b671e420a1de7b277d7c56c434627a` (`origin/main` at claim)
- Host: macOS 26.2 arm64
- Compiler: Apple clang 21.0.0 (`clang-2100.1.1.101`), Xcode 26.6
- Profiler: Apple LLVM `llvm-profdata` 21.0.0
- Dart: 3.12.2 stable, macOS arm64
- Indexed profile: `exp273-arm64-representative.profdata`
- Profile bytes: 522,568
- Profile SHA-256: `cd957c73e38b10dc04106bdd2bf056687bb0bd856209943146eca6596fd25d74`
- Profile summary: IR instrumentation, 2,406 functions, 31,934 blocks,
  2,556,436,455 total counter events

## Compile contract

Generation added these flags to the normal release native-asset build:

```text
-fprofile-generate=<profile-directory>
-fprofile-continuous
-fprofile-update=atomic
-mllvm -disable-vp
-mllvm -static-func-full-module-prefix=false
-DRESQLITE_PGO
```

Use replaced the generation flags with:

```text
-fprofile-use=<indexed-profile>
-mllvm -disable-vp
-mllvm -static-func-full-module-prefix=false
-Werror=profile-instr-out-of-date
-Werror=profile-instr-unprofiled
-Werror=backend-plugin
-DRESQLITE_PGO
```

`RESQLITE_PGO` suppresses manual `hot` attributes so measured counts own
hotness. Both hidden LLVM controls are part of the tested compatibility
contract. The static-function prefix control removes absolute checkout paths
from profile keys; `llvm-profdata show --all-functions` then reports names such
as `resqlite_json.c;b64_neon_bulk` instead of worktree-qualified names.

## Representative inputs

All inputs were fresh AOT bundles built with atomic continuous counters. They
used `LLVM_PROFILE_FILE=<lane>-%p-%m%c.profraw` and were merged without sparse
mode.

| Input | Workload | Counter events | SHA-256 |
|---|---|---:|---|
| release | Resqlite-only release scenarios through shared write shapes | 2,292,291,187 | `a9fe0396e2de16aa58c2b9e7fdd83e3cf6d287a7180fb9eb895403d97bd364c3` |
| stream | `stream_rerun_latency.dart` | 244,612,184 | `9e084e5c34991176defa0726ee1031f1302dad5cefa5dd41aaf4a1737e0b6163` |
| transaction | `tx_body_write_coalescing.dart` | 19,533,084 | `5bae87361c72e222b0d2c0cfd0e682a9fe8b498851ab2cdca77de4a430d15d14` |

Merge and inspection commands:

```sh
xcrun llvm-profdata merge -failure-mode=all \
  -output=exp273-arm64-representative.profdata profiles/*.profraw
xcrun llvm-profdata show --counts exp273-arm64-representative.profdata
xcrun llvm-profdata show --all-functions exp273-arm64-representative.profdata
```

The strict PGO-use AOT build completed without warnings. A naive continuous
profile without `-disable-vp` produced 184 value-site mismatch warnings because
Darwin continuous mode does not collect value profiles.
