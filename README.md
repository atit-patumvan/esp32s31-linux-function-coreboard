# ESP32-S31 Buildroot External Tree

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

Successful boot reaches a root shell after the SPL, OpenSBI, U-Boot, Linux,
and root filesystem have started.
