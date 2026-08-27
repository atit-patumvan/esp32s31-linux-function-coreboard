// SPDX-License-Identifier: GPL-2.0-only
/* Minimal Bluetooth Management API power control for hci0. */
#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define BTPROTO_HCI 1
#define HCI_CHANNEL_CONTROL 3
#define HCI_DEV_NONE 0xffff
#define MGMT_OP_SET_POWERED 0x0005
#define MGMT_EV_CMD_COMPLETE 0x0001
#define MGMT_EV_CMD_STATUS 0x0002

struct sockaddr_hci {
	sa_family_t family;
	uint16_t dev;
	uint16_t channel;
};

static uint16_t get_le16(const uint8_t *data)
{
	return data[0] | ((uint16_t)data[1] << 8);
}

static void put_le16(uint8_t *data, uint16_t value)
{
	data[0] = value & 0xff;
	data[1] = value >> 8;
}

static int set_powered(int fd, uint8_t powered)
{
	uint8_t command[7];
	uint8_t event[64];
	struct pollfd poll_fd = { .fd = fd, .events = POLLIN };
	int tries;

	put_le16(command, MGMT_OP_SET_POWERED);
	put_le16(command + 2, 0);
	put_le16(command + 4, 1);
	command[6] = powered;
	if (write(fd, command, sizeof(command)) != sizeof(command))
		return -1;
	for (tries = 0; tries < 10; tries++) {
		ssize_t length;
		int ret;

		do {
			ret = poll(&poll_fd, 1, 1000);
		} while (ret < 0 && errno == EINTR);
		if (ret <= 0)
			continue;
		do {
			length = read(fd, event, sizeof(event));
		} while (length < 0 && errno == EINTR);
		if (length < 9 || get_le16(event + 2) != 0 ||
		    (get_le16(event) != MGMT_EV_CMD_COMPLETE &&
		     get_le16(event) != MGMT_EV_CMD_STATUS) ||
		    get_le16(event + 6) != MGMT_OP_SET_POWERED)
			continue;
		if (event[8]) {
			fprintf(stderr, "Bluetooth management status 0x%02x\n",
				event[8]);
			errno = EIO;
			return -1;
		}
		return 0;
	}
	errno = ETIMEDOUT;
	return -1;
}

int main(int argc, char **argv)
{
	struct sockaddr_hci address = {
		.family = AF_BLUETOOTH,
		.dev = HCI_DEV_NONE,
		.channel = HCI_CHANNEL_CONTROL,
	};
	uint8_t powered;
	int fd;

	if (argc != 2 || (strcmp(argv[1], "on") && strcmp(argv[1], "off"))) {
		fprintf(stderr, "Usage: %s {on|off}\n", argv[0]);
		return 2;
	}
	powered = !strcmp(argv[1], "on");
	fd = socket(AF_BLUETOOTH, SOCK_RAW, BTPROTO_HCI);
	if (fd < 0 || bind(fd, (struct sockaddr *)&address, sizeof(address))) {
		perror("open Bluetooth management socket");
		if (fd >= 0)
			close(fd);
		return 1;
	}
	if (set_powered(fd, powered)) {
		perror("set Bluetooth power");
		close(fd);
		return 1;
	}
	printf("hci0 powered %s\n", powered ? "on" : "off");
	close(fd);
	return 0;
}
