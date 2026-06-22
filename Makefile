# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
# BUILDROOT_SRC is inherited from the environment (set by the nix dev shell)

# Build/output paths.
# OUTPUT_BASE anchors all build artefacts (output/, dl/). When this Makefile
# is invoked directly (developing the submodule), it defaults to the submodule
# root. When invoked via parent.mk from a superproject, parent.mk overrides
# OUTPUT_BASE so artefacts land in the parent repo, not inside the submodule.
OUTPUT_BASE   ?= $(CURDIR)
MODE          ?= release
O             ?= $(OUTPUT_BASE)/output/$(MODE)
RELEASE_O     ?= $(OUTPUT_BASE)/output/release
CCACHE_DIR    ?= $(OUTPUT_BASE)/output/ccache

# Download cache kept at the output base so it survives cleaning output dir
# Override with BR2_DL_DIR=/path/to/shared/cache to share across projects
BR2_DL_DIR    ?= $(OUTPUT_BASE)/dl

# Variant config/script paths
RELEASE_DEFCONFIG    := $(CURDIR)/configs/myd_yf135_defconfig
DEBUG_DEFCONFIG      := $(O)/myd_yf135_debug_defconfig
DEBUG_FRAGMENT       := $(CURDIR)/configs/myd_yf135_debug.fragment
PROGRAMMER_DEFCONFIG := $(O)/myd_yf135_programmer_defconfig
PROGRAMMER_FRAGMENT  := $(CURDIR)/configs/myd_yf135_programmer.fragment
_HOST_PYTHON3        := $(RELEASE_O)/host/bin/python3
_PYTHON3             := $(if $(wildcard $(_HOST_PYTHON3)),$(_HOST_PYTHON3),python3)
MERGE_DEFCONFIG      := $(_PYTHON3) $(CURDIR)/support/build/merge-defconfig.py
CONFIG_FRAGMENT_DEBUG ?=
BUNDLE_IMAGES_SCRIPT := $(CURDIR)/support/build/bundle-images.sh
FLASHLAYOUT_SRC      := $(CURDIR)/board/myd-yf135/flashlayout.tsv

# When set, target will use external toolchain when TOOLCHAIN_SDK points at a existing SDK
# The nix dev/ci shells export TOOLCHAIN_SDK (a Nix .#toolchain build, from Cachix)
# Purely Makefile builds use can run `make toolchain` below, pass TOOLCHAIN_SDK=<path>,
# or use any external toolchain
# When empty, the internal toolchain is built with the target
TOOLCHAIN_SDK ?=

# Merge external-toolchain fragment description for TOOLCHAIN_SDK builds
EXTERNAL_TOOLCHAIN_FRAGMENT ?= $(CURDIR)/configs/myd_yf135_external_toolchain.fragment
_TC_PATH_FRAGMENT           := $(O)/external-toolchain-path.fragment

# `make toolchain` builds a relocatable SDK from the toolchain-only defconfig.
TOOLCHAIN_DEFCONFIG := $(CURDIR)/configs/myd_yf135_toolchain_defconfig
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
LINUX_CONFIG  := $(CURDIR)/board/myd-yf135/linux.config

# Host tools self-resolve libs via RUNPATH=$ORIGIN/../lib (via HOSTLDFLAGS),
# Avoid setting LD_LIBRARY_PATH to prevent leaking into target cross-linked libs
# when -rpath-link is absent, picking up host x86 libs (libcrypt.so) and failing with "file format not recognized".
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
# Override O directly to use a custom output path.
#
# release/debug builds chain a programmer build in output/programmer/
# Set BUILD_PROGRAMMER=0 to opt out
BUILD_PROGRAMMER ?= 1

ifeq ($(MODE),debug)
_BUILD_TARGETS  :=
_UPDATE_LATEST  := true
else ifeq ($(MODE),programmer)
_BUILD_TARGETS  := arm-trusted-firmware
_UPDATE_LATEST  := false
else
_BUILD_TARGETS  :=
_UPDATE_LATEST  := true
endif

# Compose the merge chain for this mode:
#   release    = RELEASE_DEFCONFIG + CONFIG_FRAGMENT
#   debug      = RELEASE_DEFCONFIG + CONFIG_FRAGMENT + DEBUG_FRAGMENT + CONFIG_FRAGMENT_DEBUG
#   programmer = RELEASE_DEFCONFIG + PROGRAMMER_FRAGMENT
# Empty/unset slots are filtered out. With no deltas, fall back to a plain `defconfig` call.
_MERGE_DELTAS :=
ifeq ($(MODE),debug)
  _MERGE_DELTAS += $(strip $(CONFIG_FRAGMENT))
  _MERGE_DELTAS += $(DEBUG_FRAGMENT)
  _MERGE_DELTAS += $(strip $(CONFIG_FRAGMENT_DEBUG))
else ifeq ($(MODE),programmer)
  _MERGE_DELTAS += $(PROGRAMMER_FRAGMENT)
else
  _MERGE_DELTAS += $(strip $(CONFIG_FRAGMENT))
endif
_MERGE_DELTAS := $(strip $(_MERGE_DELTAS))

# Append external toolchain SDK properties last to override the base internal-toolchain selection
ifneq ($(strip $(TOOLCHAIN_SDK)),)
  _MERGE_DELTAS += $(EXTERNAL_TOOLCHAIN_FRAGMENT) $(_TC_PATH_FRAGMENT)
  _WRITE_TC_PATH = @mkdir -p $(O) && printf 'BR2_TOOLCHAIN_EXTERNAL_PATH="%s"\n' '$(TOOLCHAIN_SDK)' > $(_TC_PATH_FRAGMENT)
else
  _WRITE_TC_PATH = @true
endif

# Append extra rootfs overlays last to stack onto base + fragment overlays
ifneq ($(strip $(EXTRA_ROOTFS_OVERLAYS)),)
  _MERGE_DELTAS += $(_ROOTFS_OVERLAY_FRAGMENT)
  _WRITE_ROOTFS_OVERLAY = mkdir -p $(O) && printf 'BR2_ROOTFS_OVERLAY="%s"\n' '$(EXTRA_ROOTFS_OVERLAYS)' > $(_ROOTFS_OVERLAY_FRAGMENT)
else
  _WRITE_ROOTFS_OVERLAY = true
endif

ifneq ($(_MERGE_DELTAS),)
_APPLY_DEFCONFIG = $(_WRITE_TC_PATH) && $(_WRITE_ROOTFS_OVERLAY) && $(MERGE_DEFCONFIG) $(OVERLAY_DEFCONFIG) $(RELEASE_DEFCONFIG) $(_MERGE_DELTAS) && $(BR2_MAKE) BR2_DEFCONFIG=$(OVERLAY_DEFCONFIG) defconfig
else
_APPLY_DEFCONFIG = $(BR2_MAKE) myd_yf135_defconfig
endif

.DEFAULT_GOAL := all

.PHONY: help all release debug programmer regen-debug-defconfig regen-programmer-defconfig regen-toolchain-defconfig toolchain

help:
	@echo "Common targets:"
	@echo "  make                              Build release variant"
	@echo "  MODE=debug make                   Build debug variant"
	@echo "  MODE=programmer make              Build programmer (USB DFU) variant (TF-A + FIP only)"
	@echo "  make release                      Alias for release build"
	@echo "  make debug                        Alias for debug build"
	@echo "  make programmer                   Alias for programmer build"
	@echo "  make regen-debug-defconfig        Regenerate debug defconfig"
	@echo "  make regen-programmer-defconfig   Regenerate programmer defconfig"
	@echo "  make regen-toolchain-defconfig    Regenerate toolchain defconfig from main"
	@echo "  make toolchain                    Build relocatable external-toolchain SDK"

# Buildroot defconfigs do not support inheritance. Keep release as source of
# truth and regenerate variant defconfigs from release + variant fragment at
# build time.
regen-debug-defconfig:
	@mkdir -p $(O)
	$(MERGE_DEFCONFIG) $(DEBUG_DEFCONFIG) $(RELEASE_DEFCONFIG) $(strip $(CONFIG_FRAGMENT)) $(DEBUG_FRAGMENT) $(strip $(CONFIG_FRAGMENT_DEBUG))

regen-programmer-defconfig:
	@mkdir -p $(O)
	$(MERGE_DEFCONFIG) $(PROGRAMMER_DEFCONFIG) $(RELEASE_DEFCONFIG) $(PROGRAMMER_FRAGMENT)

# Sync the toolchain defconfig's tracked symbol values from the main defconfig (run in pre-commit)
regen-toolchain-defconfig:
	$(CURDIR)/support/pre-commit/check-toolchain-defconfig.sh

all:
	@mkdir -p $(O) $(LOG_DIR) $(CCACHE_DIR)
	$(_APPLY_DEFCONFIG)
	$(BR2_MAKE) $(_BUILD_TARGETS) 2>&1 | tee $(LOG); exit $${PIPESTATUS[0]}
	@if [ "$(_UPDATE_LATEST)" = "true" ]; then \
		ln -sfn $(MODE) $(OUTPUT_BASE)/output/latest; \
		echo "INFO: $(OUTPUT_BASE)/output/latest -> $(MODE)"; \
	fi
ifneq ($(MODE),programmer)
ifeq ($(BUILD_PROGRAMMER),1)
	$(MAKE) MODE=programmer OUTPUT_BASE=$(OUTPUT_BASE) BR2_DL_DIR=$(BR2_DL_DIR) BR2_EXTERNAL='$(BR2_EXTERNAL)' all
	@if [ -f $(FLASHLAYOUT_SRC) ]; then \
		$(BUNDLE_IMAGES_SCRIPT) \
			$(O)/images \
			$(OUTPUT_BASE)/output/programmer/images \
			$(FLASHLAYOUT_SRC); \
		echo "INFO: Generated $(O)/images/flashlayout.tsv"; \
	fi
endif
endif

release:
	$(MAKE) MODE=release all

debug:
	$(MAKE) MODE=debug all

programmer:
	$(MAKE) MODE=programmer all

# Build SDK from the toolchain-only defconfig and unpack it to $(TOOLCHAIN_SDK_OUT)
# Mirrors the Nix stage-1 (.#toolchain): make sdk -> untar -> relocate-sdk.sh
# Use with a target build with TOOLCHAIN_SDK=<path>.
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

myd_yf135_debug_defconfig: regen-debug-defconfig
	$(BR2_MAKE) BR2_DEFCONFIG=$(DEBUG_DEFCONFIG) defconfig

# If bootstrapping a new repo, see board/myd-yf135/linux.config from the upstream multi_v7_defconfig
# Run once before the first full build; afterwards use:
#   make linux-menuconfig (interactive kernel config)
#   make linux-update-config (writes changes back to board/myd-yf135/linux.config to commit)
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
