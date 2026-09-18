# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
include $(sort $(wildcard $(BR2_EXTERNAL_MYD_YF135_PATH)/package/*/*.mk))

# Parent DT: a superproject may provide
#   board/dts/parent-linux.dtsi          Linux DT additions
#   board/dts/parent-u-boot.dtsi   U-Boot control DT additions
# See wiki: Parent Integration / Parent device tree docs
DBL_PARENT_DTS_DIRS := $(foreach name,$(filter-out MYD_YF135,$(BR2_EXTERNAL_NAMES)),\
	$(BR2_EXTERNAL_$(name)_PATH)/board/dts)
DBL_PARENT_LINUX_DTSI := $(wildcard $(addsuffix /parent-linux.dtsi,$(DBL_PARENT_DTS_DIRS)))
DBL_PARENT_UBOOT_DTSI := $(wildcard $(addsuffix /parent-u-boot.dtsi,$(DBL_PARENT_DTS_DIRS)))

ifneq ($(word 2,$(DBL_PARENT_LINUX_DTSI)),)
$(error multiple externals provide parent-linux.dtsi: $(DBL_PARENT_LINUX_DTSI))
endif
ifneq ($(word 2,$(DBL_PARENT_UBOOT_DTSI)),)
$(error multiple externals provide parent-u-boot.dtsi: $(DBL_PARENT_UBOOT_DTSI))
endif

# Copied after the defconfig's stub entry: same basename, later copy wins
UBOOT_CUSTOM_DTS_PATH += $(DBL_PARENT_UBOOT_DTSI)

# Copy the board DTS into the kernel source tree before each build, and append
# the dtb to the ST Makefile at first extraction.
#
# CUSTOM_DTS_PATH would normally be used, but copies to arch/arm/boot/dts/.
# Linux 6.12+ refactored STM32MP device trees to arch/arm/boot/dts/st/, which
# is incompatible with that standard method.
#
# PRE_BUILD (not POST_PATCH) so DTS edits propagate to the kernel build dir on
# every `make` without needing linux-dirclean. Mainline 6.12 already ships its
# own stm32mp135d-myd-yf135.dts upstream; this overwrites it with our copy.
define LINUX_MYD_YF135_COPY_DTS
	cp $(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/dts/stm32mp135d-myd-yf135.dts \
		$(@D)/arch/arm/boot/dts/st/stm32mp135d-myd-yf135.dts
	cp $(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/dts/parent-linux.dtsi \
		$(@D)/arch/arm/boot/dts/st/parent-linux.dtsi
	$(if $(DBL_PARENT_LINUX_DTSI),cp $(DBL_PARENT_LINUX_DTSI) \
		$(@D)/arch/arm/boot/dts/st/parent-linux.dtsi)
	grep -q 'stm32mp135d-myd-yf135\.dtb' $(@D)/arch/arm/boot/dts/st/Makefile || \
		printf '\ndtb-$$(CONFIG_ARCH_STM32) += stm32mp135d-myd-yf135.dtb\n' \
			>> $(@D)/arch/arm/boot/dts/st/Makefile
endef
LINUX_PRE_BUILD_HOOKS += LINUX_MYD_YF135_COPY_DTS

# Companion UBI volume images. Built as direct make rules wired into
# rootfs.ubi's prerequisites, so make ensures they exist before ubinize
# packs the .ubi file. Sizes and names must match ubinize.cfg (single
# source of truth: ubinize_check.py).
#
# overlay.ubifs   empty UBIFS, mounted as overlayfs upper at runtime
# optee_ss.ubifs  empty UBIFS, populated by OP-TEE on first use

# Empty UBIFS images (mkfs.ubifs creates an empty fs).
$(BINARIES_DIR)/overlay.ubifs: | host-mtd
	$(HOST_DIR)/sbin/mkfs.ubifs -m 2048 -e 126976 -c 630 -o $@

$(BINARIES_DIR)/optee_ss.ubifs: | host-mtd
	$(HOST_DIR)/sbin/mkfs.ubifs -m 2048 -e 126976 -c 34 -o $@

# U-Boot env binary, redundant variant. BR2_TARGET_UBOOT_ENVIMAGE does not
# pass -r to mkenvimage; CONFIG_SYS_REDUNDAND_ENVIRONMENT requires the flag
# byte -r emits, otherwise U-Boot CRC fails. Same image goes into UBI
# volumes env-a and env-b at flash time (see ubinize.cfg); both start
# ACTIVE, U-Boot picks the primary, first saveenv flips the secondary.
# Size must match CONFIG_ENV_SIZE in uboot.config.
$(BINARIES_DIR)/uboot.env: $(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/default-env.env | host-uboot-tools
	$(HOST_DIR)/bin/mkenvimage -s 0x4000 -r -o $@ $<

# Wire companion images into rootfs.ubi's prereqs so make builds them
# before ubinize. Recipe stays in fs/ubi/ubi.mk; we only add deps here.
$(BINARIES_DIR)/rootfs.ubi: \
	$(BINARIES_DIR)/overlay.ubifs \
	$(BINARIES_DIR)/optee_ss.ubifs \
	$(BINARIES_DIR)/uboot.env

# Project version derived from dbl-buildroot git state at build. Sets:
#   - U-Boot binary, via localversion -> CONFIG_VERSION_VARIABLE
#   - Rootfs /etc/firmware/expected-bl33-version (e.g for verify-bl33-version)
MYD_YF135_VERSION := $(shell cd $(BR2_EXTERNAL_MYD_YF135_PATH) && \
	git describe --always --dirty --tags 2>/dev/null || echo unknown)

define UBOOT_MYD_YF135_LOCALVERSION
	printf -- '-%s\n' "$(MYD_YF135_VERSION)" > $(@D)/localversion
endef
UBOOT_PRE_BUILD_HOOKS += UBOOT_MYD_YF135_LOCALVERSION

define MYD_YF135_EXPECTED_BL33_VERSION
	mkdir -p $(TARGET_DIR)/etc/firmware
	printf '%s\n' "$(MYD_YF135_VERSION)" \
		> $(TARGET_DIR)/etc/firmware/expected-bl33-version
endef
TARGET_FINALIZE_HOOKS += MYD_YF135_EXPECTED_BL33_VERSION
