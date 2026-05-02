# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright @@COPYRIGHT_YEAR@@ @@COPYRIGHT_HOLDER@@
DBL_BR_OVERLAY  := overlay
DBL_BR_FRAGMENT := overlay/@@PROJECT_NAME@@.fragment

include modules/dbl-buildroot/support/parent.mk

# Bare `make` = forward `all` to submodule (interactive shell-mode build).
# Use `make build` for the hermetic nix-build path.
.DEFAULT_GOAL := all
