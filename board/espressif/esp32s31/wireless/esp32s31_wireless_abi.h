/* SPDX-License-Identifier: GPL-2.0-only OR Apache-2.0 */
#ifndef ESP32S31_WIRELESS_ABI_H
#define ESP32S31_WIRELESS_ABI_H

/*
 * Shared ABI between the ESP-IDF wireless service and Linux.
 *
 * The transport address is supplied by the boot firmware/device tree.  It is
 * intentionally not part of this ABI.  Both endpoints are RV32 little-endian.
 * Writers publish a completed slot by advancing producer with a release
 * barrier; readers acquire producer before inspecting the slot.
 */

#ifdef __KERNEL__
#include <linux/types.h>
typedef __u8 s31_u8;
typedef __u16 s31_u16;
typedef __u32 s31_u32;
#else
#include <stdint.h>
typedef uint8_t s31_u8;
typedef uint16_t s31_u16;
typedef uint32_t s31_u32;
#endif

#define S31_WIRELESS_MAGIC             0x57313353U /* "S31W" */
#define S31_WIRELESS_ABI_VERSION       1U
#define S31_WIRELESS_REGION_SIZE       0x00010000U
#define S31_WIRELESS_CONTROL_SIZE      0x00001000U
#define S31_WIRELESS_CACHELINE_SIZE    64U
#define S31_WIRELESS_SLOT_SIZE         2048U
#define S31_WIRELESS_SLOT_COUNT        8U
#define S31_WIRELESS_SLOT_DATA_SIZE    (S31_WIRELESS_SLOT_SIZE - 16U)

#define S31_WIRELESS_FEAT_WIFI         (1U << 0)
#define S31_WIRELESS_FEAT_BLE          (1U << 1)
#define S31_WIRELESS_FEAT_BT_CLASSIC   (1U << 2)
#define S31_WIRELESS_FEAT_COEX         (1U << 3)

#define S31_WIRELESS_ENDPOINT_OFFLINE  0U
#define S31_WIRELESS_ENDPOINT_READY    1U

enum s31_wireless_channel {
	S31_WIRELESS_CH_CONTROL = 0,
	S31_WIRELESS_CH_WIFI_STA,
	S31_WIRELESS_CH_WIFI_AP,
	S31_WIRELESS_CH_BT_HCI,
	S31_WIRELESS_CH_LOG,
	S31_WIRELESS_CH_COUNT,
};

enum s31_wireless_control_type {
	S31_WIRELESS_CTRL_HELLO = 1,
	S31_WIRELESS_CTRL_HELLO_ACK,
	S31_WIRELESS_CTRL_WIFI_SCAN,
	S31_WIRELESS_CTRL_WIFI_SCAN_RESULT,
	S31_WIRELESS_CTRL_WIFI_CONNECT,
	S31_WIRELESS_CTRL_WIFI_DISCONNECT,
	S31_WIRELESS_CTRL_WIFI_LINK,
	S31_WIRELESS_CTRL_HEALTH,
	S31_WIRELESS_CTRL_RESET,
};

enum s31_wireless_link_state {
	S31_WIRELESS_LINK_DOWN = 0,
	S31_WIRELESS_LINK_ASSOCIATING,
	S31_WIRELESS_LINK_UP,
};

struct s31_wireless_ring_state {
	volatile s31_u32 producer;
	s31_u8 producer_pad[S31_WIRELESS_CACHELINE_SIZE - sizeof(s31_u32)];
	volatile s31_u32 consumer;
	s31_u8 consumer_pad[S31_WIRELESS_CACHELINE_SIZE - sizeof(s31_u32)];
};

struct s31_wireless_firmware_state {
	volatile s31_u32 ready;
	volatile s31_u32 heartbeat;
	volatile s31_u32 generation;
	volatile s31_u32 features;
	volatile s31_u32 link_state;
	volatile s31_u32 errors;
	s31_u8 sta_mac[6];
	s31_u8 bt_mac[6];
	s31_u8 reserved0[28];
};

struct s31_wireless_linux_state {
	volatile s31_u32 ready;
	volatile s31_u32 heartbeat;
	volatile s31_u32 errors;
	s31_u8 reserved0[52];
};

struct s31_wireless_control {
	s31_u32 magic;
	s31_u16 abi_version;
	s31_u16 control_size;
	s31_u32 region_size;
	s31_u8 reserved0[S31_WIRELESS_CACHELINE_SIZE - 12U];
	struct s31_wireless_firmware_state firmware;
	struct s31_wireless_linux_state host;
	struct s31_wireless_ring_state firmware_to_linux;
	struct s31_wireless_ring_state linux_to_firmware;
};

struct s31_wireless_slot {
	s31_u16 length;
	s31_u8 channel;
	s31_u8 flags;
	s31_u32 sequence;
	s31_u32 reserved0;
	s31_u32 reserved1;
	s31_u8 data[S31_WIRELESS_SLOT_DATA_SIZE];
};

#define S31_WIRELESS_F2L_OFFSET S31_WIRELESS_CONTROL_SIZE
#define S31_WIRELESS_L2F_OFFSET \
	(S31_WIRELESS_F2L_OFFSET + \
	 S31_WIRELESS_SLOT_COUNT * S31_WIRELESS_SLOT_SIZE)
#define S31_WIRELESS_USED_SIZE \
	(S31_WIRELESS_L2F_OFFSET + \
	 S31_WIRELESS_SLOT_COUNT * S31_WIRELESS_SLOT_SIZE)

_Static_assert(sizeof(struct s31_wireless_ring_state) == 128,
	       "wireless ring state must occupy two cache lines");
_Static_assert(sizeof(struct s31_wireless_firmware_state) == 64,
	       "firmware state must occupy one cache line");
_Static_assert(sizeof(struct s31_wireless_linux_state) == 64,
	       "Linux state must occupy one cache line");
_Static_assert(sizeof(struct s31_wireless_control) <= S31_WIRELESS_CONTROL_SIZE,
	       "wireless control block exceeds its reservation");
_Static_assert(sizeof(struct s31_wireless_slot) == S31_WIRELESS_SLOT_SIZE,
	       "wireless slot ABI changed");
_Static_assert(S31_WIRELESS_USED_SIZE <= S31_WIRELESS_REGION_SIZE,
	       "wireless rings exceed the shared-memory region");

#endif /* ESP32S31_WIRELESS_ABI_H */
