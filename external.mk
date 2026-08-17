include $(sort $(wildcard $(BR2_EXTERNAL_ESP_LINUX_BSP_PATH)/package/*/*.mk))

OPENSBI_DEPENDENCIES += host-esp-cross-linker-wrapper
UBOOT_DEPENDENCIES += host-esp-cross-linker-wrapper
