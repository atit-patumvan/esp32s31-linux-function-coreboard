# Native Radio, BLE, USB, and BLE-to-Cloud Gateway Direction

## Radio build flow

Wi-Fi and Bluetooth are not hosted by a second FreeRTOS application in this
profile. The build creates an ESP-IDF radio library closure and links it into a
Linux S-mode payload:

```text
Pinned ESP-IDF
  -> bootloader/build-radio libraries
  -> radio_firmware/linux_radio.kbuild.o
  -> linux-esp32-s31/drivers/platform/esp32s31-radio-idf.o_shipped
  -> Linux native radio driver
  -> wlan0 and, in the normal variant, hci0
```

The root `Makefile` target `radio-bootloader` creates the matching ESP-IDF
libraries. `radio-linux-payload` invokes `radio_firmware/Makefile`, and `linux`
selects the final driver configuration.

The project-owned Linux linker patch keeps all ESP-IDF IRAM-named code sections
in executable XIP text. If an ESP-IDF upgrade introduces new section names,
inspect the final ELF and linker map before assuming the old rule remains safe.

## Variants

- Default: Wi-Fi plus experimental Bluetooth HCI (`S31_WIFI_ONLY=0`).
- Wi-Fi diagnostic: `S31_WIFI_ONLY=1`, intentionally no `hci0`.
- USB mass storage: `S31_USB_STORAGE=1`, opt-in due runtime memory and driver
  risk.

Clean both the root build and radio objects when switching variants. See the
reproducible build guide for commands.

## BLE management

The image deliberately avoids large BlueZ userspace. Compact project tools use
the kernel HCI interface directly:

```sh
s31-ble up
s31-ble status
s31-ble scan 15
s31-ble down
```

Implementation files:

```text
rootfs/ble_power.c
rootfs/ble_scan.c
buildroot-external/board/esp32-s31/overlay/usr/sbin/s31-ble
buildroot-external/package/s31-tools/s31-tools.mk
```

Diagnosis:

```sh
ls -l /sys/class/bluetooth
s31-ble status
dmesg | grep -i -E 'bluetooth|hci|radio|vhci'
```

If the kernel banner contains `wifi-only`, absence of `hci0` is expected.

## USB host and storage

The device tree enables the ESP32-S31 PHY and DWC2 controller in host mode. The
default kernel omits USB mass-storage support; the opt-in build enables SCSI,
`BLK_DEV_SD`, and `USB_STORAGE`.

```sh
s31-usb-storage status
dmesg | tail -n 100
lsblk
s31-usb-storage mount /dev/sda1
s31-usb-storage unmount
```

Use a disposable test device first. Confirm the block-device identity and size
before mounting or writing. The helper mounts at `/media/usb` and chooses the
first `/dev/sd*` device when none is supplied.

## BLE-to-cloud gateway architecture

The intended final appliance is:

```text
BLE advertisements
  -> native hci0 scan
  -> compact gateway daemon
  -> validation/deduplication/local queue under /persist
  -> HTTPS publish with curl/libcurl
  -> cloud endpoint
```

Recommended implementation order:

1. Stabilize `hci0` power-up and repeated scans under Wi-Fi traffic.
2. Define the exact advertisement formats and device allowlist.
3. Implement parsing and deduplication in a small C daemon. Python and Node.js
   are not currently included and are poor fits for the fixed 4 MiB rootfs.
4. Queue unsent records in a bounded file under `/persist`, with atomic rename
   and a hard storage limit.
5. Publish through libcurl using HTTPS certificate verification and explicit
   request/connect timeouts.
6. Add retry backoff with jitter and remove queue entries only after confirmed
   cloud acceptance.
7. Run under a BusyBox init script after networking and time are available.
8. Test power loss during queue write, network loss, invalid time, duplicate
   BLE packets, cloud 4xx/5xx responses, and a full persist partition.

Avoid logging BLE payloads or cloud credentials indiscriminately. `/var/log` is
volatile by design; only explicitly selected operational state should consume
limited JFFS2 erase cycles.

## Gateway acceptance criteria

- Repeated BLE scans do not stall Wi-Fi or the kernel.
- Cloud HTTPS validates CA certificates after NTP synchronization.
- Loss of network does not lose accepted BLE records or fill persist forever.
- Reset resumes the bounded queue without duplicating acknowledged records.
- SSH remains accessible and host identity remains stable.
- Memory usage stays safe during simultaneous scan, Wi-Fi RX/TX, TLS, and queue
  processing on the 16 MiB system.
