# Storage, Persistence, Flashing, and Recovery

## Authoritative 16 MiB raw flash map

`configs/esp32s31-layout.cfg` is authoritative for packaging and flashing.

| Raw offset | Size | Content | Routine update? |
|---:|---:|---|---|
| `0x002000` | bounded by next slot | wrapped U-Boot SPL | yes |
| `0x100000` | 2 MiB | U-Boot FIT with OpenSBI | yes |
| `0x300000` | 2 MiB | DTB slot | yes |
| `0x500000` | 6 MiB | Linux XIP kernel | yes |
| `0xB00000` | 1 MiB | JFFS2 `persist` | preserve |
| `0xC00000` | 4 MiB | SquashFS rootfs | yes |

The Linux flash MTD mapping starts at raw offset `0x100000`. Its device-tree
partition offsets are therefore 1 MiB lower: `persist` is `0xA00000` relative
to the MTD window and rootfs is `0xB00000`. This is intentional.

The older `bootloader/partitions.csv` is not the source of truth for this
U-Boot/Linux layout. Never calculate maintenance flash offsets from it.

## How writable persistence works

The rootfs itself is immutable SquashFS. The early `/init` program:

1. Mounts `/dev`, `/proc`, and `/sys`.
2. Finds the MTD partition whose label is exactly `persist`.
3. Mounts it as JFFS2 at `/mnt/persist`.
4. Creates `upper/` and `work/` there.
5. Mounts overlayfs with the SquashFS root as lower and JFFS2 as upper.
6. Pivots into the merged root and exposes the JFFS2 filesystem at `/persist`.
7. Recreates `/run`, `/tmp`, and `/var/log` as volatile tmpfs mounts.

Consequences:

- Changes under `/etc`, `/root`, and most of `/var` survive reset.
- `/run`, `/tmp`, and `/var/log` do not survive reset.
- `/persist` is the direct view of the JFFS2 storage.
- Deleting or replacing lower-layer files consumes overlay metadata and may
  need whiteouts; avoid unnecessary changes on this small JFFS2 partition.

Verify on target:

```sh
cat /proc/mtd
mount | grep -E ' on / | on /persist '
df -h /persist
```

Expected MTD labels are `u-boot-fit`, `dtb`, `linux`, `persist`, and `rootfs`.

## Back up before changing firmware

Use USB-DBG and read exact raw regions:

```sh
source /path/to/esp-idf/export.sh
esptool --chip esp32s31 --port /dev/cu.usbmodem1101 \
  read-flash 0xB00000 0x100000 persist-backup.bin
esptool --chip esp32s31 --port /dev/cu.usbmodem1101 \
  read-flash 0xC00000 0x400000 rootfs-backup.bin
shasum -a 256 persist-backup.bin rootfs-backup.bin
```

Raw persist backups can contain Wi-Fi credentials, modified configuration, and
SSH host private keys. Store them as secrets and never attach them to a public
issue or commit.

## Safe routine flashing

Rootfs-only update on the tested macOS USB-DBG port:

```sh
source /path/to/esp-idf/export.sh
esptool --chip esp32s31 --port /dev/cu.usbmodem1101 --baud 921600 \
  write-flash --flash-mode dio --flash-freq 80m --flash-size 16MB \
  0xC00000 build/rootfs.sqfs
```

The Makefile equivalent is `make flash-rootfs`, after adjusting the serial port
used by that recipe for the current host.

`make flash-all` writes SPL, U-Boot, DTB, Linux, and rootfs as separate regions
and omits `persist`. It is the preferred complete routine update.

## Operations that erase persistent data

- `make erase` erases the whole chip.
- `make flash-persist` writes a new empty JFFS2 image.
- Flashing `build/s31_full_flash.bin` includes erased padding across the persist
  gap and resets it.

Use these only for first installation, deliberate factory reset, layout
migration, or recovery after a corrupt JFFS2 filesystem.

## Restore a backup

Confirm the backup is exactly 1,048,576 bytes before restoring persist:

```sh
test "$(wc -c < persist-backup.bin | tr -d ' ')" = 1048576
source /path/to/esp-idf/export.sh
esptool --chip esp32s31 --port /dev/cu.usbmodem1101 --baud 921600 \
  write-flash --flash-mode dio --flash-freq 80m --flash-size 16MB \
  0xB00000 persist-backup.bin
```

Restore a rootfs backup at `0xC00000` only after confirming it is no larger
than 4,194,304 bytes.

## Reset behavior

On the tested Function-CoreBoard, Linux `reboot` finishes shutdown but does not
assert the final hardware reset. Use the physical reset control or this
non-destructive USB-DBG operation:

```sh
source /path/to/esp-idf/export.sh
esptool --chip esp32s31 --port /dev/cu.usbmodem1101 chip-id
```

`esptool` connects, reads identity information, and releases reset without
writing flash.

## Recovery sequence

1. Keep USB-UART open at 115200 and capture the complete boot log.
2. Verify the image sizes and offsets before any new write.
3. If only rootfs is damaged, restore or reflash rootfs at `0xC00000`.
4. If Linux/DTB is damaged, use segmented `flash-all`; keep persist untouched.
5. If overlay mount fails, first back up raw persist, then deliberately reset
   it with `make flash-persist`.
6. Use a merged recovery image or whole-chip erase only as the last resort.

The boot warning `Failed to add a System RAM resource at 50000000` was observed
on a working build and is not, by itself, evidence of a boot failure.
