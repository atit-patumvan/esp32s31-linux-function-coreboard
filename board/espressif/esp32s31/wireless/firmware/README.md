# ESP32-S31 Wi-Fi probe

This ESP-IDF application performs one blocking station scan, prints the radio
MAC address and discovered access points, and then leaves Wi-Fi idle. It is a
standalone hardware diagnostic, not the final Linux co-processor firmware.

Build it with the ESP-IDF version that supports ESP32-S31:

```sh
idf.py set-target esp32s31
idf.py build
```

The firmware also initializes ABI v1 at `0x2f040000`, reserves the Linux GMAC
DMA and transport ranges from the ESP-IDF heap, and advances the firmware
heartbeat once per second. Linux will consume that heartbeat after the
split-core loader starts it on the other hart.

Validated on the S31 Function-CoreBoard: Wi-Fi initialized successfully and
the station scan discovered nearby access points while the heartbeat ran.

Do not flash this probe as part of the normal Linux image. Flashing a normal
ESP-IDF project changes the flash layout; preserve `s31_full_flash.bin` so the
Linux image can be restored at offset `0x0`.
