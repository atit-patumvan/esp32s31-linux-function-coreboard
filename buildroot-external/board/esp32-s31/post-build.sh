#!/bin/sh

set -eu

target_dir="$1"

chmod 0755 "${target_dir}/init"

# This compact image has no C++ target packages.  Keep incremental output trees
# clean if they were previously built with a C++-capable external toolchain.
rm -f "${target_dir}"/lib/libstdc++.so*

# Keep incremental builds honest after retiring the FreeRTOS hosted/audio
# transport. Buildroot does not uninstall files emitted by an older version of
# a local package when the install commands shrink.
rm -f \
	"${target_dir}/usr/sbin/esp-hosted-ctl" \
	"${target_dir}/usr/sbin/s31-clock-compare" \
	"${target_dir}/usr/sbin/s31-cpufreq" \
	"${target_dir}/usr/sbin/s31-freertos-mem" \
	"${target_dir}/usr/sbin/test.out" \
	"${target_dir}/usr/bin/s31-peripheral-test" \
	"${target_dir}/usr/bin/s31-audio-analyze" \
	"${target_dir}/usr/bin/s31-audio-loopback" \
	"${target_dir}/usr/bin/s31-audio-mic-test" \
	"${target_dir}/usr/bin/s31-audio-stream-stats" \
	"${target_dir}/usr/bin/aplay" \
	"${target_dir}/usr/bin/arecord"
rm -rf "${target_dir}/usr/share/alsa"
rm -f "${target_dir}"/usr/lib/libasound.so*

# curl and libcurl use the generated CA bundle. The individual Mozilla source
# certificates and c_rehash links duplicate that data in this 4 MiB rootfs.
# Cache the bundle because Buildroot's incremental finalization runs before this
# script and its source certificates were intentionally removed on the prior run.
ca_bundle="${target_dir}/etc/ssl/certs/ca-certificates.crt"
ca_cache="$(dirname "${target_dir}")/build/s31-ca-certificates.crt"
if [ -s "${ca_bundle}" ]; then
	cp "${ca_bundle}" "${ca_cache}"
elif [ -s "${ca_cache}" ]; then
	cp "${ca_cache}" "${ca_bundle}"
else
	echo "Missing generated CA certificate bundle" >&2
	exit 1
fi
if [ -f "${ca_bundle}" ]; then
	find "${target_dir}/etc/ssl/certs" -type l -delete
	rm -rf "${target_dir}/usr/share/ca-certificates"
fi

# A case-insensitive macOS build host makes tic use hexadecimal directories
# (for example 78/xterm), while target ncurses expects x/xterm. Provide both
# lookup layouts without duplicating the terminfo data.
terminfo_dir="${target_dir}/usr/share/terminfo"
for mapping in a:61 d:64 l:6c p:70 s:73 v:76 x:78; do
	letter="${mapping%%:*}"
	hex="${mapping#*:}"
	[ -d "${terminfo_dir}/${hex}" ] || continue
	mkdir -p "${terminfo_dir}/${letter}"
	for entry in "${terminfo_dir}/${hex}"/*; do
		[ -f "${entry}" ] || continue
		ln -sf "../${hex}/${entry##*/}" \
			"${terminfo_dir}/${letter}/${entry##*/}"
	done
done

rm -rf \
	"${target_dir}/tmp" \
	"${target_dir}/run" \
	"${target_dir}/var/log" \
	"${target_dir}/var/tmp"

mkdir -m 1777 "${target_dir}/tmp"
mkdir -m 0755 "${target_dir}/run" "${target_dir}/var/log"
ln -s /tmp "${target_dir}/var/tmp"

rm -rf "${target_dir}/var/lib/bluetooth"
ln -s /run/bluetooth "${target_dir}/var/lib/bluetooth"

rm -rf "${target_dir}/var/lib/seedrng"
ln -s /run/seedrng "${target_dir}/var/lib/seedrng"

rm -f "${target_dir}/etc/mtab" "${target_dir}/etc/resolv.conf"
ln -s /proc/mounts "${target_dir}/etc/mtab"
ln -s /run/resolv.conf "${target_dir}/etc/resolv.conf"

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/../../.." && pwd)"
dtbo_dir="${S31_DTBO_DIR:-${project_dir}/build/linux-6.18/arch/riscv/boot/dts/espressif}"
install_dir="${target_dir}/usr/lib/s31-overlays"

mkdir -p "${install_dir}"
for dtbo in "${dtbo_dir}"/esp32s31-overlay-*.dtbo; do
	[ -f "${dtbo}" ] || {
		echo "Missing S31 DT overlays in ${dtbo_dir}" >&2
		exit 1
	}
	cp "${dtbo}" "${install_dir}/"
done
