# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright @@COPYRIGHT_YEAR@@ @@COPYRIGHT_HOLDER@@
# @@PROJECT_NAME@@ overlay external makefile.
# Add LINUX_POST_PATCH_HOOKS, custom packages, etc. here.
include $(sort $(wildcard $(BR2_EXTERNAL_@@PROJECT_NAME_UPPER@@_PATH)/package/*/*.mk))
