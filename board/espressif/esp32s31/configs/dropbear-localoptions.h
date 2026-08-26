/* SPDX-License-Identifier: MIT */
/* The board image permits SSH access only with an authorized public key. */
#define DROPBEAR_SVR_PASSWORD_AUTH 0
#define DROPBEAR_SVR_PUBKEY_AUTH 1
#define DISABLE_UTMP 1

/* Avoid expensive first-boot host-key generation on the 300 MHz RV32 core. */
#define DROPBEAR_RSA 0
#define DROPBEAR_ECDSA 0
