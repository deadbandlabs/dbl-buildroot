# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Makefile fragment for parent repos consuming the dbl-buildroot submodule
#
# Parent Makefile minimal usage:
#
#   DBL_BR_OVERLAY  := overlay
#   DBL_BR_FRAGMENT := overlay/syncro-os.fragment
#   include modules/dbl-buildroot/support/parent.mk
#
# Provides:
#   make build                        # nix build (.?submodules=1 wrapped)
#   make sdk                          # nix build .#sdk
#   make develop                      # nix develop
#   make update-dbl-buildroot         # bump submodule + propagate SHA
#   make update-dbl-buildroot REF=... # bump to a specific ref
#   make check-dbl-buildroot          # SHA pin drift check
#   make <anything-else>              # forwards to submodule Makefile with
#                                       BR2_EXTERNAL_EXTRA + CONFIG_FRAGMENT

DBL_BR_DIR      ?= modules/dbl-buildroot
DBL_BR_HELPERS  := $(DBL_BR_DIR)/support/parent
DBL_BR_OVERLAY  ?=
DBL_BR_FRAGMENT ?=
# Resolve to absolute paths so the submodule's Makefile (running with
# cwd = $DBL_BR_DIR) sees correct locations.
REPO_ROOT       := $(CURDIR)
REF             ?= origin/main

# `?submodules=1` makes nix include the submodule files in the flake source.
# Required because the submodule is a separate git context from the parent.
DBL_BR_FLAKEREF ?= .?submodules=1

.PHONY: build sdk develop update-dbl-buildroot check-dbl-buildroot

build:
	nix build '$(DBL_BR_FLAKEREF)'

sdk:
	nix build '$(DBL_BR_FLAKEREF)#sdk'

develop:
	nix develop '$(DBL_BR_FLAKEREF)'

update-dbl-buildroot:
	$(DBL_BR_HELPERS)/update.sh $(REF)

check-dbl-buildroot:
	$(DBL_BR_HELPERS)/check-pinned-shas.sh

# --- Submodule Makefile forwarder ---
# Any target not defined above forwards to the submodule's Makefile, with
# the parent's overlay + fragment injected. Empty DBL_BR_OVERLAY/_FRAGMENT
# disable the corresponding flag (so consumers without an overlay still work).
DBL_BR_FORWARD_FLAGS :=
ifneq ($(strip $(DBL_BR_OVERLAY)),)
DBL_BR_FORWARD_FLAGS += BR2_EXTERNAL_EXTRA=$(REPO_ROOT)/$(DBL_BR_OVERLAY)
endif
ifneq ($(strip $(DBL_BR_FRAGMENT)),)
DBL_BR_FORWARD_FLAGS += CONFIG_FRAGMENT=$(REPO_ROOT)/$(DBL_BR_FRAGMENT)
endif

%:
	$(MAKE) -C $(REPO_ROOT)/$(DBL_BR_DIR) $(DBL_BR_FORWARD_FLAGS) $@
