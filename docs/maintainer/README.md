# Function-CoreBoard Maintainer Handbook

This directory is the handoff reference for rebuilding and maintaining the
ESP32-S31 Function-CoreBoard Linux image. Start here when using a new Mac or
Linux computer.

## Documents

1. [Reproducible build](reproducible-build.md) — source pins, Linux packages,
   ESP-IDF, toolchain, Apple-silicon Docker, variants, and artifact checks.
2. [Feature build selector](feature-build-selector.md) — interactive profiles,
   scripted flags, automatic clean behavior, and selection manifests.
3. [Storage and flashing](storage-and-flashing.md) — authoritative flash map,
   SquashFS/JFFS2 overlay, backups, safe partial flashing, reset, and recovery.
4. [Network services](network-services.md) — Ethernet, DHCP/static IPv4,
   Wi-Fi, DNS, NTP, HTTPS tools, routing, implementation files, and diagnosis.
5. [SSH and access](ssh-and-access.md) — login keys, persistent Dropbear host
   keys, fingerprints, permissions, recovery, and security boundaries.
6. [Radio, BLE, USB, and gateway](radio-ble-usb-gateway.md) — native radio build
   flow, build variants, BLE/USB checks, and the intended BLE-to-cloud design.
7. [Rootfs maintenance](rootfs-maintenance.md) — Buildroot packages, the 4 MiB
   budget, curl/CA profile, nano terminfo fix, adding tools, and size recovery.
8. [Known-good baseline](known-good-baseline.md) — the exact August 2026 source
   identities, image hash, observed board state, and acceptance results.

The shorter operator checklist remains in
[Function-CoreBoard Build and Test Guide](../function-coreboard-test.md).

## Rules that prevent data loss

- Back up raw `persist` before changing the layout or doing a full erase.
- Routine updates use segmented `flash-all` or rootfs-only flashing.
- Never flash a merged full-flash image when existing persistent data matters.
- Keep every image inside the size checked by `make layout-check` and the
  rootfs size check.
- Never publish `/etc/s31-conf/wifi.conf`, private SSH keys, or a raw persist
  backup.
- Record `git rev-parse HEAD`, `git submodule status`, toolchain tag, ESP-IDF
  commit, image size, and SHA-256 for every known-good build.

## Authoritative source map

| Concern | Source of truth |
|---|---|
| Raw flash offsets | `configs/esp32s31-layout.cfg` |
| Linux MTD partitions | `linux-esp32-s31/arch/riscv/boot/dts/espressif/esp32s31.dtsi` |
| Kernel options selected per build | root `Makefile` plus kernel defconfig |
| Rootfs packages | `buildroot-external/configs/esp32s31_rootfs_defconfig` |
| Root overlay and `/persist` | `buildroot-external/board/esp32-s31/overlay/init` |
| Ethernet userspace setup | overlay `etc/network/interfaces` |
| Wi-Fi lifecycle | overlay `usr/sbin/s31-wifi` and `etc/init.d/S41s31-wifi` |
| NTP lifecycle | overlay `etc/init.d/S49ntpd` |
| SSH host-key persistence | `patches/submodules/buildroot-persistent-dropbear.patch` |
| Image trimming/finalization | `buildroot-external/board/esp32-s31/post-build.sh` |
| S31 curl/mbedTLS size profile | `buildroot-external/package/s31-build-tweaks/` |

`bootloader/partitions.csv` belongs to the ESP-IDF loader lineage and is not
the authoritative U-Boot/Linux raw flash map for this feature branch.
