/* SPDX-License-Identifier: Apache-2.0 */
#ifndef S31_TRANSPORT_H
#define S31_TRANSPORT_H

#include <stdint.h>

#include "esp_err.h"

esp_err_t s31_transport_start(const uint8_t sta_mac[6]);

#endif /* S31_TRANSPORT_H */
