# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
include $(sort $(wildcard $(BR2_EXTERNAL_DBL_MP13X_PATH)/package/*/*.mk))

# Parent DT, at most one external each:
#   board/dts/parent-linux.dtsi             Linux DT
#   board/dts/parent-u-boot.dtsi            U-Boot control DT
#   board/dts/parent-optee.dtsi             OP-TEE DT (security-critical)
#   board/dts/parent-tf-a.dtsi              TF-A BL2 DT (security-critical)
#   board/dts/parent-tf-a-fw-config.dtsi    TF-A load addresses / TZC (security-critical)
# See wiki: Parent Integration / Parent device tree docs
DBL_PARENT_DTS_DIRS := $(foreach name,$(filter-out DBL_MP13X,$(BR2_EXTERNAL_NAMES)),\
	$(BR2_EXTERNAL_$(name)_PATH)/board/dts)
DBL_PARENT_LINUX_DTSI := $(wildcard $(addsuffix /parent-linux.dtsi,$(DBL_PARENT_DTS_DIRS)))
DBL_PARENT_UBOOT_DTSI := $(wildcard $(addsuffix /parent-u-boot.dtsi,$(DBL_PARENT_DTS_DIRS)))
DBL_PARENT_OPTEE_DTSI := $(wildcard $(addsuffix /parent-optee.dtsi,$(DBL_PARENT_DTS_DIRS)))
DBL_PARENT_TF_A_DTSI := $(wildcard $(addsuffix /parent-tf-a.dtsi,$(DBL_PARENT_DTS_DIRS)))
DBL_PARENT_TF_A_FW_CONFIG_DTSI := $(wildcard $(addsuffix /parent-tf-a-fw-config.dtsi,$(DBL_PARENT_DTS_DIRS)))

# Optional board/parent-u-boot.env from parent external, e.g. to set
# parent_boot_hook. Compiled into U-Boot: covered by verified boot.
DBL_PARENT_DIRS := $(foreach name,$(filter-out DBL_MP13X,$(BR2_EXTERNAL_NAMES)),\
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

# dbl-bootid EEPROM layout (board/myc-yf135/dbl-bootid.toml)
DBL_MP13X_BOOTID = $(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/dbl-bootid
DBL_MP13X_BOOTID_DTSI = $(HOST_DIR)/bin/python3 \
	$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/dbl-bootid.py dtsi $(DBL_MP13X_BOOTID).toml
# _DEPENDENCIES is read when linux.mk/uboot.mk are parsed, before this file
$(LINUX_TARGET_BUILD) $(UBOOT_TARGET_BUILD): | host-python3

ifeq ($(BR2_PACKAGE_DBL_VERIFIED_BOOT),y)
define DBL_MP13X_BOOTID_INSTALL_IMAGES
	$(INSTALL) -D -m 0644 -t $(BINARIES_DIR) $(DBL_MP13X_BOOTID).toml $(DBL_MP13X_BOOTID)-example.bin
endef
TARGET_FINALIZE_HOOKS += DBL_MP13X_BOOTID_INSTALL_IMAGES
endif

# U-Boot compiles the base Linux dts as its control DT: provide the empty
# parent-linux.dtsi stub (Linux-only peripherals) and the parent's U-Boot file.
# Runs with the build step only: after DT edits, `make uboot-rebuild`.
define UBOOT_DBL_MP13X_COPY_DTSI
	cp $(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/dts/parent-linux.dtsi \
		$(@D)/arch/arm/dts/parent-linux.dtsi
	$(DBL_MP13X_BOOTID_DTSI) > $(@D)/arch/arm/dts/dbl-bootid-layout.dtsi
	cp $(or $(DBL_PARENT_UBOOT_DTSI),$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/dts/parent-u-boot.dtsi) \
		$(@D)/arch/arm/dts/parent-u-boot.dtsi
endef
# OP-TEE and TF-A have their own source trees. Not via CUSTOM_DTS_PATH (that
# copy would overwrite the parent file with the stub).
define OPTEE_OS_DBL_MP13X_COPY_DTSI
	cp $(or $(DBL_PARENT_OPTEE_DTSI),$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/dts/parent-optee.dtsi) \
		$(@D)/core/arch/arm/dts/parent-optee.dtsi
endef
OPTEE_OS_PRE_BUILD_HOOKS += OPTEE_OS_DBL_MP13X_COPY_DTSI

ifneq ($(BR2_PACKAGE_DBL_OTP_WRITE),y)
OPTEE_OS_MAKE_OPTS += CFG_STM32_BSEC_WRITE=n
endif

# Consent build additions
ifeq ($(BR2_PACKAGE_DBL_CONSENT),y)
OPTEE_OS_MAKE_OPTS += CPPFLAGS="$(TARGET_CPPFLAGS) -DDBL_CONSENT"
endif

# No loadable TAs: in-tree TAs are signed with OP-TEE's public default key,
# which may be loaded by root. Early TAs (built into OP-TEE) remain.
ifneq ($(BR2_TARGET_OPTEE_OS_SERVICES),y)
OPTEE_OS_MAKE_OPTS += CFG_REE_FS_TA=n CFG_SECSTOR_TA=n
else ifeq ($(BR2_PACKAGE_DBL_VERIFIED_BOOT),y)
$(error BR2_TARGET_OPTEE_OS_SERVICES enables loadable TAs, incompatible BR2_PACKAGE_DBL_VERIFIED_BOOT)
endif

define ARM_TRUSTED_FIRMWARE_DBL_MP13X_COPY_DTSI
	cp $(or $(DBL_PARENT_TF_A_DTSI),$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/dts/parent-tf-a.dtsi) \
		$(@D)/fdts/parent-tf-a.dtsi
	cp $(or $(DBL_PARENT_TF_A_FW_CONFIG_DTSI),$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/dts/parent-tf-a-fw-config.dtsi) \
		$(@D)/fdts/parent-tf-a-fw-config.dtsi
endef
ARM_TRUSTED_FIRMWARE_PRE_BUILD_HOOKS += ARM_TRUSTED_FIRMWARE_DBL_MP13X_COPY_DTSI

UBOOT_PRE_BUILD_HOOKS += UBOOT_DBL_MP13X_COPY_DTSI

# U-Boot env text, used for both uboot.env (flash) and compiled default env.
# Without CONFIG_ENV_WRITEABLE_LIST U-Boot uses compiled env only when flash
# env is invalid: flash must hold full script.
# Append uboot-env-flags.txt only with CONFIG_ENV_WRITEABLE_LIST. Without it,
# U-Boot warns on unknown "w" flag.
# After env edits run `make uboot-rebuild`
DBL_UBOOT_ENV_WRITEABLE := $(subst $(space),,$(patsubst %,$(comma)%,$(call qstrip,$(BR2_PACKAGE_DBL_UBOOT_ENV_WRITEABLE))))
DBL_UBOOT_ENV_FILES := \
	$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/default-env.env \
	$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/uboot-env.txt \
	$(if $(BR2_PACKAGE_DBL_NAND_LOCK),$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/uboot-env-nand-lock.txt) \
	$(DBL_PARENT_UBOOT_ENV)
define UBOOT_DBL_MP13X_DEFAULT_ENV
	cat $(DBL_UBOOT_ENV_FILES) \
		$(if $(BR2_PACKAGE_DBL_CONSENT),$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/uboot-env-consent.txt) \
		$(if $(BR2_PACKAGE_DBL_CONSENT_BOOT),$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/uboot-env-consent-boot.txt) \
		> $(@D)/dbl-default-env.txt
	if grep -q '^CONFIG_ENV_WRITEABLE_LIST=y' $(@D)/.config; then \
		sed '/^\.flags=/s/$$/$(DBL_UBOOT_ENV_WRITEABLE)/' \
			$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/uboot-env-flags.txt \
			>> $(@D)/dbl-default-env.txt; \
	fi
endef
UBOOT_PRE_BUILD_HOOKS += UBOOT_DBL_MP13X_DEFAULT_ENV

# Copy the board DTS into the kernel source tree and add its dtb to the ST Makefile
#
# CUSTOM_DTS_PATH would normally be used, but copies to arch/arm/boot/dts/.
# Linux 6.12+ refactored STM32MP device trees to arch/arm/boot/dts/st/, which
# is incompatible with that standard method.
#
# Runs with the build step only: after DTS edits, `make linux-rebuild`.
define LINUX_DBL_MP13X_COPY_DTS
	cp $(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/dts/stm32mp135-myc-yf135.dts \
		$(@D)/arch/arm/boot/dts/st/stm32mp135-myc-yf135.dts
	cp $(or $(DBL_PARENT_LINUX_DTSI),$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/dts/parent-linux.dtsi) \
		$(@D)/arch/arm/boot/dts/st/parent-linux.dtsi
	$(DBL_MP13X_BOOTID_DTSI) > $(@D)/arch/arm/boot/dts/st/dbl-bootid-layout.dtsi
	grep -q 'stm32mp135-myc-yf135\.dtb' $(@D)/arch/arm/boot/dts/st/Makefile || \
		printf '\ndtb-$$(CONFIG_ARCH_STM32) += stm32mp135-myc-yf135.dtb\n' \
			>> $(@D)/arch/arm/boot/dts/st/Makefile
endef
LINUX_PRE_BUILD_HOOKS += LINUX_DBL_MP13X_COPY_DTS

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
$(BINARIES_DIR)/overlay.ubifs: $(BR2_EXTERNAL_DBL_MP13X_PATH)/external.mk | host-mtd
	$(HOST_DIR)/sbin/mkfs.ubifs -m 2048 -e 126976 -c 869 -o $@

$(BINARIES_DIR)/optee_ss.ubifs: $(BR2_EXTERNAL_DBL_MP13X_PATH)/external.mk | host-mtd
	$(HOST_DIR)/sbin/mkfs.ubifs -m 2048 -e 126976 -c 34 -o $@

# U-Boot env binary, redundant variant. BR2_TARGET_UBOOT_ENVIMAGE does not
# pass -r to mkenvimage; CONFIG_SYS_REDUNDAND_ENVIRONMENT requires the flag
# byte -r emits, otherwise U-Boot CRC fails. Same image goes into UBI
# volumes env-a and env-b at flash time (see ubinize.cfg); both start
# ACTIVE, U-Boot picks the primary, first saveenv flips the secondary.
# Size must match CONFIG_ENV_SIZE in uboot.config.
$(BINARIES_DIR)/uboot.env: $(DBL_UBOOT_ENV_FILES) | host-uboot-tools
	cat $(DBL_UBOOT_ENV_FILES) | $(HOST_DIR)/bin/mkenvimage -s 0x4000 -r -o $@ -

# See board/myc-yf135/insecure-test-key/README.md
DBL_MP13X_TEST_KEY = $(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/insecure-test-key/insecure-test-key

# Rootfs slot image + RAUC bundle payload (mkrootimg.sh)
ifeq ($(BR2_PACKAGE_DBL_VERIFIED_BOOT),y)

DBL_MP13X_FIT_ALGO = sha256,rsa3072
DBL_MP13X_FIT_KEY = $(DBL_MP13X_TEST_KEY).key
DBL_MP13X_FIT_PUBKEYS = $(or $(call qstrip,$(BR2_PACKAGE_DBL_FIT_PUBKEYS)),$(DBL_MP13X_TEST_KEY).crt)

# Starts from dts/dt.dtb so removed keys don't linger
# Runs before Buildroot installs u-boot.bin, to allow TF-A to pack keyed U-Boot into the FIP
define UBOOT_DBL_MP13X_FIT_PUBKEYS
	cp $(@D)/dts/dt.dtb $(@D)/u-boot.dtb
	$(foreach crt,$(DBL_MP13X_FIT_PUBKEYS),
		$(@D)/tools/fdt_add_pubkey -a $(DBL_MP13X_FIT_ALGO) -r conf \
			-k $(dir $(crt)) -n $(basename $(notdir $(crt))) $(@D)/u-boot.dtb
	)
	$(HOST_DIR)/bin/fdtput -t s $(@D)/u-boot.dtb /signature required-mode any
	cat $(@D)/u-boot-nodtb.bin $(@D)/u-boot.dtb > $(@D)/u-boot.bin
endef
UBOOT_POST_BUILD_HOOKS += UBOOT_DBL_MP13X_FIT_PUBKEYS
$(UBOOT_TARGET_BUILD): $(DBL_MP13X_FIT_PUBKEYS) | host-dtc

# TF-A Trusted Board Boot: every certificate is signed with the test key;
# always re-sign release FIPs with sign-fip.sh
DBL_MP13X_TBB_KEY = $(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/insecure-test-key/insecure-tbb-key.pem
$(ARM_TRUSTED_FIRMWARE_TARGET_BUILD): $(DBL_MP13X_TBB_KEY) | dbl-tf-a-mbedtls $(BR2_CMAKE_HOST_DEPENDENCY)
define ARM_TRUSTED_FIRMWARE_DBL_MP13X_CHECK_TBB_KEYS
	want=$$($(HOST_DIR)/bin/openssl pkey -in $(DBL_MP13X_TBB_KEY) -pubout) && \
	for crt in $(ARM_TRUSTED_FIRMWARE_IMG_DIR)/*.crt; do \
		got=$$($(HOST_DIR)/bin/openssl x509 -inform DER -in $$crt -noout -pubkey) && \
		[ "$$got" = "$$want" ] || { echo "TBB: $$crt not signed for the test key" >&2; exit 1; }; \
	done
endef
ARM_TRUSTED_FIRMWARE_POST_BUILD_HOOKS += ARM_TRUSTED_FIRMWARE_DBL_MP13X_CHECK_TBB_KEYS

# Target fiptool for rauc/fip-install (unit certificate splice)
DBL_MP13X_FIPTOOL_DIR = $(ARM_TRUSTED_FIRMWARE_DIR)/tools/fiptool
define ARM_TRUSTED_FIRMWARE_DBL_MP13X_TARGET_FIPTOOL
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -std=c99 \
		-D_GNU_SOURCE -D_XOPEN_SOURCE=700 -DSTATIC=0 -DUSING_OPENSSL3=1 \
		-DPLAT_DEF_FIP_UUID -I$(@D)/include/tools_share \
		-I$(@D)/plat/st/common/include -I$(DBL_MP13X_FIPTOOL_DIR) \
		-o $(@D)/fiptool-target $(DBL_MP13X_FIPTOOL_DIR)/fiptool.c \
		$(DBL_MP13X_FIPTOOL_DIR)/tbbr_config.c \
		$(DBL_MP13X_FIPTOOL_DIR)/plat_fiptool/st/plat_def_uuid_config.c -lcrypto
endef
ARM_TRUSTED_FIRMWARE_POST_BUILD_HOOKS += ARM_TRUSTED_FIRMWARE_DBL_MP13X_TARGET_FIPTOOL
define ARM_TRUSTED_FIRMWARE_DBL_MP13X_INSTALL_FIPTOOL
	$(INSTALL) -D -m 0755 $(@D)/fiptool-target $(TARGET_DIR)/usr/bin/fiptool
endef
ARM_TRUSTED_FIRMWARE_POST_INSTALL_TARGET_HOOKS += ARM_TRUSTED_FIRMWARE_DBL_MP13X_INSTALL_FIPTOOL
$(ARM_TRUSTED_FIRMWARE_TARGET_BUILD): | openssl
ARM_TRUSTED_FIRMWARE_MAKE_OPTS += \
	TRUSTED_BOARD_BOOT=1 GENERATE_COT=1 \
	MBEDTLS_DIR=$(DBL_TF_A_MBEDTLS_DIR) \
	ROT_KEY=$(DBL_MP13X_TBB_KEY) \
	TRUSTED_WORLD_KEY=$(DBL_MP13X_TBB_KEY) \
	NON_TRUSTED_WORLD_KEY=$(DBL_MP13X_TBB_KEY) \
	BL32_KEY=$(DBL_MP13X_TBB_KEY) \
	BL33_KEY=$(DBL_MP13X_TBB_KEY)

DBL_MP13X_ROOTIMG_OPTS = --verity --sign-key $(DBL_MP13X_FIT_KEY) --sign-algo $(DBL_MP13X_FIT_ALGO)
DBL_MP13X_ROOTIMG_DEPS = host-cryptsetup uboot $(DBL_MP13X_FIT_KEY)
# NB: Buildroot host-uboot-tools (2021.07) is too old for this U-Boot's FIT
DBL_MP13X_ROOTIMG_PATH = $(UBOOT_DIR)/tools:

# After certificate changes run `make linux-reconfigure`
ifneq ($(call qstrip,$(BR2_PACKAGE_DBL_VERITY_SIG_CERTS)),)
define DBL_MP13X_LINUX_VERITY_SIG
	$(call KCONFIG_ENABLE_OPT,CONFIG_DM_VERITY_VERIFY_ROOTHASH_SIG)
	$(call KCONFIG_SET_OPT,CONFIG_SYSTEM_TRUSTED_KEYS,"$(call qstrip,$(BR2_PACKAGE_DBL_VERITY_SIG_CERTS))")
endef
PACKAGES_LINUX_CONFIG_FIXUPS += $(DBL_MP13X_LINUX_VERITY_SIG)$(sep)
endif
endif

# RAUC /etc/rauc/system.conf is composed from
# rauc/system.conf, + rauc/system-verified.conf + parent board/rauc-system.conf
# Groups may repeat across files; repeated keys are rejected.
DBL_PARENT_RAUC_CONF := $(wildcard $(addsuffix /rauc-system.conf,$(DBL_PARENT_DIRS)))
DBL_RAUC_CONF_FILES := \
	$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/rauc/system.conf \
	$(if $(BR2_PACKAGE_DBL_VERIFIED_BOOT),$(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/rauc/system-verified.conf) \
	$(DBL_PARENT_RAUC_CONF)

DBL_MP13X_RAUC_KEYRING = $(or $(call qstrip,$(BR2_PACKAGE_DBL_RAUC_KEYRING)),$(DBL_MP13X_TEST_KEY).crt)

define DBL_MP13X_RAUC_CONF
	mkdir -p $(TARGET_DIR)/etc/rauc
	cat $(DBL_RAUC_CONF_FILES) > $(TARGET_DIR)/etc/rauc/system.conf
	$(INSTALL) -D -m 0644 $(DBL_MP13X_RAUC_KEYRING) $(TARGET_DIR)/etc/rauc/keyring.pem
	$(if $(BR2_PACKAGE_DBL_VERIFIED_BOOT),
		$(INSTALL) -D -m 755 $(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/rauc/pre-install \
			$(TARGET_DIR)/usr/lib/rauc/pre-install
		$(INSTALL) -D -m 755 $(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/rauc/fip-install \
			$(TARGET_DIR)/usr/lib/rauc/fip-install)
endef
TARGET_FINALIZE_HOOKS += DBL_MP13X_RAUC_CONF
target-finalize: $(DBL_MP13X_RAUC_KEYRING)

# shortcut: `linux` and `rootfs-squashfs` are phony; rebuilds on every `make`
$(BINARIES_DIR)/rootfs.img: linux rootfs-squashfs host-uboot-tools host-dtc $(DBL_MP13X_ROOTIMG_DEPS)
	PATH=$(DBL_MP13X_ROOTIMG_PATH)$(BR_PATH) $(BR2_EXTERNAL_DBL_MP13X_PATH)/board/myc-yf135/mkrootimg.sh $(DBL_MP13X_ROOTIMG_OPTS) \
		$(BINARIES_DIR)/zImage \
		$(BINARIES_DIR)/stm32mp135-myc-yf135.dtb \
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
DBL_MP13X_VERSION := $(shell cd $(BR2_EXTERNAL_DBL_MP13X_PATH) && \
	git describe --always --dirty --tags 2>/dev/null || echo unknown)

define UBOOT_DBL_MP13X_LOCALVERSION
	printf -- '-%s\n' "$(DBL_MP13X_VERSION)" > $(@D)/localversion
endef
UBOOT_PRE_BUILD_HOOKS += UBOOT_DBL_MP13X_LOCALVERSION

define DBL_MP13X_EXPECTED_BL33_VERSION
	mkdir -p $(TARGET_DIR)/etc/firmware
	printf '%s\n' "$(DBL_MP13X_VERSION)" \
		> $(TARGET_DIR)/etc/firmware/expected-bl33-version
endef
TARGET_FINALIZE_HOOKS += DBL_MP13X_EXPECTED_BL33_VERSION
