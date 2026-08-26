# SPDX-License-Identifier: Apache-2.0
idf_component_register(SRCS "wifi_probe.c" "transport.c"
                       INCLUDE_DIRS "." "../.."
                       REQUIRES esp_event esp_mm esp_netif esp_wifi heap
                                nvs_flash)
