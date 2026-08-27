# Makefile for ESP32-S31 Linux

TOOLCHAIN_DIR := $(CURDIR)/toolchain
CROSSTOOL_NG_DIR ?= $(abspath $(CURDIR)/../crosstool-NG)
CROSSTOOL_CONFIG := $(CURDIR)/configs/riscv32-esp-linux-musl.config
TOOLCHAIN_PREFIX := $(TOOLCHAIN_DIR)/riscv32-esp-linux-musl
TOOLCHAIN_TUPLE ?= riscv32-esp-linux-musl
TOOLCHAIN_RELEASE_TAG ?= latest
TOOLCHAIN_RELEASE_ASSET := riscv32-esp-linux-musl.tar.xz
TOOLCHAIN_RELEASE_REPOSITORY ?= GrieferPig/crosstool-NG-s31
TOOLCHAIN_RELEASE_API ?= https://api.github.com/repos/$(TOOLCHAIN_RELEASE_REPOSITORY)/releases/latest
TOOLCHAIN_RELEASE_DOWNLOAD_BASE ?= https://github.com/$(TOOLCHAIN_RELEASE_REPOSITORY)/releases/download
CROSS_COMPILE := $(TOOLCHAIN_PREFIX)/bin/$(TOOLCHAIN_TUPLE)-
CC := $(CROSS_COMPILE)gcc
CPP := $(CROSS_COMPILE)cpp
DTC := dtc
JOBS ?= $(shell nproc)

# Xesploop is available to normal userspace on both HP harts.  XespV exists
# only on hart 1, so keep it out of the global compiler ISA and expose it
# through libesp-simd, whose initializer pins users to hart 1 before executing
# vector instructions.  Kernel and firmware code must remain integer-safe.
S31_SAFE_ISA := rv32imacb_zicsr_zifencei_zaamo_zalrsc_zba_zbb_zbc_zbs
S31_KERNEL_ISA := rv32imafcb_zicsr_zifencei_zaamo_zalrsc_zba_zbb_zbc_zbs
S31_USER_ISA := rv32imafcb_zicsr_zifencei_zaamo_zalrsc_zba_zbb_zbc_zbs
S31_COMMON_FLAGS := -mabi=ilp32
S31_KERNEL_FLAGS := -mabi=ilp32f
S31_USER_FLAGS := -march=$(S31_USER_ISA) $(S31_COMMON_FLAGS)

BUILD_DIR := $(CURDIR)/build
OPENSBI_DIR := $(CURDIR)/opensbi-esp32-s31
LINUX_DIR := $(CURDIR)/linux-esp32-s31
UBOOT_DIR := $(CURDIR)/u-boot-esp32-s31
BOOTLOADER_DIR := $(CURDIR)/bootloader
BUILDROOT_DIR := $(CURDIR)/buildroot
BUILDROOT_EXTERNAL := $(CURDIR)/buildroot-external

# Out-of-tree build dirs
OPENSBI_OUT := $(BUILD_DIR)/opensbi-uboot-minimal
LINUX_OUT := $(BUILD_DIR)/linux-6.18
UBOOT_OUT := $(BUILD_DIR)/u-boot
BUILDROOT_OUT := $(BUILD_DIR)/buildroot
BUILDROOT_DL_DIR := $(BUILD_DIR)/buildroot-dl
COREMARK_OUT := $(BUILD_DIR)/coremark
COREMARK_BIN := $(COREMARK_OUT)/coremark.exe
TOOLCHAIN_ARCHIVE := $(BUILD_DIR)/downloads/$(TOOLCHAIN_RELEASE_ASSET)

S31_LAYOUT_CFG := $(CURDIR)/configs/esp32s31-layout.cfg

FW_PAYLOAD := $(BUILD_DIR)/fw_payload.bin
XIP_IMAGE := $(BUILD_DIR)/xipImage
UBOOT_ITB := $(BUILD_DIR)/u-boot.itb
UBOOT_SPL_DTB := $(BUILD_DIR)/u-boot-spl-dtb.bin
SPL_APP_BIN := $(BUILD_DIR)/spl_app.bin
ROOTFS_IMG := $(BUILD_DIR)/rootfs.sqfs
PERSIST_IMG := $(BUILD_DIR)/persist.jffs2

IDF_ROOT ?= $(HOME)/.espressif
# Keep the ESP-IDF dependency local to its installation root.  The master
# checkout is preferred, with an installed alternate accepted as a fallback.
IDF_EXPORT ?= $(firstword $(wildcard $(IDF_ROOT)/master/esp-idf/export.sh) $(wildcard $(IDF_PATH)/export.sh) $(shell find $(IDF_ROOT) -maxdepth 5 -type f -path '*/esp-idf/export.sh' 2>/dev/null | sort | head -n 1))

.PHONY: all download toolchain toolchain-source idf-check opensbi uboot flash-image radio-linux-payload radio-bootloader radio-image linux coremark rootfs initramfs s31-pie-cases layout-check \
	buildroot-menuconfig buildroot-clean clean fullclean flash-opensbi flash-linux \
	flash-dtb flash-rootfs persist flash-persist bootloader flash-bootloader flash-all erase

all: toolchain download uboot linux rootfs flash-image

$(BUILD_DIR) $(OPENSBI_OUT) $(LINUX_OUT) $(UBOOT_OUT) $(BUILDROOT_OUT) $(COREMARK_OUT):
	mkdir -p $@

download: toolchain
	@echo "--- Download ---"
	git submodule update --init --recursive

toolchain: | $(BUILD_DIR)
	@set -eu; \
	if [ -x "$(CC)" ] && [ "$(TOOLCHAIN_RELEASE_TAG)" = latest ]; then \
		echo "Using installed toolchain at $(TOOLCHAIN_PREFIX)"; \
		exit 0; \
	fi; \
	mkdir -p "$(dir $(TOOLCHAIN_ARCHIVE))" "$(TOOLCHAIN_DIR)"; \
	release_tag="$(TOOLCHAIN_RELEASE_TAG)"; \
	if [ "$$release_tag" = latest ]; then \
		release_tag=$$(curl --fail --location --retry 3 --silent --show-error "$(TOOLCHAIN_RELEASE_API)" | sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p'); \
	fi; \
	if [ -z "$$release_tag" ]; then \
		echo "ERROR: failed to resolve the latest toolchain release tag" >&2; exit 1; \
	fi; \
	release_url="$(TOOLCHAIN_RELEASE_DOWNLOAD_BASE)/$$release_tag/$(TOOLCHAIN_RELEASE_ASSET)"; \
	release_sha256_url="$$release_url.sha256"; \
	installed_tag=$$(cat "$(TOOLCHAIN_PREFIX)/.release" 2>/dev/null || true); \
	if [ -z "$$installed_tag" ] && [ -d "$(TOOLCHAIN_PREFIX)" ]; then \
		installed_tag=$$(find "$(TOOLCHAIN_PREFIX)" -maxdepth 1 -type f -name '.release-*' -printf '%f\n' 2>/dev/null | sed 's/^\.release-//' | head -n 1); \
	fi; \
	if [ "$$installed_tag" = "$$release_tag" ]; then \
		echo "Toolchain release $$release_tag is already installed"; \
		exit 0; \
	fi; \
	echo "Installing toolchain release $$release_tag"; \
	curl --fail --location --retry 3 --output "$(TOOLCHAIN_ARCHIVE).part" "$$release_url"; \
	curl --fail --location --retry 3 --output "$(TOOLCHAIN_ARCHIVE).sha256.part" "$$release_sha256_url"; \
	expected_hash=$$(awk 'NR == 1 { print $$1; exit }' "$(TOOLCHAIN_ARCHIVE).sha256.part"); \
	printf '%s\n' "$$expected_hash" | grep -Eq '^[0-9a-fA-F]{64}$$' || { echo "ERROR: invalid release checksum" >&2; exit 1; }; \
	printf '%s  %s\n' "$$expected_hash" "$(TOOLCHAIN_ARCHIVE).part" | sha256sum --check -; \
	mv "$(TOOLCHAIN_ARCHIVE).part" "$(TOOLCHAIN_ARCHIVE)"; \
	rm -f "$(TOOLCHAIN_ARCHIVE).sha256.part"; \
	staging=$$(mktemp -d "$(TOOLCHAIN_DIR)/.riscv32-esp-linux-musl.XXXXXX"); \
	trap 'chmod -R u+w "$$staging" 2>/dev/null || true; rm -rf "$$staging"' EXIT; \
	tar -xJf "$(TOOLCHAIN_ARCHIVE)" -C "$$staging"; \
	test -x "$$staging/bin/riscv32-esp-linux-musl-gcc"; \
	printf '%s\n' "$$release_tag" > "$$staging/.release"; \
	printf '%s\n' "$$release_tag" > "$$staging/.release-$$release_tag"; \
	chmod u-w "$$staging"; \
	if [ -e "$(TOOLCHAIN_PREFIX)" ]; then \
		backup="$(TOOLCHAIN_PREFIX).previous.$$(date -u +%Y%m%d%H%M%S)"; \
		mv "$(TOOLCHAIN_PREFIX)" "$$backup"; \
		echo "Previous toolchain retained at $$backup"; \
	fi; \
	mv "$$staging" "$(TOOLCHAIN_PREFIX)"; \
	trap - EXIT; \
	"$(CC)" --version | head -n 1

toolchain-source:
	python3 $(CURDIR)/build_linux_toolchain.py --ct-ng-dir "$(CROSSTOOL_NG_DIR)" --jobs "$(JOBS)" --force

# The FIT's fixed 0x400 external-data position places OpenSBI at the
# 64-byte-aligned NOR XIP address 0x40000400.  Only writable state lives in
# coherent HP SRAM, leaving the retired loader area available to the radio.
FW_TEXT_START ?= 0x40000400
FW_RW_START ?= 0x2F00F000
# SV32 XIP uses a 4-MiB leaf/megapage boundary.
LINUX_XIP_ADDR ?= 0x40400000
FW_JUMP_ADDR ?= $(LINUX_XIP_ADDR)
OPENSBI_MAX_SIZE ?= 262144

FDT_SRC := $(LINUX_DIR)/arch/riscv/boot/dts/espressif/esp32s31_generic.dts
FDT_DTB := $(BUILD_DIR)/esp32s31_generic.dtb
OPENSBI_FW_JUMP_BIN := $(OPENSBI_OUT)/platform/generic/firmware/fw_jump.bin
OPENSBI_FW_DYNAMIC_BIN := $(OPENSBI_OUT)/platform/generic/firmware/fw_dynamic.bin
OPENSBI_CONFIG_STAMP := $(OPENSBI_OUT)/.s31-link-config

opensbi: toolchain | $(OPENSBI_OUT)
	@echo "--- OpenSBI ---"
	@set -eu; \
	desired='FW_TEXT_START=$(FW_TEXT_START) FW_RW_START=$(FW_RW_START) ISA=$(S31_SAFE_ISA)'; \
	actual=$$(cat "$(OPENSBI_CONFIG_STAMP)" 2>/dev/null || true); \
	if [ "$$actual" != "$$desired" ]; then \
		echo "OpenSBI link configuration changed; rebuilding its output tree"; \
	$(MAKE) -C $(OPENSBI_DIR) O=$(OPENSBI_OUT) clean; \
	mkdir -p "$(OPENSBI_OUT)"; \
	printf '%s\n' "$$desired" > "$(OPENSBI_CONFIG_STAMP)"; \
	fi
	$(MAKE) -C $(OPENSBI_DIR) O=$(OPENSBI_OUT) \
		CROSS_COMPILE="$(CROSS_COMPILE)" \
		PLATFORM=generic \
		PLATFORM_DEFCONFIG=esp32s31_defconfig \
		PLATFORM_RISCV_XLEN=32 \
		PLATFORM_RISCV_ISA=$(S31_SAFE_ISA) \
		FW_TEXT_START=$(FW_TEXT_START) \
		FW_RW_START=$(FW_RW_START) \
		FW_DYNAMIC=y \
		-j$(JOBS)
	@size=$$(stat -c%s $(OPENSBI_FW_DYNAMIC_BIN)); \
	if [ $$size -gt $(OPENSBI_MAX_SIZE) ]; then \
		echo "ERROR: OpenSBI fw_dynamic ($$size bytes) overlaps SPL at 0x2f040000"; exit 1; \
	fi

uboot: idf-check opensbi | $(UBOOT_OUT)
	@echo "--- U-Boot SPL + proper ---"
	# ESP-IDF prepends its private Python environment to PATH.  Binman needs
	# the distro pkg_resources/pyelftools modules installed by the host, so keep
	# the system Python ahead of the IDF environment for the U-Boot build only.
	PATH="/usr/bin:/bin:$$PATH" $(MAKE) -C $(UBOOT_DIR) O=$(UBOOT_OUT) ARCH=riscv \
		CROSS_COMPILE="$(CROSS_COMPILE)" espressif_esp32s31_defconfig
	PATH="/usr/bin:/bin:$$PATH" $(MAKE) -C $(UBOOT_DIR) O=$(UBOOT_OUT) ARCH=riscv \
		CROSS_COMPILE="$(CROSS_COMPILE)" \
		OPENSBI=$(OPENSBI_FW_DYNAMIC_BIN) -j$(JOBS)
	cp -v $(UBOOT_OUT)/u-boot.itb $(UBOOT_ITB)
	cp -v $(UBOOT_OUT)/spl/u-boot-spl-dtb.bin $(UBOOT_SPL_DTB)
	@work=$$(mktemp -d "$(BUILD_DIR)/spl-wrap.XXXXXX"); \
	trap 'rm -rf "$$work"' EXIT; \
	$(CROSS_COMPILE)objcopy -I binary -O elf32-littleriscv -B riscv \
		$(UBOOT_SPL_DTB) "$$work/spl1.elf"; \
	$(CROSS_COMPILE)objcopy --change-section-address .data=0x2F040000 \
		--rename-section .data=.text,alloc,load,readonly,code,contents \
		--set-start 0x2F040000 "$$work/spl1.elf" "$$work/spl_wrapped.elf"; \
	bash -c "source $(IDF_EXPORT) >/dev/null && esptool --chip esp32s31 elf2image \
		--flash-mode dio --flash-freq 80m --flash-size 16MB \
		--output $(SPL_APP_BIN) $$work/spl_wrapped.elf"

RADIO_BOOT_BUILD := $(BOOTLOADER_DIR)/build-radio
RADIO_PARTITION_SIZE := 1966080
RADIO_PAYLOAD := $(BUILD_DIR)/radio-fw-payload.bin
S31_RADIO_BOOTLOADER_PREBUILT ?= 0
S31_RADIO_PAYLOAD_PREBUILT ?= 0

idf-check:
	@test -f "$(IDF_EXPORT)" || { echo "ERROR: ESP-IDF export.sh not found under $(IDF_ROOT)" >&2; exit 1; }

radio-bootloader: idf-check
	@echo "--- Build radio-only loader ---"
	@if [ "$(S31_RADIO_BOOTLOADER_PREBUILT)" = "1" ]; then \
		test -f "$(RADIO_BOOT_BUILD)/esp-idf/esp_wifi/libesp_wifi.a"; \
		test -f "$(RADIO_BOOT_BUILD)/esp-idf/bt/libbt.a"; \
		echo "Using prebuilt ESP-IDF radio libraries from $(RADIO_BOOT_BUILD)"; \
	else \
		bash -c "source $(IDF_EXPORT) && cd $(BOOTLOADER_DIR) && \
		S31_RADIO_DEPS=1 idf.py -B build-radio \
		-D SDKCONFIG=$(RADIO_BOOT_BUILD)/sdkconfig \
		-D 'SDKCONFIG_DEFAULTS=$(BOOTLOADER_DIR)/sdkconfig;$(BOOTLOADER_DIR)/sdkconfig.radio.defaults' \
		reconfigure build"; \
	fi

RADIO_LINUX_CMDLINE := console=ttyS0,115200n8 root=mtd:rootfs rootfstype=squashfs ro rootwait init=/init clk_ignore_unused

radio-image: LINUX_CMDLINE := $(RADIO_LINUX_CMDLINE)
radio-image: opensbi linux
	@set -eu; \
	RAW="$(BUILD_DIR)/radio-fw.raw"; \
	DTB="$(BUILD_DIR)/radio-esp32s31.dtb"; \
	cp "$(FDT_DTB)" "$$DTB"; \
	cp "$(OPENSBI_FW_JUMP_BIN)" "$$RAW"; \
	RAW_SIZE=$$(stat -c%s "$$RAW"); \
	FDT_OFFSET=$$(( (RAW_SIZE + 7) & ~7 )); \
	DTB_SIZE=$$(stat -c%s "$$DTB"); \
	MAX_PAYLOAD_SIZE=$$(( $(RADIO_PARTITION_SIZE) - 4 )); \
	if [ $$((FDT_OFFSET + DTB_SIZE)) -gt $$MAX_PAYLOAD_SIZE ]; then \
		echo "ERROR: OpenSBI + DTB exceeds expanded partition"; exit 1; \
	fi; \
	cp "$$RAW" "$(RADIO_PAYLOAD)"; \
	truncate -s $$FDT_OFFSET "$(RADIO_PAYLOAD)"; \
	cat "$$DTB" >> "$(RADIO_PAYLOAD)"; \
	truncate -s $$MAX_PAYLOAD_SIZE "$(RADIO_PAYLOAD)"; \
	printf '%08x' $$FDT_OFFSET | sed 's/../& /g' | \
		awk '{for (i=4;i>=1;i--) printf "%s", $$i}' | xxd -r -p >> "$(RADIO_PAYLOAD)"; \
	echo "Radio payload: $$((FDT_OFFSET + DTB_SIZE)) bytes used, FDT offset $$FDT_OFFSET"

DEFCONFIG ?= esp32s31_defconfig
LINUX_TARGET ?= xipImage
S31_WIFI_ONLY ?= 0
S31_USB_STORAGE ?= 0
# CMDLINE_FORCE replaces, rather than extends, the defconfig command line, so
# retain the rootfs and console arguments here as well.  Both HP harts start by
# default; normal device IRQs remain pinned to hart 0 via irqaffinity=0.
LINUX_CMDLINE ?= earlycon=esp32s31uart,mmio,0x2038a000,115200 console=ttyS0,115200n8 root=/dev/mtdblock5 rootfstype=squashfs ro rootwait init=/init clk_ignore_unused irqaffinity=0
LINUX_PARTITION_SIZE := 6291456

radio-linux-payload:
	@if [ "$(S31_RADIO_PAYLOAD_PREBUILT)" = "1" ]; then \
		test -s "$(LINUX_DIR)/drivers/platform/esp32s31-radio-idf.o_shipped"; \
		echo "Using prebuilt Linux radio payload"; \
	else \
		$(MAKE) --no-print-directory radio-bootloader; \
		$(MAKE) -C $(CURDIR)/radio_firmware IDF_ROOT="$(IDF_ROOT)" \
			S31_WIFI_ONLY="$(S31_WIFI_ONLY)" linux-kbuild; \
	fi

linux: toolchain radio-linux-payload layout-check | $(LINUX_OUT)
	@echo "--- Linux ---"
	$(MAKE) -C $(LINUX_DIR) O=$(LINUX_OUT) ARCH=riscv CROSS_COMPILE="$(CROSS_COMPILE)" $(DEFCONFIG)
	$(LINUX_DIR)/scripts/config --file $(LINUX_OUT)/.config \
		--disable BUILTIN_DTB \
		--enable RISCV_ISA_C \
		--disable RISCV_ISA_V \
		--disable RISCV_ISA_V_DEFAULT_ENABLE \
		--enable RISCV_ISA_ZBA \
		--enable RISCV_ISA_ZBB \
		--enable RISCV_ISA_ZBC \
		--enable BT \
		--enable BT_BREDR \
		--enable SMP \
		--set-val NR_CPUS 2 \
		--enable ESP32S31_COPROC_CONTEXT \
		--disable CSD_LOCK_WAIT_DEBUG \
		--disable CSD_LOCK_WAIT_DEBUG_DEFAULT \
		--enable PREEMPT_VOLUNTARY \
		--disable PREEMPT_NONE \
		--disable PREEMPT \
		--enable DMATEST \
		--enable HZ_100 \
		--disable HZ_250 \
		--disable HZ_300 \
		--disable HZ_1000
	@if [ "$(S31_USB_STORAGE)" = "1" ]; then \
		echo "Enabling experimental USB mass-storage support"; \
		$(LINUX_DIR)/scripts/config --file $(LINUX_OUT)/.config \
			--enable SCSI \
			--enable BLK_DEV_SD \
			--enable USB_STORAGE; \
	else \
		$(LINUX_DIR)/scripts/config --file $(LINUX_OUT)/.config \
			--disable USB_STORAGE; \
	fi
	@if [ "$(S31_WIFI_ONLY)" = "1" ]; then \
		$(LINUX_DIR)/scripts/config --file $(LINUX_OUT)/.config \
			--disable BT_ESP32S31; \
	else \
		$(LINUX_DIR)/scripts/config --file $(LINUX_OUT)/.config \
			--enable BT_ESP32S31; \
	fi
	@if [ -n "$(LINUX_CMDLINE)" ]; then \
		$(LINUX_DIR)/scripts/config --file $(LINUX_OUT)/.config \
			--set-str CMDLINE "$(LINUX_CMDLINE)"; \
	fi
	$(MAKE) -C $(LINUX_DIR) O=$(LINUX_OUT) ARCH=riscv CROSS_COMPILE="$(CROSS_COMPILE)" olddefconfig
	$(MAKE) -C $(LINUX_DIR) O=$(LINUX_OUT) ARCH=riscv CROSS_COMPILE="$(CROSS_COMPILE)" \
		KCFLAGS="-march=$(S31_KERNEL_ISA) $(S31_KERNEL_FLAGS)" -j$(JOBS) $(LINUX_TARGET) dtbs
	cp -v $(LINUX_OUT)/arch/riscv/boot/$(LINUX_TARGET) $(XIP_IMAGE)
	@size=$$(stat -c%s $(XIP_IMAGE)); \
	if [ $$size -gt $(LINUX_PARTITION_SIZE) ]; then \
		echo "ERROR: $(LINUX_TARGET) ($$size bytes) overlaps persist at 0xB00000"; exit 1; \
	fi
	cp -v $(LINUX_OUT)/arch/riscv/boot/dts/espressif/esp32s31_generic.dtb $(FDT_DTB)

coremark: rootfs | $(COREMARK_OUT)
	@test -x "$(BUILDROOT_OUT)/target/usr/bin/coremark"
	@mkdir -p "$(COREMARK_OUT)"
	@cp -v "$(BUILDROOT_OUT)/target/usr/bin/coremark" "$(COREMARK_BIN)"
	@echo "CoreMark: $(COREMARK_BIN)"

# Keep this decimal because POSIX test(1) and truncate(1) do not accept the
# partition table's 0x-prefixed value.
# Match configs/esp32s31-layout.cfg and the fixed partitions in
# esp32s31.dtsi.  The flash MTD starts at raw offset 0x100000, so its 0xa00000
# persist and 0xb00000 rootfs offsets correspond to raw 0xB00000 and
# 0xC00000.  Persist is exactly 1 MiB and rootfs occupies the final 4 MiB.
ROOTFS_PARTITION_SIZE ?= 4194304
PERSIST_PARTITION_SIZE ?= 1048576

layout-check:
	@set -eu; . "$(S31_LAYOUT_CFG)"; \
	kernel_size=$$((SLOT_PERSIST - SLOT_KERNEL)); \
	persist_size=$$((SLOT_ROOTFS - SLOT_PERSIST)); \
	rootfs_size=$$((FLASH_SIZE - SLOT_ROOTFS)); \
	test "$$kernel_size" -eq "$(LINUX_PARTITION_SIZE)" || { \
		echo "ERROR: kernel size disagrees with $(S31_LAYOUT_CFG)" >&2; exit 1; }; \
	test "$$persist_size" -eq "$(PERSIST_PARTITION_SIZE)" || { \
		echo "ERROR: persist size disagrees with $(S31_LAYOUT_CFG)" >&2; exit 1; }; \
	test "$$rootfs_size" -eq "$(ROOTFS_PARTITION_SIZE)" || { \
		echo "ERROR: rootfs size disagrees with $(S31_LAYOUT_CFG)" >&2; exit 1; }
BUILDROOT_MAKE = $(MAKE) -C $(BUILDROOT_DIR) O=$(BUILDROOT_OUT) \
	BR2_EXTERNAL=$(BUILDROOT_EXTERNAL) BR2_DL_DIR=$(BUILDROOT_DL_DIR) \
	S31_DTBO_DIR=$(LINUX_OUT)/arch/riscv/boot/dts/espressif \
	S31_TOOLCHAIN_PATH=$(TOOLCHAIN_PREFIX) \
	S31_TOOLCHAIN_TUPLE=$(notdir $(CROSS_COMPILE:%-=%))

s31-pie-cases:
	@$(MAKE) --no-print-directory idf-check
	bash -c "source $(IDF_EXPORT) >/dev/null && $(CURDIR)/rootfs/gen_s31_pie_cases.sh $(CURDIR)/rootfs/s31_pie_cases.inc"

rootfs: linux toolchain | $(BUILDROOT_OUT)
	@echo "--- Buildroot rootfs ---"
	$(BUILDROOT_MAKE) esp32s31_rootfs_defconfig
	$(BUILDROOT_MAKE) toolchain-external-custom-rebuild
	$(BUILDROOT_MAKE) toolchain-external-rebuild
	$(BUILDROOT_MAKE) s31-tools-rebuild
	$(BUILDROOT_MAKE)
	cp -v $(BUILDROOT_OUT)/images/rootfs.squashfs $(ROOTFS_IMG)
	@ROOTFS_SIZE=$$(stat -c%s $(ROOTFS_IMG)); \
	echo "Buildroot rootfs: $$ROOTFS_SIZE / $(ROOTFS_PARTITION_SIZE) bytes ($$(( $(ROOTFS_PARTITION_SIZE) - $$ROOTFS_SIZE )) bytes free)"; \
	if [ $$ROOTFS_SIZE -gt $(ROOTFS_PARTITION_SIZE) ]; then \
		echo "ERROR: Buildroot rootfs ($$ROOTFS_SIZE bytes) exceeds partition ($(ROOTFS_PARTITION_SIZE) bytes)"; \
		exit 1; \
	fi

# Historical/user-facing name for the root filesystem image.
initramfs: linux rootfs

# Generate an empty, NOR-compatible JFFS2 image for the persist partition.
# This is separate from normal firmware updates so user data is not erased.
persist: layout-check | $(BUILD_DIR)
	@command -v mkfs.jffs2 >/dev/null || { echo "ERROR: mkfs.jffs2 is required" >&2; exit 1; }
	@staging=$$(mktemp -d "$(BUILD_DIR)/persist.XXXXXX"); \
	trap 'rmdir "$$staging"' EXIT; \
	mkfs.jffs2 -q -e 0x2000 --pad=$(PERSIST_PARTITION_SIZE) \
		-d "$$staging" -o $(PERSIST_IMG)

buildroot-menuconfig: | $(BUILDROOT_OUT)
	$(BUILDROOT_MAKE) esp32s31_rootfs_defconfig
	$(BUILDROOT_MAKE) menuconfig

buildroot-clean:
	rm -rf $(BUILDROOT_OUT)

clean:
	rm -rf $(BUILD_DIR)

fullclean: clean
	@test ! -e $(TOOLCHAIN_DIR) || chmod -R u+w $(TOOLCHAIN_DIR)
	rm -rf $(TOOLCHAIN_DIR)

flash-image: uboot linux rootfs
	@echo "--- Merge official U-Boot flash layout ---"
	bash -c "source $(IDF_EXPORT) >/dev/null && \
		$(CURDIR)/tools/gen_esp_flash_image.sh $(S31_LAYOUT_CFG) $(BUILD_DIR)"

# OpenSBI is embedded in U-Boot's FIT at the official 0x100000 slot.
flash-opensbi: uboot
	bash -c "source $(S31_LAYOUT_CFG) && source $(IDF_EXPORT) >/dev/null && \
		esptool -p /dev/ttyUSB0 -b 2000000 write-flash \
		\$$SLOT_UBOOT_ITB $(UBOOT_ITB)"

flash-dtb: linux
	bash -c "source $(S31_LAYOUT_CFG) && source $(IDF_EXPORT) >/dev/null && \
		esptool -p /dev/ttyUSB0 -b 2000000 write-flash \$$SLOT_DTB $(FDT_DTB)"

flash-linux: linux
	bash -c "source $(S31_LAYOUT_CFG) && source $(IDF_EXPORT) >/dev/null && \
		esptool -p /dev/ttyUSB0 -b 2000000 write-flash \
		\$$SLOT_DTB $(FDT_DTB) \$$SLOT_KERNEL $(XIP_IMAGE)"

flash-rootfs: rootfs
	bash -c "source $(S31_LAYOUT_CFG) && source $(IDF_EXPORT) >/dev/null && \
		esptool -p /dev/ttyUSB0 -b 2000000 write-flash \$$SLOT_ROOTFS $(ROOTFS_IMG)"

flash-persist: persist
	bash -c "source $(S31_LAYOUT_CFG) && source $(IDF_EXPORT) >/dev/null && \
		esptool -p /dev/ttyUSB0 -b 2000000 write-flash \$$SLOT_PERSIST $(PERSIST_IMG)"

bootloader: uboot

flash-bootloader: uboot
	@echo "--- Flash U-Boot SPL + FIT ---"
	bash -c "source $(S31_LAYOUT_CFG) && source $(IDF_EXPORT) >/dev/null && \
		esptool -p /dev/ttyUSB0 -b 2000000 write-flash \
		\$$SLOT_SPL $(SPL_APP_BIN) \$$SLOT_UBOOT_ITB $(UBOOT_ITB)"

flash-all: uboot linux rootfs
	@echo "--- Flash complete U-Boot/Linux image (persist preserved) ---"
	bash -c "source $(S31_LAYOUT_CFG) && source $(IDF_EXPORT) >/dev/null && \
		esptool -p /dev/ttyUSB0 -b 2000000 write-flash \
		\$$SLOT_SPL $(SPL_APP_BIN) \
		\$$SLOT_UBOOT_ITB $(UBOOT_ITB) \
		\$$SLOT_DTB $(FDT_DTB) \
		\$$SLOT_KERNEL $(XIP_IMAGE) \
		\$$SLOT_ROOTFS $(ROOTFS_IMG)"

erase:
	bash -c "source $(IDF_EXPORT) >/dev/null && esptool -p /dev/ttyUSB0 -b 2000000 erase-flash"
