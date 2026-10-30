# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
include $(sort $(wildcard $(BR2_EXTERNAL_MYD_YF135_PATH)/package/*/*.mk))

# Parent DT, at most one external each:
#   board/dts/parent-linux.dtsi             Linux DT
#   board/dts/parent-u-boot.dtsi            U-Boot control DT
#   board/dts/parent-optee.dtsi             OP-TEE DT (security-critical)
#   board/dts/parent-tf-a.dtsi              TF-A BL2 DT (security-critical)
#   board/dts/parent-tf-a-fw-config.dtsi    TF-A load addresses / TZC (security-critical)
# See wiki: Parent Integration / Parent device tree docs
DBL_PARENT_DTS_DIRS := $(foreach name,$(filter-out MYD_YF135,$(BR2_EXTERNAL_NAMES)),\
	$(BR2_EXTERNAL_$(name)_PATH)/board/dts)
DBL_PARENT_LINUX_DTSI := $(wildcard $(addsuffix /parent-linux.dtsi,$(DBL_PARENT_DTS_DIRS)))
DBL_PARENT_UBOOT_DTSI := $(wildcard $(addsuffix /parent-u-boot.dtsi,$(DBL_PARENT_DTS_DIRS)))
DBL_PARENT_OPTEE_DTSI := $(wildcard $(addsuffix /parent-optee.dtsi,$(DBL_PARENT_DTS_DIRS)))
DBL_PARENT_TF_A_DTSI := $(wildcard $(addsuffix /parent-tf-a.dtsi,$(DBL_PARENT_DTS_DIRS)))
DBL_PARENT_TF_A_FW_CONFIG_DTSI := $(wildcard $(addsuffix /parent-tf-a-fw-config.dtsi,$(DBL_PARENT_DTS_DIRS)))

# Optional board/parent-u-boot.env from parent external, e.g. to set
# parent_boot_hook. Compiled into U-Boot: covered by verified boot.
DBL_PARENT_DIRS := $(foreach name,$(filter-out MYD_YF135,$(BR2_EXTERNAL_NAMES)),\
	$(BR2_EXTERNAL_$(name)_PATH)/board)
DBL_PARENT_UBOOT_ENV := $(wildcard $(addsuffix /parent-u-boot.env,$(DBL_PARENT_DIRS)))
ifneq ($(word 2,$(DBL_PARENT_UBOOT_ENV)),)
$(error multiple externals provide parent-u-boot.env: $(DBL_PARENT_UBOOT_ENV))
endif

ifneq ($(word 2,$(DBL_PARENT_LINUX_DTSI)),)
$(error multiple externals provide parent-linux.dtsi: $(DBL_PARENT_LINUX_DTSI))
endif
ifneq ($(word 2,$(DBL_PARENT_UBOOT_DTSI)),)
$(error multiple externals provide parent-u-boot.dtsi: $(DBL_PARENT_UBOOT_DTSI))
endif
ifneq ($(word 2,$(DBL_PARENT_OPTEE_DTSI)),)
$(error multiple externals provide parent-optee.dtsi: $(DBL_PARENT_OPTEE_DTSI))
endif
ifneq ($(word 2,$(DBL_PARENT_TF_A_DTSI)),)
$(error multiple externals provide parent-tf-a.dtsi: $(DBL_PARENT_TF_A_DTSI))
endif
ifneq ($(word 2,$(DBL_PARENT_TF_A_FW_CONFIG_DTSI)),)
$(error multiple externals provide parent-tf-a-fw-config.dtsi: $(DBL_PARENT_TF_A_FW_CONFIG_DTSI))
endif

# U-Boot compiles the base Linux dts as its control DT: provide the empty
# parent-linux.dtsi stub (Linux-only peripherals) and the parent's U-Boot file.
# Runs with the build step only: after DT edits, `make uboot-rebuild`.
define UBOOT_MYD_YF135_COPY_DTSI
	cp $(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/dts/parent-linux.dtsi \
		$(@D)/arch/arm/dts/parent-linux.dtsi
	cp $(or $(DBL_PARENT_UBOOT_DTSI),$(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/dts/parent-u-boot.dtsi) \
		$(@D)/arch/arm/dts/parent-u-boot.dtsi
endef
# OP-TEE and TF-A have their own source trees. Not via CUSTOM_DTS_PATH (that
# copy would overwrite the parent file with the stub).
define OPTEE_OS_MYD_YF135_COPY_DTSI
	cp $(or $(DBL_PARENT_OPTEE_DTSI),$(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/dts/parent-optee.dtsi) \
		$(@D)/core/arch/arm/dts/parent-optee.dtsi
endef
OPTEE_OS_PRE_BUILD_HOOKS += OPTEE_OS_MYD_YF135_COPY_DTSI

ifneq ($(BR2_PACKAGE_DBL_OTP_WRITE),y)
OPTEE_OS_MAKE_OPTS += CFG_STM32_BSEC_WRITE=n
endif

define ARM_TRUSTED_FIRMWARE_MYD_YF135_COPY_DTSI
	cp $(or $(DBL_PARENT_TF_A_DTSI),$(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/dts/parent-tf-a.dtsi) \
		$(@D)/fdts/parent-tf-a.dtsi
	cp $(or $(DBL_PARENT_TF_A_FW_CONFIG_DTSI),$(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/dts/parent-tf-a-fw-config.dtsi) \
		$(@D)/fdts/parent-tf-a-fw-config.dtsi
endef
ARM_TRUSTED_FIRMWARE_PRE_BUILD_HOOKS += ARM_TRUSTED_FIRMWARE_MYD_YF135_COPY_DTSI

UBOOT_PRE_BUILD_HOOKS += UBOOT_MYD_YF135_COPY_DTSI

# U-Boot env text, used for both uboot.env (flash) and compiled default env.
# Without CONFIG_ENV_WRITEABLE_LIST U-Boot uses compiled env only when flash
# env is invalid: flash must hold full script.
# Append uboot-env-flags.txt only with CONFIG_ENV_WRITEABLE_LIST. Without it,
# U-Boot warns on unknown "w" flag.
# After env edits run `make uboot-rebuild`
DBL_UBOOT_ENV_FILES := \
	$(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/default-env.env \
	$(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/uboot-env.txt \
	$(DBL_PARENT_UBOOT_ENV)
define UBOOT_MYD_YF135_DEFAULT_ENV
	cat $(DBL_UBOOT_ENV_FILES) > $(@D)/dbl-default-env.txt
	if grep -q '^CONFIG_ENV_WRITEABLE_LIST=y' $(@D)/.config; then \
		cat $(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/uboot-env-flags.txt \
			>> $(@D)/dbl-default-env.txt; \
	fi
endef
UBOOT_PRE_BUILD_HOOKS += UBOOT_MYD_YF135_DEFAULT_ENV

# Copy the board DTS into the kernel source tree and add its dtb to the ST Makefile
#
# CUSTOM_DTS_PATH would normally be used, but copies to arch/arm/boot/dts/.
# Linux 6.12+ refactored STM32MP device trees to arch/arm/boot/dts/st/, which
# is incompatible with that standard method.
#
# Runs with the build step only: after DTS edits, `make linux-rebuild`.
define LINUX_MYD_YF135_COPY_DTS
	cp $(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/dts/stm32mp135d-myd-yf135.dts \
		$(@D)/arch/arm/boot/dts/st/stm32mp135d-myd-yf135.dts
	cp $(or $(DBL_PARENT_LINUX_DTSI),$(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/dts/parent-linux.dtsi) \
		$(@D)/arch/arm/boot/dts/st/parent-linux.dtsi
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

# Empty UBIFS images. After resizing overlay or optee_ss volume, set -c to its
# LEB count (printed by ubinize_check.py); fs can't grow past -c
# Changes to -c rebuilds images
$(BINARIES_DIR)/overlay.ubifs: $(BR2_EXTERNAL_MYD_YF135_PATH)/external.mk | host-mtd
	$(HOST_DIR)/sbin/mkfs.ubifs -m 2048 -e 126976 -c 869 -o $@

$(BINARIES_DIR)/optee_ss.ubifs: $(BR2_EXTERNAL_MYD_YF135_PATH)/external.mk | host-mtd
	$(HOST_DIR)/sbin/mkfs.ubifs -m 2048 -e 126976 -c 34 -o $@

# U-Boot env binary, redundant variant. BR2_TARGET_UBOOT_ENVIMAGE does not
# pass -r to mkenvimage; CONFIG_SYS_REDUNDAND_ENVIRONMENT requires the flag
# byte -r emits, otherwise U-Boot CRC fails. Same image goes into UBI
# volumes env-a and env-b at flash time (see ubinize.cfg); both start
# ACTIVE, U-Boot picks the primary, first saveenv flips the secondary.
# Size must match CONFIG_ENV_SIZE in uboot.config.
$(BINARIES_DIR)/uboot.env: $(DBL_UBOOT_ENV_FILES) | host-uboot-tools
	cat $(DBL_UBOOT_ENV_FILES) | $(HOST_DIR)/bin/mkenvimage -s 0x4000 -r -o $@ -

# Rootfs slot image + RAUC bundle payload (mkrootimg.sh)
ifeq ($(BR2_PACKAGE_DBL_VERIFIED_BOOT),y)

# Not in images/: CI uploads it
# NB: not removed by `make clean`; delete fit-key/ for a new key
MYD_YF135_FIT_KEYDIR = $(BASE_DIR)/fit-key
MYD_YF135_FIT_KEY = $(MYD_YF135_FIT_KEYDIR)/throwaway.key
MYD_YF135_FIT_PUBKEYS = $(or $(call qstrip,$(BR2_PACKAGE_DBL_FIT_PUBKEYS)),$(MYD_YF135_FIT_KEYDIR)/throwaway.crt)

$(MYD_YF135_FIT_KEY): | host-openssl
	mkdir -p $(@D)
	$(HOST_DIR)/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
		-subj /CN=dbl-fit-throwaway -keyout $@.tmp -out $(@D)/throwaway.crt
	mv $@.tmp $@
$(MYD_YF135_FIT_KEYDIR)/throwaway.crt: $(MYD_YF135_FIT_KEY) ;

# Starts from dts/dt.dtb so removed keys don't linger
# Runs before Buildroot installs u-boot.bin, to allow TF-A to pack keyed U-Boot into the FIP
define UBOOT_MYD_YF135_FIT_PUBKEYS
	cp $(@D)/dts/dt.dtb $(@D)/u-boot.dtb
	$(foreach crt,$(MYD_YF135_FIT_PUBKEYS),
		$(@D)/tools/fdt_add_pubkey -a sha256,rsa2048 -r conf \
			-k $(dir $(crt)) -n $(basename $(notdir $(crt))) $(@D)/u-boot.dtb
	)
	$(HOST_DIR)/bin/fdtput -t s $(@D)/u-boot.dtb /signature required-mode any
	cat $(@D)/u-boot-nodtb.bin $(@D)/u-boot.dtb > $(@D)/u-boot.bin
endef
UBOOT_POST_BUILD_HOOKS += UBOOT_MYD_YF135_FIT_PUBKEYS
$(UBOOT_TARGET_BUILD): $(MYD_YF135_FIT_PUBKEYS) | host-dtc

MYD_YF135_ROOTIMG_OPTS = --verity --sign-key $(MYD_YF135_FIT_KEY)
MYD_YF135_ROOTIMG_DEPS = host-cryptsetup uboot $(MYD_YF135_FIT_KEY)
# NB: buildroot host-uboot-tools is not compatible with current U-boot (2021.07)
MYD_YF135_ROOTIMG_PATH = $(UBOOT_DIR)/tools:

# After certificate changes run `make linux-reconfigure`
ifneq ($(call qstrip,$(BR2_PACKAGE_DBL_VERITY_SIG_CERTS)),)
define MYD_YF135_LINUX_VERITY_SIG
	$(call KCONFIG_ENABLE_OPT,CONFIG_DM_VERITY_VERIFY_ROOTHASH_SIG)
	$(call KCONFIG_SET_OPT,CONFIG_SYSTEM_TRUSTED_KEYS,"$(call qstrip,$(BR2_PACKAGE_DBL_VERITY_SIG_CERTS))")
endef
PACKAGES_LINUX_CONFIG_FIXUPS += $(MYD_YF135_LINUX_VERITY_SIG)$(sep)
endif
endif

# RAUC /etc/rauc/system.conf is composed from
# rauc/system.conf, + rauc/system-verified.conf + parent board/rauc-system.conf
# Groups may repeat across files; repeated keys are rejected.
DBL_PARENT_RAUC_CONF := $(wildcard $(addsuffix /rauc-system.conf,$(DBL_PARENT_DIRS)))
DBL_RAUC_CONF_FILES := \
	$(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/rauc/system.conf \
	$(if $(BR2_PACKAGE_DBL_VERIFIED_BOOT),$(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/rauc/system-verified.conf) \
	$(DBL_PARENT_RAUC_CONF)

# Not in images/, like fit-key/
MYD_YF135_RAUC_KEYDIR = $(BASE_DIR)/rauc-key
MYD_YF135_RAUC_KEYRING = $(or $(call qstrip,$(BR2_PACKAGE_DBL_RAUC_KEYRING)),$(MYD_YF135_RAUC_KEYDIR)/throwaway.crt)

$(MYD_YF135_RAUC_KEYDIR)/throwaway.crt: | host-openssl
	mkdir -p $(@D)
	$(HOST_DIR)/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
		-subj /CN=dbl-rauc-throwaway -keyout $(@D)/throwaway.key -out $@.tmp
	mv $@.tmp $@

define MYD_YF135_RAUC_CONF
	mkdir -p $(TARGET_DIR)/etc/rauc
	cat $(DBL_RAUC_CONF_FILES) > $(TARGET_DIR)/etc/rauc/system.conf
	$(INSTALL) -D -m 0644 $(MYD_YF135_RAUC_KEYRING) $(TARGET_DIR)/etc/rauc/keyring.pem
	$(if $(BR2_PACKAGE_DBL_VERIFIED_BOOT),
		$(INSTALL) -D -m 755 $(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/rauc/pre-install \
			$(TARGET_DIR)/usr/lib/rauc/pre-install)
endef
TARGET_FINALIZE_HOOKS += MYD_YF135_RAUC_CONF
target-finalize: $(MYD_YF135_RAUC_KEYRING)

# shortcut: `linux` and `rootfs-squashfs` are phony; rebuilds on every `make`
$(BINARIES_DIR)/rootfs.img: linux rootfs-squashfs host-uboot-tools host-dtc $(MYD_YF135_ROOTIMG_DEPS)
	PATH=$(MYD_YF135_ROOTIMG_PATH)$(BR_PATH) $(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/mkrootimg.sh $(MYD_YF135_ROOTIMG_OPTS) \
		$(BINARIES_DIR)/zImage \
		$(BINARIES_DIR)/stm32mp135d-myd-yf135.dtb \
		$(BINARIES_DIR)/rootfs.squashfs \
		$@

# Wire companion images into rootfs.ubi's prereqs so make builds them
# before ubinize. Recipe stays in fs/ubi/ubi.mk; we only add deps here.
$(BINARIES_DIR)/rootfs.ubi: \
	$(BINARIES_DIR)/rootfs.img \
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
