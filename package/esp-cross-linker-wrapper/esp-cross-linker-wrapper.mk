################################################################################
#
# host-esp-cross-linker-wrapper
#
################################################################################

ESP_CROSS_LINKER_WRAPPER_VERSION = 1.0
ESP_CROSS_LINKER_WRAPPER_SITE = $(BR2_EXTERNAL_ESP_LINUX_BSP_PATH)/package/esp-cross-linker-wrapper
ESP_CROSS_LINKER_WRAPPER_SITE_METHOD = local

HOST_ESP_CROSS_LINKER_WRAPPER_DEPENDENCIES = host-binutils

define HOST_ESP_CROSS_LINKER_WRAPPER_INSTALL_CMDS
	ln -sf ../$(GNU_TARGET_NAME)/bin/ld $(TARGET_CROSS)ld
	ln -sf ../$(GNU_TARGET_NAME)/bin/ld.bfd $(TARGET_CROSS)ld.bfd
endef

$(eval $(host-generic-package))
