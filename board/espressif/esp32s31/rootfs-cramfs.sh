#!/usr/bin/env bash
# Post-fakeroot hook for the esp32s31 profile: pack the whole target tree
# into a COMPRESSED cramfs mounted directly as / from the flash XIP window
# (root=mtd:rootfs rootfstype=cramfs). Replaces the extracted-initramfs
# root: the cpio extraction pinned ~3.3 MB of tmpfs; cramfs file pages are
# ordinary evictable page cache backed by flash.
#
# Runs inside fakeroot (so file ownership/modes are packed as root), with
# $1 = TARGET_DIR. Output: $BINARIES_DIR/rootfs.cramfs, merged into
# s31_full_flash.bin at the rootfs slot defined by esp32s31-layout.cfg.
set -e

TARGET="${1:?usage: rootfs-cramfs.sh TARGET_DIR}"
MK="$HOST_DIR/bin/mkcramfs"

[ -x "$MK" ] || { echo "rootfs-cramfs: $MK missing (enable BR2_PACKAGE_HOST_CRAMFS)"; exit 1; }

echo "rootfs-cramfs: mkcramfs $TARGET -> rootfs.cramfs"
"$MK" -L -q -n rootfs "$TARGET" "$BINARIES_DIR/rootfs.cramfs"

sz=$(stat -c%s "$BINARIES_DIR/rootfs.cramfs")
printf 'rootfs-cramfs: rootfs.cramfs = %d bytes (%d KB)\n' "$sz" "$((sz / 1024))"
# The rootfs starts at 0xC00000 in a 16 MiB flash, leaving a 4 MiB slot.
if [ "$sz" -gt $((4 * 1024 * 1024)) ]; then
	echo "rootfs-cramfs: ERROR rootfs.cramfs exceeds the 4 MiB flash slot"
	exit 1
fi
