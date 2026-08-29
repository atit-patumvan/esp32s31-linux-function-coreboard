# ESP32-S31 rootfs is limited to a 4 MiB flash slot. Keep curl focused on the
# HTTP(S) cloud-gateway use case and use the compact generated CA bundle.
ifeq ($(BR2_PACKAGE_LIBCURL_MBEDTLS),y)
LIBCURL_CONF_OPTS += \
	--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
	--disable-ftp \
	--disable-file \
	--disable-ipfs \
	--disable-mqtt \
	--disable-alt-svc \
	--disable-hsts \
	--disable-unix-sockets \
	--disable-socketpair \
	--disable-doh \
	--disable-mime \
	--disable-bindlocal \
	--disable-form-api \
	--disable-dateparse \
	--disable-netrc \
	--disable-headers-api \
	--disable-digest-auth \
	--disable-kerberos-auth \
	--disable-negotiate-auth \
	--disable-sha512-256 \
	--disable-dnsshuffle
endif

define S31_MBEDTLS_MINIMAL_CLIENT_CONFIG
	$(SED) '/^#define MBEDTLS_ARIA_C$$/d' \
		-e '/^#define MBEDTLS_CAMELLIA_C$$/d' \
		-e '/^#define MBEDTLS_DES_C$$/d' \
		-e '/^#define MBEDTLS_DHM_C$$/d' \
		-e '/^#define MBEDTLS_KEY_EXCHANGE_DHE_PSK_ENABLED$$/d' \
		-e '/^#define MBEDTLS_KEY_EXCHANGE_DHE_RSA_ENABLED$$/d' \
		-e '/^#define MBEDTLS_ECJPAKE_C$$/d' \
		-e '/^#define MBEDTLS_LMS_C$$/d' \
		-e '/^#define MBEDTLS_MD5_C$$/d' \
		-e '/^#define MBEDTLS_NIST_KW_C$$/d' \
		-e '/^#define MBEDTLS_RIPEMD160_C$$/d' \
		-e '/^#define MBEDTLS_SSL_CACHE_C$$/d' \
		-e '/^#define MBEDTLS_SSL_COOKIE_C$$/d' \
		-e '/^#define MBEDTLS_SSL_SRV_C$$/d' \
		-e '/^#define MBEDTLS_SSL_PROTO_TLS1_3$$/d' \
		-e '/^#define MBEDTLS_SSL_TLS1_3_/d' \
		-e '/^#define MBEDTLS_ECP_DP_SECP192R1_ENABLED$$/d' \
		-e '/^#define MBEDTLS_ECP_DP_SECP224R1_ENABLED$$/d' \
		-e '/^#define MBEDTLS_ECP_DP_SECP521R1_ENABLED$$/d' \
		-e '/^#define MBEDTLS_ECP_DP_SECP192K1_ENABLED$$/d' \
		-e '/^#define MBEDTLS_ECP_DP_SECP224K1_ENABLED$$/d' \
		-e '/^#define MBEDTLS_ECP_DP_SECP256K1_ENABLED$$/d' \
		-e '/^#define MBEDTLS_ECP_DP_BP256R1_ENABLED$$/d' \
		-e '/^#define MBEDTLS_ECP_DP_BP384R1_ENABLED$$/d' \
		-e '/^#define MBEDTLS_ECP_DP_BP512R1_ENABLED$$/d' \
		-e '/^#define MBEDTLS_ECP_DP_CURVE448_ENABLED$$/d' \
		$(@D)/include/mbedtls/mbedtls_config.h
endef
MBEDTLS_POST_PATCH_HOOKS += S31_MBEDTLS_MINIMAL_CLIENT_CONFIG
