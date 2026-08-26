// SPDX-License-Identifier: Apache-2.0
/* Standalone RF probe used before integrating the split-core transport. */

#include <inttypes.h>
#include <stdlib.h>

#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "nvs_flash.h"
#include "transport.h"

static const char *TAG = "s31-wifi-probe";

static void init_nvs(void)
{
	esp_err_t error = nvs_flash_init();

	if (error == ESP_ERR_NVS_NO_FREE_PAGES ||
	    error == ESP_ERR_NVS_NEW_VERSION_FOUND) {
		ESP_ERROR_CHECK(nvs_flash_erase());
		error = nvs_flash_init();
	}
	ESP_ERROR_CHECK(error);
}

static const char *auth_name(wifi_auth_mode_t mode)
{
	switch (mode) {
	case WIFI_AUTH_OPEN:
		return "open";
	case WIFI_AUTH_OWE:
		return "owe";
	case WIFI_AUTH_WEP:
		return "wep";
	case WIFI_AUTH_WPA_PSK:
		return "wpa";
	case WIFI_AUTH_WPA2_PSK:
		return "wpa2";
	case WIFI_AUTH_WPA_WPA2_PSK:
		return "wpa/wpa2";
	case WIFI_AUTH_WPA3_PSK:
		return "wpa3";
	case WIFI_AUTH_WPA2_WPA3_PSK:
		return "wpa2/wpa3";
	default:
		return "other";
	}
}

static void scan_once(void)
{
	wifi_ap_record_t *records;
	uint16_t count = 0;
	uint16_t capacity;

	ESP_ERROR_CHECK(esp_wifi_scan_start(NULL, true));
	ESP_ERROR_CHECK(esp_wifi_scan_get_ap_num(&count));
	capacity = count;
	if (!capacity) {
		ESP_LOGW(TAG, "scan completed: no access points found");
		return;
	}

	records = calloc(capacity, sizeof(*records));
	if (!records) {
		ESP_LOGE(TAG, "cannot allocate %u scan records", capacity);
		return;
	}
	ESP_ERROR_CHECK(esp_wifi_scan_get_ap_records(&count, records));
	ESP_LOGI(TAG, "scan completed: %u access points", count);
	for (uint16_t index = 0; index < count; index++) {
		ESP_LOGI(TAG,
			 "%02u channel=%u rssi=%d auth=%s bssid=%02x:%02x:%02x:%02x:%02x:%02x ssid=%s",
			 index + 1, records[index].primary, records[index].rssi,
			 auth_name(records[index].authmode),
			 records[index].bssid[0], records[index].bssid[1],
			 records[index].bssid[2], records[index].bssid[3],
			 records[index].bssid[4], records[index].bssid[5],
			 records[index].ssid);
	}
	free(records);
}

void app_main(void)
{
	uint8_t mac[6];
	wifi_init_config_t config = WIFI_INIT_CONFIG_DEFAULT();

	init_nvs();
	ESP_ERROR_CHECK(esp_netif_init());
	ESP_ERROR_CHECK(esp_event_loop_create_default());
	ESP_ERROR_CHECK(esp_wifi_init(&config));
	ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
	ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
	ESP_ERROR_CHECK(esp_wifi_start());
	ESP_ERROR_CHECK(esp_read_mac(mac, ESP_MAC_WIFI_STA));
	ESP_LOGI(TAG, "station MAC %02x:%02x:%02x:%02x:%02x:%02x",
		  mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
	ESP_ERROR_CHECK(s31_transport_start(mac));
	scan_once();
	ESP_LOGI(TAG, "Wi-Fi RF probe passed; leaving station idle");
}
