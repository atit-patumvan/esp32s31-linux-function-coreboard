// SPDX-License-Identifier: Apache-2.0
/* ESP-IDF endpoint for the split-core transport bring-up heartbeat. */

#include <string.h>

#include "esp_cache.h"
#include "esp_log.h"
#include "esp32s31_wireless_abi.h"
#include "esp32s31_wireless_layout.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "heap_memory_layout.h"
#include "transport.h"

static const char *TAG = "s31-transport";
static volatile struct s31_wireless_control *const control =
	(void *)S31_WIRELESS_REGION_BASE;

/* Keep Linux-owned DMA and transport pages out of the ESP-IDF heap. */
SOC_RESERVE_MEMORY_REGION(S31_GMAC_DMA_BASE, S31_GMAC_DMA_END,
			  linux_gmac_dma);
SOC_RESERVE_MEMORY_REGION(S31_WIRELESS_REGION_BASE,
			  S31_WIRELESS_REGION_END, wireless_transport);

static esp_err_t publish_firmware_state(void)
{
	esp_err_t error;

	__asm__ __volatile__("fence rw, rw" ::: "memory");
	error = esp_cache_msync((void *)&control->firmware,
				sizeof(control->firmware),
				ESP_CACHE_MSYNC_FLAG_DIR_C2M);
	/* Internal HP SRAM is uncached in current S31 ESP-IDF builds. */
	return error == ESP_ERR_NOT_SUPPORTED ? ESP_OK : error;
}

static void heartbeat_task(void *argument)
{
	(void)argument;
	for (;;) {
		control->firmware.heartbeat++;
		if (publish_firmware_state() != ESP_OK)
			control->firmware.errors++;
		vTaskDelay(pdMS_TO_TICKS(1000));
	}
}

esp_err_t s31_transport_start(const uint8_t sta_mac[6])
{
	esp_err_t error;

	memset((void *)control, 0, S31_WIRELESS_REGION_SIZE);
	control->magic = S31_WIRELESS_MAGIC;
	control->abi_version = S31_WIRELESS_ABI_VERSION;
	control->control_size = sizeof(*control);
	control->region_size = S31_WIRELESS_REGION_SIZE;
	control->firmware.features = S31_WIRELESS_FEAT_WIFI;
	control->firmware.generation = 1;
	control->firmware.ready = S31_WIRELESS_ENDPOINT_READY;
	memcpy((void *)control->firmware.sta_mac, sta_mac,
	       sizeof(control->firmware.sta_mac));
	__asm__ __volatile__("fence rw, rw" ::: "memory");
	error = esp_cache_msync((void *)control, S31_WIRELESS_CONTROL_SIZE,
				ESP_CACHE_MSYNC_FLAG_DIR_C2M);
	if (error == ESP_ERR_NOT_SUPPORTED)
		error = ESP_OK;
	if (error != ESP_OK)
		return error;

	if (xTaskCreate(heartbeat_task, "s31-heartbeat", 2048, NULL, 1, NULL) !=
	    pdPASS)
		return ESP_ERR_NO_MEM;
	ESP_LOGI(TAG, "ABI v%u at 0x%08x; firmware heartbeat started",
		  S31_WIRELESS_ABI_VERSION, S31_WIRELESS_REGION_BASE);
	return ESP_OK;
}
