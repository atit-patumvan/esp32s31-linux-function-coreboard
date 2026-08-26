/* SPDX-License-Identifier: Apache-2.0 */
#include <stddef.h>
#include <stdio.h>

#include "esp32s31_wireless_abi.h"

int main(void)
{
	printf("abi=%u control=%zu slot=%zu f2l=0x%x l2f=0x%x used=0x%x\n",
	       S31_WIRELESS_ABI_VERSION,
	       sizeof(struct s31_wireless_control),
	       sizeof(struct s31_wireless_slot),
	       S31_WIRELESS_F2L_OFFSET,
	       S31_WIRELESS_L2F_OFFSET,
	       S31_WIRELESS_USED_SIZE);
	return 0;
}
