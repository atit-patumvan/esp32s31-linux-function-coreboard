# Function-CoreBoard Build and Test Guide

This guide validates the `feature/function-coreboard-native-radio` profile on
an ESP32-S31 Function-CoreBoard with 16 MiB flash. The examples use the macOS
ports seen on one tested board:

- USB-DBG (flash/reset): `/dev/cu.usbmodem1101`
- USB-UART (Linux console): `/dev/cu.usbserial-110`

Device names can change after reconnecting the board. Find the current names
before flashing:

```sh
ls /dev/cu.usb*
```

For subsystem implementation details and recovery decisions, see the
[maintainer handbook](maintainer/README.md).

## 1. Build

Clone the public branch and initialize its pinned submodules:

```sh
git clone --recurse-submodules \
  --branch feature/function-coreboard-native-radio \
  https://github.com/atit-patumvan/esp32s31-linux-function-coreboard.git
cd esp32s31-linux-function-coreboard
make all
```

The root filesystem is written to `build/rootfs.sqfs`. The build fails if the
image exceeds its fixed 4 MiB flash slot.

The normal build enables Wi-Fi and BLE. For a Wi-Fi-only diagnostic kernel,
build with `S31_WIFI_ONLY=1`. Experimental USB mass-storage support is opt-in:

```sh
make S31_USB_STORAGE=1 linux rootfs
```

Alternatively, select the combined BLE-gateway and writable USB-storage build
interactively:

```sh
./tools/s31-build
```

or non-interactively:

```sh
./tools/s31-build --profile gateway-usb --target all
```

## 2. Flash without erasing persistent data

Routine firmware updates should not erase the 1 MiB `persist` partition.
`make flash-all` and `make flash-rootfs` preserve it. Do not run `make erase`
or `make flash-persist` unless the saved configuration is intentionally being
cleared.

On macOS, a rootfs-only update can be flashed directly through USB-DBG:

```sh
source /path/to/esp-idf/export.sh
esptool --chip esp32s31 --port /dev/cu.usbmodem1101 --baud 921600 \
  write-flash --flash-mode dio --flash-freq 80m --flash-size 16MB \
  0xC00000 build/rootfs.sqfs
```

The expected raw flash layout is:

| Region | Offset | Size |
|---|---:|---:|
| Linux kernel slot | `0x500000` | 6 MiB |
| Persistent JFFS2 | `0xB00000` | 1 MiB |
| SquashFS rootfs | `0xC00000` | 4 MiB |

For an initial installation, build and flash the empty persistent filesystem
once with `make flash-persist`. This operation clears any previous overlay.

## 3. Open the serial console

```sh
screen /dev/cu.usbserial-110 115200
```

Press Enter if the login prompt is already waiting. To close `screen`, press
`Ctrl-A`, then `K`, then `Y`.

## 4. Basic boot checks

Run these commands on the board:

```sh
uname -a
cat /proc/cpuinfo
mount | grep ' on / '
df -h / /persist
```

The root mount should be an `overlay` mounted `rw`. `/persist` should be JFFS2.

## 5. Ethernet, DHCP, and NTP

Connect the Ethernet cable, then check its address, route, link, and clock:

```sh
ip -brief addr show eth0
ip route
ethtool eth0 | grep 'Link detected'
date -u
ps | grep '[n]tpd'
```

`eth0` is configured for DHCP in `/etc/network/interfaces`. With a live cable,
it should be `UP` with an address supplied by the local DHCP server.

Because `/etc` is covered by the persistent overlay, an optional static
Ethernet configuration also survives reset. Edit it with `pico
/etc/network/interfaces`, replacing the `eth0` DHCP stanza with values suitable
for the local network:

```text
auto eth0
iface eth0 inet static
    address 192.168.1.80
    netmask 255.255.255.0
    gateway 192.168.1.1
```

Apply network changes from the serial console so an SSH session is not stranded
by an incorrect address.

## 6. Wi-Fi and saved configuration

Bring Wi-Fi up, scan, connect, and save the credentials:

```sh
s31-wifi scan
s31-wifi connect "YOUR_SSID" "YOUR_PASSPHRASE" --save
s31-wifi status
ip -brief addr show wlan0
ip route
```

The saved configuration is stored at `/etc/s31-conf/wifi.conf` through the
persistent overlay. Its values are Base64-encoded for safe shell parsing, not
encrypted. Avoid displaying or publishing this file.

After a reset, confirm that Wi-Fi reconnects automatically:

```sh
test -s /etc/s31-conf/wifi.conf && echo 'Wi-Fi configuration present'
ip -brief addr show wlan0
```

## 7. Network tools and HTTPS

```sh
command -v ethtool curl nc tracepath nano pico
ethtool --version
curl --version
tracepath -V
curl --fail --show-error --silent --output /dev/null \
  --write-out 'HTTPS status: %{http_code}\n' https://example.com/
tracepath -m 3 1.1.1.1
nc -z -v -w 5 example.com 443
```

The HTTPS check should report status 200. Curl validates the server certificate
against `/etc/ssl/certs/ca-certificates.crt` and supports HTTP and HTTPS only.

## 8. Nano and pico

macOS terminals commonly send `TERM=xterm-256color`; the login profile maps it
to the compact xterm database included in the image.

```sh
pico /tmp/editor-test
```

Use `Ctrl-O`, then Enter to save, and `Ctrl-X` to exit. `nano` invokes the same
small editor.

## 9. SSH and host-key persistence

Place the desired public login key in
`buildroot-external/board/esp32-s31/overlay/root/.ssh/authorized_keys` before
building. After the board obtains an address, connect from the host:

```sh
ssh -i /path/to/private_key root@BOARD_IP
```

On the board, verify that Dropbear uses persistent storage:

```sh
readlink /var/run/dropbear
ls -l /persist/dropbear
```

The link should resolve to `/persist/dropbear`. To test host-key persistence,
record the fingerprint on the host, reset the board, and run the same command
again:

```sh
ssh-keyscan -T 5 -t ed25519 BOARD_IP 2>/dev/null | ssh-keygen -lf -
```

The fingerprint must remain unchanged.

## 10. Writable-overlay persistence test

Create a marker on the board and flush pending writes:

```sh
date -u > /root/persistence-test
sync
```

On the currently tested Function-CoreBoard, `reboot` completes Linux shutdown
but does not assert the final hardware reset. Press the board reset control, or
issue this non-destructive USB-DBG command from the host:

```sh
source /path/to/esp-idf/export.sh
esptool --chip esp32s31 --port /dev/cu.usbmodem1101 chip-id
```

After the board boots again:

```sh
cat /root/persistence-test
test -s /etc/s31-conf/wifi.conf && echo 'Wi-Fi configuration survived'
readlink /var/run/dropbear
```

## 11. BLE test

BLE requires the normal radio build. A kernel built with `S31_WIFI_ONLY=1`
intentionally has no `hci0` device.

```sh
s31-ble up
s31-ble status
ls -l /sys/class/bluetooth/hci0
s31-ble scan 15
s31-ble down
```

The native HCI path is experimental. Record `dmesg` and the serial console if
`hci0` does not appear or a scan fails.

## 12. Optional USB-storage test

USB mass storage is available only in a kernel built with
`S31_USB_STORAGE=1`:

```sh
s31-usb-storage status
dmesg | tail -n 80
lsblk
```

Attach a disposable test device first. Confirm enumeration and block-device
size before attempting a mount, and do not write to an unknown device.

## Expected baseline

The tested Wi-Fi-only image reported Linux 6.18, obtained a DHCP address on
`wlan0`, completed a CA-verified HTTPS request, opened `pico` interactively,
and retained its Wi-Fi configuration, root marker, and Dropbear ED25519 host
key after a USB-DBG hardware reset.
