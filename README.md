# ESP32-S31 Buildroot External Tree

> **Community project**: This is an independent extension of Espressif's
> developer-preview `esp-buildroot-external` branch. It is not an official
> Espressif release.
>
> **Tested hardware**: ESP32-S31 Function-CoreBoard-1 with its onboard YT8531
> Gigabit Ethernet PHY. DHCP, DNS, Internet connectivity, and NTP were verified
> at a 1000 Mb/s full-duplex link.

> **⚠️ Espressif Integration**: This repository provides Buildroot integration and configurations for ESP32S31.
> **⚠️ Developer Preview**: This branch (`buildroot/v2025.02-esp32s31`) is currently in developer preview and is **not yet recommended for production use**.  
> For branch strategy and maintenance policy, see the [Branch Strategy](#branch-strategy) section below.

This BR2_EXTERNAL tree builds the ESP32-S31 NOR boot stack and root filesystem
with Buildroot 2025.02.

## Prerequisites

Clone the matching upstream Buildroot release to a local path:

```sh
git clone --branch 2025.02 --depth 1 \
  https://gitlab.com/buildroot.org/buildroot.git <path-to-buildroot>
```

## Configure

```sh
make -C <path-to-buildroot> \
  BR2_EXTERNAL=<path-to-esp-buildroot-external> \
  O=<path-to-output-directory> \
  espressif_esp32s31_function_core_board_nor_defconfig
```

The defconfig builds a 32-bit RISC-V musl toolchain and uses these integration
branches:

- OpenSBI: [`integration/v1.6-esp32s31`](https://github.com/espressif/opensbi/tree/integration/v1.6-esp32s31)
- U-Boot: [`integration/v2024.07-esp32s31`](https://github.com/espressif/u-boot/tree/integration/v2024.07-esp32s31)
- Linux: [`integration/v6.18-esp32s31`](https://github.com/espressif/linux/tree/integration/v6.18-esp32s31)
- BSP tools: [`integration/v1.0-esp32s31`](https://github.com/espressif/esp-linux-bsp/tree/integration/v1.0-esp32s31)

## Build

Provide an ESP32-S31-capable `esptool` through `ESP_ESPTOOL` or `PATH`, then
run:

```sh
ESP_ESPTOOL=<path-to-esptool> \
make -C <path-to-buildroot> O=<path-to-output-directory> -j"$(nproc)"
```

The final flash image is
`<path-to-output-directory>/images/s31_full_flash.bin`.

## Deploy

Connect the board in download mode and write the complete flash image at
offset `0x0`:

```sh
<path-to-esptool> \
  --chip esp32s31 \
  --port <serial-port> \
  --baud 1152000 \
  write-flash \
  0x0 <path-to-output-directory>/images/s31_full_flash.bin
```

Use a lower baud rate, such as `460800`, if the serial connection is unstable.
After flashing, open the console at 115200 baud:

```sh
screen /dev/cu.usbserial-10 115200
```

Successful boot reaches a root shell after the SPL, OpenSBI, U-Boot, Linux,
and root filesystem have started.

### Backward-compatible rootfs update

On a board already running the verified Function-CoreBoard bootloader and
kernel, update only the cramfs slot to preserve that low-level boot stack:

```sh
<path-to-esptool> \
  --chip esp32s31 \
  --port <serial-port> \
  --baud 115200 \
  --no-stub write-flash \
  0xC00000 <path-to-output-directory>/images/rootfs.cramfs
```

The `0xC00000` offset is specific to this NOR profile. Do not use it with a
different partition layout.

## Ethernet networking

The Function-CoreBoard Ethernet port starts automatically as `eth0` and uses
DHCP. After a default route is available, `ntpd` synchronizes against
`0.pool.ntp.org` and `1.pool.ntp.org`. The image includes `ip`, `ifconfig`,
`route`, `ping`, `nslookup`, `netstat`, `wget`, `ethtool`, `tcpdump`, `ntpd`,
`udhcpc`, and the beginner-friendly `pico`/`nano` text editor.

Useful checks from the serial console are:

```sh
ip -4 addr show eth0
ip route
cat /etc/resolv.conf
ethtool eth0
ping -c 3 1.1.1.1
nslookup pool.ntp.org
date -u
```

The ESP32-S31 GMAC cannot reliably transmit Linux socket buffers directly
from PSRAM. The board patch therefore uses the reserved internal DMA pool as
a coherent transmit bounce buffer.

No board-specific MAC address is published in this tree. Unless the
bootloader supplies a valid address, Linux generates a locally administered
address at boot. For a stable DHCP identity, add your own unique
`local-mac-address` to the GMAC device-tree node.

## SSH access

The Function-CoreBoard profile runs Dropbear on TCP port 22 and permits only
public-key authentication for `root`. Replace
`board/espressif/esp32s31/rootfs_overlay/root/.ssh/authorized_keys` with your
own public key before distributing an image.

For the local development board built from this checkout, connect with:

```sh
ssh -i ~/esp-linux/keys/esp32s31_ed25519 root@<board-ip>
```

On the tested board, TCP port 22 becomes available about 80 seconds after a
cold boot, once the kernel random-number generator is ready. Both command
execution and interactive PTY sessions are supported.

Because the root filesystem is read-only, the SSH server generates an
ephemeral host key in `/var/run` at every boot. Remove the old entry with
`ssh-keygen -R <board-ip>` if the client reports that the host key changed.

## Experimental native Wi-Fi, BLE, and persistence

The `feature/native-wifi-ble` branch records the current Function-CoreBoard
bring-up. It supersedes the earlier split-core transport experiment with a
native Linux radio design: Linux exposes `wlan0` through cfg80211/nl80211 and
`hci0` through a dedicated ESP32-S31 HCI driver. The earlier
`feature/wifi-core1` branch remains available for history and compatibility.

The 2026-08-27 candidate build includes:

- a 1 MiB JFFS2 upper layer that makes `/etc`, `/root`, and other overlay
  changes persistent while retaining a compressed read-only SquashFS base;
- native Wi-Fi scan, WPA2 connection, DHCP, saved credentials, and automatic
  reconnect;
- native BLE power control and advertisement scanning without requiring the
  full BlueZ userspace suite;
- Dropbear SSH, NTP synchronization, `ip`, `iw`, and `pico`/`nano`;
- a separate experimental kernel with DWC2 USB-host mass-storage support.

Both kernels fit the existing 6 MiB slot. The normal kernel is 5,920,076 bytes
and the USB-storage variant is 6,055,244 bytes. The root filesystem is
2,932,736 bytes in its 4 MiB slot.

The build has passed compile, link, filesystem-content, checksum, and flash
layout checks. On-board validation is still pending. Do not flash it without
an external UART console and a verified 16 MiB backup of the working Ethernet
installation. The tested recovery image and stable branch remain unchanged.

Management commands in the candidate image are:

```sh
s31-wifi scan
s31-wifi connect "SSID" "passphrase" --save
s31-wifi status
s31-wifi disconnect
s31-wifi forget

s31-ble up
s31-ble scan 15
s31-ble status
s31-ble down

s31-usb-storage status
s31-usb-storage mount
s31-usb-storage unmount
```

The normal image must be validated before testing the USB-storage variant.
USB-DBG is the programming/debug connection, not the USB host connector.

---

## Branch Strategy

### `buildroot/v2025.02-esp32s31` - Developer Preview

This branch is currently in **developer preview** and is **not yet recommended for production use**.

#### Purpose
- Quick access to ESP32-S31 support
- Technical validation and feedback collection
- Evaluation and testing purposes only

#### What to Expect
- **Limited chip support**: ESP32-S31 only
- **Irregular updates**: No scheduled release cadence
- **Breaking changes**: May occur without notice
- **Limited feature acceptance**: New feature requests may not be accepted during the Developer Preview
- **Bug fixes**: Bug fixes may be addressed on a best-effort basis during the Developer Preview

#### Maintenance Policy
- Bug reports are welcome but may be deferred
- Pull requests reviewed on a case-by-case basis
- No API/ABI compatibility guarantees
- Best-effort support only

#### Recommended For
- Early adopters wanting immediate ESP32-S31 access
- Hardware evaluation and prototyping
- Testing and providing feedback to Espressif

#### Not Recommended For
- Production deployments
- Long-term projects requiring stability
- Critical systems
