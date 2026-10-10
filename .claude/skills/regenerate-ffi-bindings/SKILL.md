---
name: regenerate-ffi-bindings
description: Regenerate the Dart bindings of the native module after changing native/stitcher/include/sary_stitcher.h (new field, new function, new return code), and check that the interface stays FFI-compatible.
---

# Regenerate the FFI bindings

1. Edit `native/stitcher/include/sary_stitcher.h` within ffigen's constraints:
   - no `enum` in the interface (its size depends on the compiler): return
     codes as `#define SARY_*` and functions returning `int32_t`;
   - no `volatile` pointers in structs (ffigen then drops **all** the struct's
     fields): declare `float *` / `int32_t *` and apply `volatile` on the C++
     side (`static_cast<volatile float*>`);
   - fixed-size types (`int32_t`, `float`); strings as UTF-8 `const char *`.
2. Update `native/stitcher/src/sary_stitcher.cpp` and, when a
   `SaryStitchParams` field is added, `native/stitcher/tools/stitch_cli.cpp`
   (initialized with `SaryStitchParams params{}`).
3. Generate (libclang ships with Xcode on macOS):
   ```bash
   dart run ffigen --config ffigen.yaml
   ```
   Read the output: no `[WARNING]` nor `[SEVERE]` line may appear. Result:
   `lib/data/native/sary_stitcher_bindings.g.dart` (never edit it by hand).
4. Fill the new field in `SaryStitchParams.$allocate(...)` in
   `lib/data/services/stitching_service.dart` (`_stitchInIsolate`).
5. Check:
   ```bash
   flutter analyze
   flutter build apk --debug
   ```
