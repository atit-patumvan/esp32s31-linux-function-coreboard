# ESP32-S31 XespV userspace SIMD library

XespV is intentionally isolated in `libesp-simd`; it is not enabled in the
global userspace `-march` and does not interpose on musl. Programs that do not
link this library cannot accidentally emit or execute PIE instructions.

The public header is `esp_simd.h`. It exposes 17 memory/string operations,
`esp_simd_eq_u8x16`, and `esp_simd_add_sat_u8`. The latter follows the
hardware `esp.vadd.u8` semantics: unsigned results saturate at 255 rather than
wrapping modulo 256. Raw assembly symbols remain hidden inside the shared
library.

## Hart binding

S31 revision v0.0 can execute XespV reliably on hart 1. A library constructor
calls `esp_simd_init()` before `main()` and pins the calling thread to CPU1.
Every public entry point repeats the initialization once per newly-created
thread; pthreads inherit the CPU1 affinity and confirm it on first use. If
affinity cannot be established, memory/string and arithmetic entry points use
their scalar libc/C fallback and do not execute XespV.

Callers must not broaden a thread's affinity after successful initialization.
`esp_simd_cpu()` and `esp_simd_active()` are available for diagnostics.

## Build and use

Buildroot package `BR2_PACKAGE_ESP_SIMD` installs:

```text
/usr/include/esp_simd.h
/usr/lib/libesp-simd.so.1
```

Link applications with `-lesp-simd`. The assembly object alone is built with
`_xesploop_xespv2p2 -mespv-spec=2p2`; ordinary Buildroot programs use
`_xesploop` without XespV.

Vector loads and stores operate only on aligned, complete 16-byte blocks.
Scalar code handles alignment, tails, terminators, mismatches, and overlapping
move edges. Composite copy functions reuse the same bounded primitives.

## Hardware validation

Run `/usr/sbin/s31-string-bench`. On S31 rev0.0 with Linux 6.18 it confirmed
CPU1 affinity and passed aligned/misaligned/tail/overlap tests for all 17
libc-style functions plus the compare and saturating-add APIs. Representative
256 KiB results were 35.64 MiB/s for XespV `memcpy` (1.07x libc), 50.33 MiB/s
for `memrchr` (1.47x), and 30.82 MiB/s for `memcmp` (1.38x). Some composite
copy routines remain slower than libc and are explicit APIs rather than libc
replacements.

The full ttyUSB0 record is
`logs/xesploop-xespv-simd-final-ttyUSB0-20260824.log`.
