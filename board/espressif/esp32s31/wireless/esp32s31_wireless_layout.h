/* SPDX-License-Identifier: GPL-2.0-only OR Apache-2.0 */
#ifndef ESP32S31_WIRELESS_LAYOUT_H
#define ESP32S31_WIRELESS_LAYOUT_H

#include "esp32s31_wireless_abi.h"

/* Function-CoreBoard internal HP SRAM ownership during split-core operation. */
#define S31_GMAC_DMA_BASE              0x2f030000U
#define S31_GMAC_DMA_SIZE              0x00010000U
#define S31_WIRELESS_REGION_BASE       0x2f040000U

#define S31_GMAC_DMA_END               (S31_GMAC_DMA_BASE + S31_GMAC_DMA_SIZE)
#define S31_WIRELESS_REGION_END        \
	(S31_WIRELESS_REGION_BASE + S31_WIRELESS_REGION_SIZE)

_Static_assert(S31_GMAC_DMA_END <= S31_WIRELESS_REGION_BASE,
	       "GMAC DMA and wireless transport overlap");
_Static_assert((S31_GMAC_DMA_BASE & 0xfffU) == 0U,
	       "GMAC DMA reservation must be page aligned");
_Static_assert((S31_WIRELESS_REGION_BASE & 0xfffU) == 0U,
	       "wireless transport must be page aligned");

#endif /* ESP32S31_WIRELESS_LAYOUT_H */
