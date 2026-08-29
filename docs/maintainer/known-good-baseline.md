# Known-Good Function-CoreBoard Baseline

This record captures the hardware-validated state from 2026-08-29. It is a
diagnostic reference, not a promise that DHCP addresses or serial device names
will remain the same.

## Source identity

The functional changes were committed as superproject commit:

```text
98f4abacc99a1d1495c86d5d7b2b1f6f4a785675
```

Pinned submodules at that commit:

```text
buildroot          cb857ba4c87a93e5265a9e4a3f32071abf39e14a
linux-esp32-s31    87d6ed85a5b833af737057af943781119a1345a4
opensbi-esp32-s31  2b1ea02dab7ffdacf07d4efd889e95833e138af7
u-boot-esp32-s31   06fe89c93ed52349f60120c77efe3018c1e6b29f
```

Other build inputs:

```text
ESP-IDF: a602e67b0bf9ee0806dc4e1df7afc9affedf5c33
Linux toolchain: esp32s31-linux-gcc-15.2.0-5
GCC: 15.2.0
```

Project-owned submodule patches were applied before building. A dirty marker on
Buildroot or Linux after patch application is expected.

## Hardware-validated rootfs artifact

The Wi-Fi-only rootfs used for the final flash test:

```text
size:   4,124,672 bytes
slot:   4,194,304 bytes
free:      69,632 bytes
SHA-256: 0ce1511dfe830ac33ed8fb13deb32ae4db3c0381c0f4da8884ba6fa7467d6d54
```

The local filename was `rootfs-s31-persistent-net-tools.sqfs`. Rebuilt files do
not need the same hash when timestamps or upstream generated data differ, but
they must meet the same size and functional acceptance checks.

## Observed target baseline

```text
Linux: 6.18.0-wifi-only, riscv32
wlan0: UP with DHCP and default route
eth0: driver present; link down when no cable was attached
root: overlayfs, read-write
persist: JFFS2, read-write
Dropbear runtime: /var/run/dropbear -> /persist/dropbear
curl: 8.21.0 with mbedTLS 3.6.6, HTTP/HTTPS
ethtool: 7.0
tracepath: iputils 20250605
nano/pico: GNU nano 9.0 tiny
```

## Acceptance results

- Wi-Fi configuration survived rootfs replacement and hardware reset.
- Wi-Fi reconnected automatically after hardware reset.
- Root marker under `/root` survived.
- Dropbear ED25519 fingerprint was unchanged across reset.
- CA-verified `curl https://example.com/` returned HTTP 200.
- `tracepath` reached the local gateway.
- `pico` opened interactively from a macOS `xterm-256color` SSH session.
- `ethtool`, `curl`, `nc`, `tracepath`, `nano`, and `pico` were found on target.
- The rootfs flash write was hash-verified by esptool.

## Known limitation

Linux `reboot` completed shutdown but did not restart the SoC on this board. A
USB-DBG hard reset immediately restored normal boot and all persistence checks
passed. Treat external reset as the supported maintenance procedure until a
platform restart handler is validated.

## What was not accepted yet

- BLE `hci0` was not tested in the final Wi-Fi-only image because that variant
  intentionally disables the Bluetooth driver.
- USB mass storage was not enabled in the final baseline image.
- Ethernet DHCP had passed in an earlier image, but the final validation had no
  live Ethernet cable.

These remain separate acceptance gates; do not infer them from the Wi-Fi-only
rootfs result.
