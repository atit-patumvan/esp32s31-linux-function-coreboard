################################################################################
#
# s31-tools
#
################################################################################

S31_TOOLS_VERSION = 1.0
S31_TOOLS_SITE = $(BR2_EXTERNAL_ESP32_S31_PATH)/../rootfs
S31_TOOLS_SITE_METHOD = local
S31_TOOLS_LICENSE = GPL-2.0-only
S31_TOOLS_DEPENDENCIES = dtc

define S31_TOOLS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		-I$(STAGING_DIR)/usr/include \
		$(@D)/s31_overlay.c -lfdt -o $(@D)/s31-overlay
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		$(@D)/ble_scan.c -o $(@D)/ble-scan
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		$(@D)/ble_power.c -o $(@D)/ble-power
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		$(@D)/wifi_scan.c -o $(@D)/wifi-scan
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		$(@D)/wifi_connect.c -o $(@D)/wifi-connect
endef

define S31_TOOLS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/s31-overlay \
		$(TARGET_DIR)/usr/sbin/s31-overlay
	$(INSTALL) -D -m 0755 $(@D)/ble-scan $(TARGET_DIR)/usr/sbin/ble-scan
	$(INSTALL) -D -m 0755 $(@D)/ble-power $(TARGET_DIR)/usr/sbin/ble-power
	$(INSTALL) -D -m 0755 $(@D)/wifi-scan $(TARGET_DIR)/usr/sbin/wifi-scan
	$(INSTALL) -D -m 0755 $(@D)/wifi-connect \
		$(TARGET_DIR)/usr/sbin/wifi-connect
endef

$(eval $(generic-package))
