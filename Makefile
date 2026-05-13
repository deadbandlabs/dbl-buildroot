# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
BUILDROOT_SRC ?= $(shell echo $$BUILDROOT_SRC)

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

# Debug builds reuse release host tools by default through output/debug/host symlink.
# Set SHARE_HOST_FOR_DEBUG=0 to disable and keep separate host trees.
SHARE_HOST_FOR_DEBUG ?= 1

# Download cache kept at the output base so it survives cleaning output dir
# Override with BR2_DL_DIR=/path/to/shared/cache to share across projects
BR2_DL_DIR    ?= $(OUTPUT_BASE)/dl

# Variant config/script paths
RELEASE_DEFCONFIG    := $(CURDIR)/configs/myd_yf135_defconfig
DEBUG_DEFCONFIG      := $(O)/myd_yf135_debug_defconfig
DEBUG_FRAGMENT       := $(CURDIR)/configs/myd_yf135_debug.fragment
PROGRAMMER_DEFCONFIG := $(O)/myd_yf135_programmer_defconfig
PROGRAMMER_FRAGMENT  := $(CURDIR)/configs/myd_yf135_programmer.fragment
GEN_DEBUG_SCRIPT     := $(CURDIR)/support/build/gen-debug-defconfig.sh
SHARE_HOST_SCRIPT    := $(CURDIR)/support/build/share-host-artifacts.sh
BUNDLE_IMAGES_SCRIPT := $(CURDIR)/support/build/bundle-images.sh
FLASHLAYOUT_SRC      := $(CURDIR)/board/myd-yf135/flashlayout.tsv

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
_BASE_DEFCONFIG := $(DEBUG_DEFCONFIG)
_VARIANT_PREP   := regen-debug-defconfig prepare-variant-host-reuse
_BUILD_TARGETS  :=
_UPDATE_LATEST  := true
else ifeq ($(MODE),programmer)
_BASE_DEFCONFIG := $(PROGRAMMER_DEFCONFIG)
_VARIANT_PREP   := regen-programmer-defconfig prepare-variant-host-reuse
# Programmer only needs the loader stack: TF-A pulls in U-Boot and OP-TEE
# via package deps and packs them into fip.bin. Skip kernel/rootfs.
_BUILD_TARGETS  := arm-trusted-firmware
# Programmer is a fragment, not a usable image set; don't repoint `latest`.
_UPDATE_LATEST  := false
else
_BASE_DEFCONFIG := $(RELEASE_DEFCONFIG)
_VARIANT_PREP   :=
_BUILD_TARGETS  :=
_UPDATE_LATEST  := true
endif

# If CONFIG_FRAGMENT is set, merge it over the variant's base config.
# Otherwise apply the base config directly.
ifneq ($(strip $(CONFIG_FRAGMENT)),)
_APPLY_DEFCONFIG = @$(GEN_DEBUG_SCRIPT) $(_BASE_DEFCONFIG) $(CONFIG_FRAGMENT) $(OVERLAY_DEFCONFIG) && $(BR2_MAKE) BR2_DEFCONFIG=$(OVERLAY_DEFCONFIG) defconfig
else ifeq ($(MODE),debug)
_APPLY_DEFCONFIG = $(BR2_MAKE) BR2_DEFCONFIG=$(DEBUG_DEFCONFIG) defconfig
else ifeq ($(MODE),programmer)
_APPLY_DEFCONFIG = $(BR2_MAKE) BR2_DEFCONFIG=$(PROGRAMMER_DEFCONFIG) defconfig
else
_APPLY_DEFCONFIG = $(BR2_MAKE) myd_yf135_defconfig
endif

.DEFAULT_GOAL := all

.PHONY: help all release debug programmer regen-debug-defconfig regen-programmer-defconfig prepare-variant-host-reuse host-toolchain _toolchain-only toolchain

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
	@echo "  make host-toolchain               Build release host toolchain"

# Buildroot defconfigs do not support inheritance. Keep release as source of
# truth and regenerate variant defconfigs from release + variant fragment at
# build time.
regen-debug-defconfig:
	@mkdir -p $(O)
	$(GEN_DEBUG_SCRIPT) $(RELEASE_DEFCONFIG) $(DEBUG_FRAGMENT) $(DEBUG_DEFCONFIG)

regen-programmer-defconfig:
	@mkdir -p $(O)
	$(GEN_DEBUG_SCRIPT) $(RELEASE_DEFCONFIG) $(PROGRAMMER_FRAGMENT) $(PROGRAMMER_DEFCONFIG)

prepare-variant-host-reuse:
	@$(SHARE_HOST_SCRIPT) "$(CURDIR)" "$(RELEASE_O)" "$(O)" "$(SHARE_HOST_FOR_DEBUG)" "$(MAKE)"

all: $(_VARIANT_PREP)
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

host-toolchain:
	$(MAKE) MODE=release _toolchain-only

_toolchain-only:
	@mkdir -p $(O) $(LOG_DIR) $(CCACHE_DIR)
	$(_APPLY_DEFCONFIG)
	$(BR2_MAKE) toolchain

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

# Regenerate buildroot.lock (run after changing package versions in defconfig)
.PHONY: nix-lock
nix-lock:
	nix build .#lockfile --out-link $(O)/nix-lockfile
	cp -L $(O)/nix-lockfile buildroot.lock
	python3 $(CURDIR)/support/build/fix-cargo2-lockfile.py buildroot.lock

# Forward everything else to buildroot, tee'd stdout+stderr to $(LOG)
# Explicit local targets above take precedence over this catch-all
%:
	@mkdir -p $(LOG_DIR)
	$(BR2_MAKE) $@ 2>&1 | tee $(LOG); exit $${PIPESTATUS[0]}
