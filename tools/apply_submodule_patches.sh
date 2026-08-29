#!/bin/sh

set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

apply_once() {
	directory=$1
	patch_file=$2

	if git -C "$directory" apply --reverse --check "$patch_file" 2>/dev/null; then
		return 0
	fi
	if ! git -C "$directory" apply --check "$patch_file"; then
		echo "Cannot apply required patch: $patch_file" >&2
		exit 1
	fi
	git -C "$directory" apply "$patch_file"
}

apply_once "$project_dir/buildroot" \
	"$project_dir/patches/submodules/buildroot-macos-host.patch"
apply_once "$project_dir/buildroot" \
	"$project_dir/patches/submodules/buildroot-persistent-dropbear.patch"
apply_once "$project_dir/linux-esp32-s31" \
	"$project_dir/patches/submodules/linux-idf62-iram.patch"
