# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
BUILDROOT_SRC ?= $(shell echo $$BUILDROOT_SRC)

# Build/output paths
MODE          ?= release
O             ?= $(CURDIR)/output/$(MODE)
RELEASE_O     ?= $(CURDIR)/output/release
CCACHE_DIR    ?= $(CURDIR)/output/ccache

# Debug builds reuse release host tools by default through output/debug/host symlink.
# Set SHARE_HOST_FOR_DEBUG=0 to disable and keep separate host trees.
SHARE_HOST_FOR_DEBUG ?= 1

# Download cache kept at the project root so it survives cleaning output dir
# Override with BR2_DL_DIR=/path/to/shared/cache to share across projects
BR2_DL_DIR    ?= $(CURDIR)/dl

# Variant config/script paths
RELEASE_DEFCONFIG := $(CURDIR)/configs/myd_yf135_defconfig
DEBUG_DEFCONFIG   := $(O)/myd_yf135_debug_defconfig
DEBUG_FRAGMENT    := $(CURDIR)/configs/myd_yf135_debug.fragment
GEN_DEBUG_SCRIPT  := $(CURDIR)/support/build/gen-debug-defconfig.sh
SHARE_HOST_SCRIPT := $(CURDIR)/support/build/share-host-artifacts.sh

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

# Host tools (including host ccache) depend on shared libs in $(O)/host/lib{,64}.
# In some environments (e.g. Nix), those paths are not in the dynamic linker
# default search path, so explicitly prepend them.
HOST_LIB_PATHS = $(O)/host/lib:$(O)/host/lib64
BR2_ENV = LD_LIBRARY_PATH="$(HOST_LIB_PATHS):$$LD_LIBRARY_PATH"
BR2_ARGS = -C $(BUILDROOT_SRC) O=$(O) BR2_EXTERNAL=$(BR2_EXTERNAL) BR2_DL_DIR=$(BR2_DL_DIR) BR2_CCACHE_DIR=$(CCACHE_DIR)
BR2_MAKE = $(BR2_ENV) $(MAKE) $(BR2_ARGS)

# Build logs:
# One timestamped file per invocation, stored in output/logs/ sorted chronologically by filename
# Override with make LOG=/tmp/other.log
LOG_DIR ?= $(O)/logs
LOG     ?= $(LOG_DIR)/$(shell date +%Y%m%d-%H%M%S).log

# MODE selects the build variant (release/debug) and the output directory.
# release = output/release/   debug = output/debug/
# Override O directly to use a custom output path.
ifeq ($(MODE),debug)
_BASE_DEFCONFIG := $(DEBUG_DEFCONFIG)
_VARIANT_PREP   := regen-debug-defconfig prepare-debug-host-reuse
else
_BASE_DEFCONFIG := $(RELEASE_DEFCONFIG)
_VARIANT_PREP   :=
endif

# If CONFIG_FRAGMENT is set, merge it over the variant's base config.
# Otherwise apply the base config directly.
ifneq ($(strip $(CONFIG_FRAGMENT)),)
_APPLY_DEFCONFIG = @$(GEN_DEBUG_SCRIPT) $(_BASE_DEFCONFIG) $(CONFIG_FRAGMENT) $(OVERLAY_DEFCONFIG) && $(BR2_MAKE) BR2_DEFCONFIG=$(OVERLAY_DEFCONFIG) defconfig
else ifeq ($(MODE),debug)
_APPLY_DEFCONFIG = $(BR2_MAKE) BR2_DEFCONFIG=$(DEBUG_DEFCONFIG) defconfig
else
_APPLY_DEFCONFIG = $(BR2_MAKE) myd_yf135_defconfig
endif

.DEFAULT_GOAL := all

.PHONY: help all release debug regen-debug-defconfig prepare-debug-host-reuse host-toolchain toolchain

help:
	@echo "Common targets:"
	@echo "  make                         Build release variant"
	@echo "  MODE=debug make              Build debug variant"
	@echo "  make release                 Alias for release build"
	@echo "  make debug                   Alias for debug build"
	@echo "  make regen-debug-defconfig   Regenerate debug defconfig"
	@echo "  make host-toolchain          Build release host toolchain"

# Buildroot defconfigs do not support inheritance. Keep release as source of
# truth and regenerate debug defconfig from release + debug fragment at build time.
regen-debug-defconfig:
	@mkdir -p $(O)
	$(GEN_DEBUG_SCRIPT) $(RELEASE_DEFCONFIG) $(DEBUG_FRAGMENT) $(DEBUG_DEFCONFIG)

prepare-debug-host-reuse:
	@$(SHARE_HOST_SCRIPT) "$(CURDIR)" "$(RELEASE_O)" "$(O)" "$(SHARE_HOST_FOR_DEBUG)" "$(MAKE)"

all: $(_VARIANT_PREP)
	@mkdir -p $(O) $(LOG_DIR) $(CCACHE_DIR)
	$(_APPLY_DEFCONFIG)
	$(BR2_MAKE) 2>&1 | tee $(LOG); exit $${PIPESTATUS[0]}
	@ln -sfn $(MODE) $(CURDIR)/output/latest
	@echo "INFO: output/latest -> $(MODE)"

release:
	$(MAKE) MODE=release all

debug:
	$(MAKE) MODE=debug all

host-toolchain:
	$(MAKE) MODE=release toolchain

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
