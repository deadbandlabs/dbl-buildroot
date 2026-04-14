BUILDROOT_SRC ?= $(shell echo $$BUILDROOT_SRC)
O             ?= $(CURDIR)/output
# Download cache kept at the project root so it survives cleaning output dir
# Override with BR2_DL_DIR=/path/to/shared/cache to share across projects
BR2_DL_DIR    ?= $(CURDIR)/dl

# Derive the kernel source directory from the version in the defconfig so
# this stays in sync automatically if the version is ever bumped
LINUX_VERSION := $(shell grep BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE \
                     $(CURDIR)/configs/myd_yf135_defconfig | cut -d'"' -f2)
LINUX_SRC     := $(O)/build/linux-$(LINUX_VERSION)
LINUX_CONFIG  := $(CURDIR)/board/myd-yf135/linux.config

BR2_MAKE = $(MAKE) -C $(BUILDROOT_SRC) O=$(O) BR2_EXTERNAL=$(CURDIR) BR2_DL_DIR=$(BR2_DL_DIR)

# Build logs:
# One timestamped file per invocation, stored in output/logs/ sorted chronologically by filename
# Override with make LOG=/tmp/other.log
LOG_DIR ?= $(O)/logs
LOG     ?= $(LOG_DIR)/$(shell date +%Y%m%d-%H%M%S).log

# Default: full buildroot build
.DEFAULT_GOAL := all

# Seed board/myd-yf135/linux.config from the upstream multi_v7_defconfig
# Run once before the first full build; afterwards use:
#   make linux-menuconfig (interactive kernel config)
#   make linux-update-config (writes changes back to board/myd-yf135/linux.config to commit)
.PHONY: linux-config-init
linux-config-init:
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

# Forward everything else to buildroot, tee'd stdout+stderr to $(LOG)
# Explicit local targets above take precedence over this catch-all
%:
	@mkdir -p $(LOG_DIR)
	$(BR2_MAKE) $@ 2>&1 | tee $(LOG); exit $${PIPESTATUS[0]}
