# Luma native image core

`src/luma_native.cpp` implements bounded RGBA8 processing and a C ABI for worker-isolate use. It compiles tone, HSL and a registered CUBE preset to one cached 33-cubed transform; detail operators retain alpha. LibRaw 0.22.3 is built from the exact unmodified official source units listed by upstream `Makefile.am`.

Upstream source: https://www.libraw.org/data/LibRaw-0.22.3.tar.gz

Upstream archive SHA256: `789f3c33466210a1a0907f747a97c715d21bbf4af712f257fcbbd90111b227e4`.

LibRaw license choice: CDDL-1.0. See `src/libraw/COPYRIGHT`, `LICENSE.CDDL` and `LICENSE.LGPL` for the upstream alternative. This configuration has no external JPEG-lossy-DNG, LCMS, Jasper or OpenMP dependencies. It does not imply support for every camera/encoding. Image decoding, EXIF orientation, crop and encoding use Dart Image in the calling worker.

The C ABI rejects invalid dimensions, non-finite parameters and unsafe sizes. All buffer allocations have explicit owners. `luma_raw` buffers must be returned through `luma_free`. Calls and compiled caches are confined to their worker thread; caller buffers are not retained.

```sh
cmake -S src -B build -DLUMA_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
```
