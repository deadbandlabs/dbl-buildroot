# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
# BUILDROOT_SRC comes from the environment (nix dev shell)

# Build/output paths.
# OUTPUT_BASE anchors all artefacts (output/, dl/)
# Direct invocation (submodule development) defaults to the submodule root
# parent.mk overrides it so a superproject's artefacts land in the parent repo
OUTPUT_BASE   ?= $(CURDIR)
MODE          ?= release
O             ?= $(OUTPUT_BASE)/output/$(MODE)
CCACHE_DIR    ?= $(OUTPUT_BASE)/output/ccache

# Download cache outside output/ so cleaning output/ still prevents full re-dl
# Override with BR2_DL_DIR=/path/to/shared/cache to share across projects
BR2_DL_DIR    ?= $(OUTPUT_BASE)/dl

# Variant config/script paths
RELEASE_DEFCONFIG    := $(CURDIR)/configs/myc_yf135_defconfig
DEBUG_FRAGMENT       := $(CURDIR)/configs/myc_yf135_debug.fragment
PROGRAMMER_FRAGMENT  := $(CURDIR)/configs/myc_yf135_programmer.fragment
CONSENT_FRAGMENT     := $(CURDIR)/configs/myc_yf135_consent.fragment
# Gated by BR2_PACKAGE_DBL_VERIFIED_BOOT inside merge-defconfig.py (dbl-merge-if)
VERIFIED_FRAGMENT    := $(CURDIR)/configs/myc_yf135_verified.fragment
# DBL_PYTHON3 is exported by the nix dev/ci shells (python3 stays off PATH, see nix/devshell.nix)
MERGE_DEFCONFIG      := $(or $(DBL_PYTHON3),python3) $(CURDIR)/support/build/merge-defconfig.py
CONFIG_FRAGMENT_DEBUG ?=
BUNDLE_IMAGES_SCRIPT := $(CURDIR)/support/build/bundle-images.sh
FLASHLAYOUT_SRC      := $(CURDIR)/board/myc-yf135/flashlayout.tsv

# External toolchain SDK used by the target build, resolved when the defconfig is applied
#   1. TOOLCHAIN_SDK=<path>: an existing SDK (e.g. from `make toolchain` below)
#   2. DBL_NIX_TOOLCHAIN set (exported by the nix dev/ci shells): this repo's
#      Nix .#toolchain build, substituted from Cachix when available
#   3. Neither: the internal toolchain is built with the target
# A parent with a custom toolchain passes TOOLCHAIN_SDK itself
TOOLCHAIN_SDK ?=
DBL_NIX_TOOLCHAIN ?=

# Merge external-toolchain fragment description for TOOLCHAIN_SDK builds
EXTERNAL_TOOLCHAIN_FRAGMENT ?= $(CURDIR)/configs/myc_yf135_external_toolchain.fragment
_TC_PATH_FRAGMENT           := $(O)/external-toolchain-path.fragment

# `make toolchain` builds a relocatable SDK from the toolchain-only defconfig
TOOLCHAIN_DEFCONFIG := $(CURDIR)/configs/myc_yf135_toolchain_defconfig
TOOLCHAIN_O         := $(OUTPUT_BASE)/output/toolchain
TOOLCHAIN_SDK_OUT   := $(TOOLCHAIN_O)/sdk
TOOLCHAIN_MAKE      := $(MAKE) -C $(BUILDROOT_SRC) O=$(TOOLCHAIN_O) BR2_DL_DIR=$(BR2_DL_DIR) BR2_CCACHE_DIR=$(CCACHE_DIR)

# BR2_EXTERNAL is a ':' separated list. Default to this repository.
# Downstream/super-projects can append with BR2_EXTERNAL_EXTRA or override BR2_EXTERNAL entirely.
BR2_EXTERNAL ?= $(CURDIR)
ifneq ($(strip $(BR2_EXTERNAL_EXTRA)),)
BR2_EXTERNAL := $(BR2_EXTERNAL):$(BR2_EXTERNAL_EXTRA)
endif

# (Optional) merge downstream defconfig fragment. When set, the
# variant's base defconfig is merged before applying. Super-projects use this to
# extend the base image with project-specific packages/config.
CONFIG_FRAGMENT ?=
OVERLAY_DEFCONFIG := $(O)/overlay_defconfig

# (Optional) extra rootfs overlay dirs (e.g. Nix-built image content) appended to
# BR2_ROOTFS_OVERLAY via a generated fragment, mirroring the nix build's extraRootfsOverlays
EXTRA_ROOTFS_OVERLAYS    ?=
_ROOTFS_OVERLAY_FRAGMENT := $(O)/rootfs-overlays.fragment

# Derive the kernel source directory from the version in the defconfig so
# this stays in sync automatically if the version is ever bumped
LINUX_VERSION := $(shell grep BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE \
					 $(RELEASE_DEFCONFIG) | cut -d'"' -f2)
LINUX_SRC     := $(O)/build/linux-$(LINUX_VERSION)
LINUX_CONFIG  := $(CURDIR)/board/myc-yf135/linux.config

# Host tools self-resolve libs via RUNPATH=$ORIGIN/../lib (from HOSTLDFLAGS)
# No LD_LIBRARY_PATH. Without -rpath-link it leaks host x86 libs (libcrypt.so)
# into target cross-links and fails with "file format not recognized"
BR2_ARGS = -C $(BUILDROOT_SRC) O=$(O) BR2_EXTERNAL=$(BR2_EXTERNAL) BR2_DL_DIR=$(BR2_DL_DIR) BR2_CCACHE_DIR=$(CCACHE_DIR)
BR2_MAKE = $(MAKE) $(BR2_ARGS)

# Build logs:
# One timestamped file per invocation, stored in output/logs/ sorted chronologically by filename
# Override with make LOG=/tmp/other.log
LOG_DIR ?= $(O)/logs
LOG     ?= $(LOG_DIR)/$(shell date +%Y%m%d-%H%M%S).log

# MODE selects the build variant (release/debug/programmer) and the output dir.
# release    = output/release/    production NAND artifacts (ENV_IS_IN_UBI)
# debug      = output/debug/      verbose logging variant of release
# programmer = output/programmer/ USB DFU loader (ENV_IS_NOWHERE), used as
#                                 fsbl-boot/fip-boot in flashlayout.tsv
# consent    = output/consent/    USB DFU loaded, boots the factory rootfs
#                                 (fip-consent.bin; flash-dfu --consent)
# Override O directly to use a custom output path.
#
# release/debug builds chain programmer and consent build with
# BR2_PACKAGE_DBL_VERIFIED_BOOT=y
# Set BUILD_PROGRAMMER=0 to opt out of both
BUILD_PROGRAMMER ?= 1

ifeq ($(MODE),debug)
_BUILD_TARGETS  :=
_UPDATE_LATEST  := true
else ifeq ($(MODE),programmer)
_BUILD_TARGETS  := arm-trusted-firmware
_UPDATE_LATEST  := false
else ifeq ($(MODE),consent)
_BUILD_TARGETS  := arm-trusted-firmware
_UPDATE_LATEST  := false
else
_BUILD_TARGETS  :=
_UPDATE_LATEST  := true
endif

# Buildroot defconfigs do not support inheritance, release is the source of truth
# Variants merge release + fragments into $(OVERLAY_DEFCONFIG) at build time
# Compose the merge chain for this mode:
#   release    = RELEASE_DEFCONFIG + VERIFIED_FRAGMENT + CONFIG_FRAGMENT
#   debug      = RELEASE_DEFCONFIG + VERIFIED_FRAGMENT + CONFIG_FRAGMENT + DEBUG_FRAGMENT + CONFIG_FRAGMENT_DEBUG
#   programmer = RELEASE_DEFCONFIG + VERIFIED_FRAGMENT + CONFIG_FRAGMENT + PROGRAMMER_FRAGMENT
#                (same chain as the nix programmer build, which is what ships)
#   consent    = RELEASE_DEFCONFIG + VERIFIED_FRAGMENT + CONFIG_FRAGMENT + CONSENT_FRAGMENT
# VERIFIED_FRAGMENT only applies when the merged result sets BR2_PACKAGE_DBL_VERIFIED_BOOT=y.
# Empty/unset slots are filtered out.
_MERGE_DELTAS := $(VERIFIED_FRAGMENT)
ifeq ($(MODE),debug)
  _MERGE_DELTAS += $(strip $(CONFIG_FRAGMENT))
  _MERGE_DELTAS += $(DEBUG_FRAGMENT)
  _MERGE_DELTAS += $(strip $(CONFIG_FRAGMENT_DEBUG))
else ifeq ($(MODE),programmer)
  _MERGE_DELTAS += $(strip $(CONFIG_FRAGMENT))
  _MERGE_DELTAS += $(PROGRAMMER_FRAGMENT)
else ifeq ($(MODE),consent)
  _MERGE_DELTAS += $(strip $(CONFIG_FRAGMENT))
  _MERGE_DELTAS += $(CONSENT_FRAGMENT)
else
  _MERGE_DELTAS += $(strip $(CONFIG_FRAGMENT))
endif
_MERGE_DELTAS := $(strip $(_MERGE_DELTAS))

# Extra rootfs overlays, appended last to stack onto base + fragment overlays
ifneq ($(strip $(EXTRA_ROOTFS_OVERLAYS)),)
  _ROOTFS_OVERLAY_DELTA = $(_ROOTFS_OVERLAY_FRAGMENT)
  _WRITE_ROOTFS_OVERLAY = printf 'BR2_ROOTFS_OVERLAY="%s"\n' '$(EXTRA_ROOTFS_OVERLAYS)' > $(_ROOTFS_OVERLAY_FRAGMENT)
else
  _ROOTFS_OVERLAY_DELTA =
  _WRITE_ROOTFS_OVERLAY = true
endif

# Merge chain into $(OVERLAY_DEFCONFIG) and apply it
# SDK resolved here, the only consumer. config/clean/fetch goals never call nix
# SDK fragment goes after the mode deltas to override the internal toolchain
define _APPLY_DEFCONFIG
@mkdir -p $(O)
@set -e; sdk='$(strip $(TOOLCHAIN_SDK))'; tc=; \
if [ -z "$$sdk" ] && [ -n '$(strip $(DBL_NIX_TOOLCHAIN))' ]; then \
	sdk=$$(nix build '$(CURDIR)#toolchain' --no-link --print-out-paths); \
	[ -n "$$sdk" ] || { echo "ERROR: could not resolve the Nix toolchain SDK; pass TOOLCHAIN_SDK=<path>" >&2; exit 1; }; \
fi; \
if [ -n "$$sdk" ]; then \
	echo "INFO: external toolchain SDK: $$sdk"; \
	printf 'BR2_TOOLCHAIN_EXTERNAL_PATH="%s"\n' "$$sdk" > $(_TC_PATH_FRAGMENT); \
	tc='$(EXTERNAL_TOOLCHAIN_FRAGMENT) $(_TC_PATH_FRAGMENT)'; \
fi; \
$(_WRITE_ROOTFS_OVERLAY); \
$(MERGE_DEFCONFIG) $(OVERLAY_DEFCONFIG) $(RELEASE_DEFCONFIG) $(_MERGE_DELTAS) $$tc $(_ROOTFS_OVERLAY_DELTA)
$(BR2_MAKE) BR2_DEFCONFIG=$(OVERLAY_DEFCONFIG) defconfig
endef

.DEFAULT_GOAL := all

.PHONY: help all release debug programmer consent regen-toolchain-defconfig toolchain

help:
	@echo "Common targets:"
	@echo "  make                              Build release variant"
	@echo "  MODE=debug make                   Build debug variant"
	@echo "  MODE=programmer make              Build programmer (USB DFU) variant (TF-A + FIP only)"
	@echo "  MODE=consent make                 Build consent session variant (TF-A + FIP only)"
	@echo "  make release                      Alias for release build"
	@echo "  make debug                        Alias for debug build"
	@echo "  make programmer                   Alias for programmer build"
	@echo "  make consent                      Alias for consent build"
	@echo "  make regen-toolchain-defconfig    Regenerate toolchain defconfig from main"
	@echo "  make toolchain                    Build relocatable external-toolchain SDK"

# Sync the toolchain defconfig's tracked symbol values from the main defconfig (run in pre-commit)
regen-toolchain-defconfig:
	$(CURDIR)/support/pre-commit/check-toolchain-defconfig.sh

# Merged config sets verified boot (run after $(_APPLY_DEFCONFIG))
_IS_VERIFIED = grep -q '^BR2_PACKAGE_DBL_VERIFIED_BOOT=y' $(O)/.config

all:
	@mkdir -p $(O) $(LOG_DIR) $(CCACHE_DIR)
	$(_APPLY_DEFCONFIG)
ifeq ($(MODE),consent)
	@$(_IS_VERIFIED) || { echo "ERROR: MODE=consent requires BR2_PACKAGE_DBL_VERIFIED_BOOT=y" >&2; exit 1; }
endif
	$(BR2_MAKE) $(_BUILD_TARGETS) 2>&1 | tee $(LOG); exit $${PIPESTATUS[0]}
	@if [ "$(_UPDATE_LATEST)" = "true" ]; then \
		ln -sfn $(MODE) $(OUTPUT_BASE)/output/latest; \
		echo "INFO: $(OUTPUT_BASE)/output/latest -> $(MODE)"; \
	fi
ifeq ($(filter programmer consent,$(MODE)),)
ifeq ($(BUILD_PROGRAMMER),1)
	$(MAKE) MODE=programmer OUTPUT_BASE=$(OUTPUT_BASE) BR2_DL_DIR=$(BR2_DL_DIR) BR2_EXTERNAL='$(BR2_EXTERNAL)' all
	if $(_IS_VERIFIED); then $(MAKE) MODE=consent OUTPUT_BASE=$(OUTPUT_BASE) BR2_DL_DIR=$(BR2_DL_DIR) BR2_EXTERNAL='$(BR2_EXTERNAL)' all; fi
ifneq ($(wildcard $(FLASHLAYOUT_SRC)),)
	$(BUNDLE_IMAGES_SCRIPT) $(O)/images $(OUTPUT_BASE)/output/programmer/images $(FLASHLAYOUT_SRC) \
		$$($(_IS_VERIFIED) && echo $(OUTPUT_BASE)/output/consent/images)
	@echo "INFO: Generated $(O)/images/flashlayout.tsv"
endif
endif
endif

release:
	$(MAKE) MODE=release all

debug:
	$(MAKE) MODE=debug all

programmer:
	$(MAKE) MODE=programmer all

consent:
	$(MAKE) MODE=consent all

# Build SDK from the toolchain-only defconfig and unpack it to $(TOOLCHAIN_SDK_OUT)
# Mirrors the Nix stage-1 (.#toolchain): make sdk -> untar -> relocate-sdk.sh
# Pass to a target build with TOOLCHAIN_SDK=<path>
toolchain:
	@mkdir -p $(TOOLCHAIN_O) $(CCACHE_DIR)
	$(TOOLCHAIN_MAKE) BR2_DEFCONFIG=$(TOOLCHAIN_DEFCONFIG) defconfig
	$(TOOLCHAIN_MAKE) sdk
	rm -rf $(TOOLCHAIN_SDK_OUT)
	@mkdir -p $(TOOLCHAIN_SDK_OUT)
	tar -xf $(TOOLCHAIN_O)/images/*_sdk-buildroot.tar.gz -C $(TOOLCHAIN_SDK_OUT) --strip-components=1
	$(TOOLCHAIN_SDK_OUT)/relocate-sdk.sh
	@echo "INFO: SDK ready at $(TOOLCHAIN_SDK_OUT)"
	@echo "INFO: reuse via: make TOOLCHAIN_SDK=$(TOOLCHAIN_SDK_OUT) debug"

# If bootstrapping a new repo, see board/myc-yf135/linux.config (upstream multi_v7_defconfig)
# Run once before the first full build, then use:
#   make linux-menuconfig (interactive kernel config)
#   make linux-update-config (writes changes back to board/myc-yf135/linux.config to commit)
.PHONY: linux-config-init
linux-config-init:
	$(_APPLY_DEFCONFIG)
	$(BR2_MAKE) linux-extract
	$(MAKE) -C $(LINUX_SRC) ARCH=arm multi_v7_defconfig
	install -D $(LINUX_SRC)/.config $(LINUX_CONFIG)
	@echo ""
	@echo "Written to $(LINUX_CONFIG)"
	@echo "Customise : make linux-menuconfig"
	@echo "Save back : make linux-update-config"

# No logging enabled for interactive/ncurses targets
MENUCONFIG_TARGETS := menuconfig linux-menuconfig uboot-menuconfig \
                      busybox-menuconfig barebox-menuconfig \
                      nconfig linux-nconfig

.PHONY: $(MENUCONFIG_TARGETS)
$(MENUCONFIG_TARGETS):
	$(BR2_MAKE) $@

# Regenerate all locks
#  * buildroot.lock: target/image sources
#  * toolchain.lock: toolchain SDK sources
.PHONY: nix-lock
nix-lock:
	nix build .#lockfile --out-link $(O)/nix-lockfile
	cp -L $(O)/nix-lockfile buildroot.lock
	chmod +w buildroot.lock
	nix build .#toolchain-lockfile --out-link $(O)/nix-toolchain-lockfile
	cp -L $(O)/nix-toolchain-lockfile toolchain.lock
	chmod +w toolchain.lock

# Forward everything else to buildroot, tee'd stdout+stderr to $(LOG)
# Explicit local targets above take precedence over this catch-all
%:
	@mkdir -p $(LOG_DIR)
	$(BR2_MAKE) $@ 2>&1 | tee $(LOG); exit $${PIPESTATUS[0]}
