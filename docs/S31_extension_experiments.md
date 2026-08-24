# ESP32-S31 ISA extension experiments

Last updated: 2026-08-24

## Hardware and toolchain baseline

- The local S31 hardware reference identifies the HP core ISA as
  `RV32IMAFBCNSUX`.
- ESP-IDF's current S31 RISC-V toolchain is GCC 15.2.0 plus binutils 2.45.
  The Linux/musl build pins the commits behind the matching
  `esp-15.2.0_20251204` releases.  S31's
  `soc_caps.h` and generated `sdkconfig` declare the Espressif extensions
  `xesploop` and `xespv`; Xespv machine code is assembled with
  `-mespv-spec=2p2`.  They do not declare `xespdsp`, Zcb, Zcmp, or Zcmt, so
  those extensions are intentionally not enabled for S31.
- Linux uses the soft-float `ilp32` ABI.  The `f` extension may still be used
  in userspace while keeping the syscall and libc ABI compatible with ilp32.
- `n`, `s`, and `u` describe privilege architecture rather than compiler code
  generation options.  They are implemented by the S31-specific OpenSBI and
  Linux privileged/trap paths, not appended to GCC's `-march` string.

## Board results

The test image was built from `rootfs/s31_ext_test.S` and
`rootfs/s31_ext_test.c` and run on ESP32-S31 revision v0.0, CPU1 under Linux
6.18. `libesp-simd` pins the process before `main()`. Each Xespv instruction
is isolated in a child process with a two-second
alarm so one illegal or non-terminating instruction cannot hide later results.
The dispatcher initializes q0..q7 before every case; indexed vector loads and
stores otherwise consume inherited q-register contents as unsafe offsets.

| Extension | Coverage | Result |
| --- | ---: | --- |
| RV32F | 27 instruction classes, including FCSR access | 27/27 pass |
| Xesploop | setupi, setup, starti, endi, counti, count; both loop slots | 6/6 pass |
| Xespv 2.2 | every non-HWLoop form in IDF `xesppie.S` | 353/354 pass |
| F/HWLoop/PIE context | signal delivery plus four fork workers, 200 yield iterations each | pass |

The one repeatable failure is case 270:

```text
esp.fft.cmul.s16.st.xp q0,q1,q2,x10,x9,0,0,0
opcode 0x2211087f
Linux result: SIGILL (signal 4)
```

The same assembler-generated opcode was temporarily executed on hart 1 in
bootloader M-mode after PIE was enabled.  Hart 1 did not reach OpenSBI and the
hart 0 watchdog/probe path restarted the system.  The probe was removed after
capture and the normal bootloader was rebuilt and flashed.  This establishes
that the failure is below Linux context management.  It does not distinguish
between an unimplemented instruction on revision v0.0 and an undocumented
hardware prerequisite.

The previous USB-UART noise bytes were deliberately excluded from this ISA
result because they are unrelated to instruction execution.

## Reproducible opcode generation

`rootfs/gen_s31_pie_cases.sh` reads the authoritative ESP-IDF decoder corpus:

```text
$IDF_PATH/components/esp_gdbstub/test_gdbstub_host/rv_decode/xesppie.S
```

It mechanically assigns safe scalar/vector operands, invokes
`riscv32-esp-elf-gcc`, verifies the object has the `xespv2p2` ELF attribute,
checks that exactly 354 four-byte instructions were emitted, and writes
`rootfs/s31_pie_cases.inc`.  The tested IDF source SHA256 is:

```text
649e5fc30c7de30326715c4ef91af6710bd8fe7c44bbb105e60622fe5257de79
```

Do not hand-edit the generated include. `make rootfs` regenerates it.

## Optimization policy

Ordinary S31 Linux userspace is configured for:

```text
rv32imafbc_zicsr_zifencei_zaamo_zalrsc_zba_zbb_zbc_zbs_xesploop
```

with `-mabi=ilp32`. Xesploop is therefore available to normal compiler output.
XespV is built only into `libesp-simd` and extension tests with
`_xespv2p2 -mespv-spec=2p2`; the library pins each using thread to CPU1 before
executing PIE code. Components must still obey their execution-context rules:

- Linux kernel C code must not emit floating-point or PIE instructions because
  kernel execution cannot borrow userspace coprocessor state arbitrarily.
- OpenSBI trap paths must preserve S-mode FPU, HWLoop and PIE state before any
  implementation code can use those resources.
- Normal userland may use F, compressed, bit-manipulation and Xesploop. XespV
  callers must use `libesp-simd`; the single failing FFT store form above is
  treated as an expected rev0.0 silicon exception and is not used by the
  library.

## Current image audit

The current tuple and versions are:

```text
riscv32-esp-linux-musl
GCC 15.2.0 (Espressif GCC commit 0dbf584943ac179894690b389f3a37926bb4cd33)
binutils 2.45 (Espressif binutils commit 99fe9ecb9fb65a69be65944eb1bbd7e42dfe0857)
musl 1.2.5, Linux UAPI headers 6.12, ilp32 ABI; running kernel 6.18
```

The 2026-08-24 build and physical-board run produced these artifact-level
results:

| Artifact | Effective policy / result |
| --- | --- |
| Linux `vmlinux` | 6.18 SMP, `CONFIG_ESP32S31_COPROC_CONTEXT=y` |
| Buildroot BusyBox | ELF includes Xesploop 1.0 and excludes XespV |
| two-thread CoreMark | ELF includes Xesploop; 15 `esp.lp` sites; 1941.23 iterations/s, CRC valid |
| `libesp-simd.so.1` | ELF includes Xesploop 1.0 and XespV 2.2; only `esp_simd_*` APIs exported |
| `s31-ext-test` | Xesploop 6/6; XespV 353/354 plus one expected rev0.0 exception; context pass |

The XZ squashfs is 2,412,544 bytes in a 4 MiB rootfs partition. The complete
boot, instruction, context and CoreMark record is
`logs/xesploop-xespv-simd-final-ttyUSB0-20260824.log`.
