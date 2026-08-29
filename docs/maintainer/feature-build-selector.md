# Interactive Feature Build Selector

`tools/s31-build` provides one entry point for choosing the supported kernel
features and build environment. It builds artifacts only and never flashes a
board.

## Interactive use

From the repository root:

```sh
./tools/s31-build
```

The menu asks for:

1. Wi-Fi plus BLE, or Wi-Fi only.
2. Experimental USB mass storage enabled or disabled.
3. Complete image, Linux, rootfs, or merged recovery-image target.
4. Automatic, native Linux, or reproducible Docker execution.

The tool shows the final selection and asks for confirmation before building.

## Profiles

| Profile | Wi-Fi | BLE `hci0` | USB storage |
|---|---|---|---|
| `wifi` | yes | no | no |
| `wifi-usb` | yes | no | yes |
| `gateway` | yes | yes | no |
| `gateway-usb` | yes | yes | yes |

List profiles without building:

```sh
./tools/s31-build --list-profiles
```

For the planned BLE-to-cloud gateway with writable USB storage:

```sh
./tools/s31-build --profile gateway-usb --target all
```

On macOS or ARM Linux, automatic execution selects the pinned amd64 Docker
container. On x86-64 Linux, it selects the native build.

## Scripted examples

Native Ubuntu build with an explicit ESP-IDF installation:

```sh
./tools/s31-build --profile gateway-usb \
  --executor native \
  --idf-export /path/to/esp-idf/export.sh \
  --target all
```

Reproducible Docker build on Apple silicon:

```sh
./tools/s31-build --profile gateway-usb \
  --executor docker \
  --target all
```

Force the pinned container to be rebuilt:

```sh
./tools/s31-build --profile gateway-usb \
  --executor docker --rebuild-container
```

Preview the selection and cleaning decision without changing files:

```sh
./tools/s31-build --profile gateway-usb --dry-run
```

Individual feature flags override a profile:

```sh
./tools/s31-build --profile gateway --usb-storage
./tools/s31-build --profile gateway-usb --no-usb-storage
./tools/s31-build --profile wifi --ble
```

## Automatic clean behavior

The radio payload does not encode build-variable changes as normal file
dependencies. Reusing a Wi-Fi-only radio object in a BLE build could therefore
produce a kernel without `hci0` even though the command requested BLE.

The selector records the last successful feature values in:

```text
build/.s31-feature-state
```

If BLE or USB selection changes—or an older build tree exists without recorded
state—it runs both:

```sh
make -C radio_firmware clean
make clean
```

Use `--clean` to force the same behavior. The selection is recorded after a
successful build at:

```text
build/s31-build-selection.txt
```

Archive this manifest with the firmware hashes.

## Features that remain in every profile

The selector changes only the supported kernel/radio variants. All profiles
retain the standard rootfs baseline:

- Ethernet with DHCP configuration
- persistent overlay storage
- Dropbear SSH and persistent host keys
- NTP and runtime DNS
- `ip`, `iw`, `ethtool`, `curl`, `nc`, and `tracepath`
- `nano` and `pico`
- Wi-Fi management commands

Removing individual rootfs packages requires editing the Buildroot defconfig
and repeating the rootfs size and hardware acceptance process.

## Build targets

| Target | Result |
|---|---|
| `all` | standard complete build and merged image |
| `linux` | kernel and DTB, including selected radio/USB features |
| `rootfs` | rootfs plus its Linux/DT-overlay dependencies |
| `flash-image` | merged recovery image and all prerequisites |

None of these selector targets writes the board. Flash separately only after
checking `build/s31-build-selection.txt`, image sizes, and backups. Use
segmented `flash-all` to preserve persist.

## Important variant check after boot

```sh
uname -a
s31-ble status
s31-usb-storage status
```

A Wi-Fi-only kernel intentionally has no `hci0`. USB storage requires a block
device under `/dev/sd*`; an empty `/media/usb` directory does not prove that a
drive was detected or mounted.
