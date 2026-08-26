# ESP32-S31 split-core wireless bring-up

This directory contains the transport ABI shared by the experimental
ESP-IDF wireless service and Linux host driver.

The intended ownership model is:

- hart 0 runs ESP-IDF/FreeRTOS and owns Wi-Fi, Bluetooth and RF coexistence;
- hart 1 runs Linux and owns Ethernet, IP networking and cloud services;
- a reserved 64 KiB region carries control messages, Ethernet frames and,
  later, Bluetooth HCI packets;
- the existing Ethernet-only Buildroot defconfig remains unchanged.

The physical address is deliberately absent from the ABI. The bootloader must
select a region that does not overlap its stack, OpenSBI, Linux, GMAC DMA, ROM
work areas or ESP-IDF heaps. It then publishes the same region through the
Linux device tree.

## Bring-up gates

1. Build and run `abi-layout-test.c` on the host.
2. Boot a heartbeat-only service on hart 0 and Linux on hart 1.
3. Verify both heartbeat counters without enabling the radio.
4. Add cache maintenance and a bidirectional control-message loopback.
5. Add the Wi-Fi station data channel and Linux virtual Ethernet driver.
6. Add scan/connect control messages and DHCP on Linux.
7. Add Bluetooth HCI only after Wi-Fi is stable.

The transport starts in polling mode for diagnosis. Inter-core interrupts are
added only after the shared-memory protocol passes sustained loopback tests.
