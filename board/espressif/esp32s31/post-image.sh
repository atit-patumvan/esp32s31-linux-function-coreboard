#!/bin/bash
#
# Thin hook: image packaging lives in esp-linux-bsp.

set -eu

IMAGES_DIR="$1"
STORAGE_TYPE="${2:-nor}"

[ "$STORAGE_TYPE" = "nor" ] || {
    echo "✗ Error: ESP32-S31 only supports NOR image packaging"
    exit 1
}

# Locate esp-linux-bsp. Resolution order:
#   1) ESP_BSP_DIR if set (manual override / CI).
#   2) host package install dir (when BR2_PACKAGE_HOST_ESP_LINUX_BSP fetched it).
#   3) sibling checkout next to the buildroot tree (dev convenience).
if [ -z "${ESP_BSP_DIR:-}" ]; then
    if [ -x "${HOST_DIR:-}/share/esp-linux-bsp/tools/buildroot_post_image.sh" ]; then
        ESP_BSP_DIR="${HOST_DIR}/share/esp-linux-bsp"
    else
        ESP_BSP_DIR="$(pwd)/../esp-linux-bsp"
    fi
fi
ORCH="$ESP_BSP_DIR/tools/buildroot_post_image.sh"
if [ ! -x "$ORCH" ]; then
    echo "✗ Error: esp-linux-bsp orchestrator not found: $ORCH (set ESP_BSP_DIR)"
    exit 1
fi

exec "$ORCH" esp32s31 "$STORAGE_TYPE" "$IMAGES_DIR"
