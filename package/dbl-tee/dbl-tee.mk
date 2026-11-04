# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
################################################################################
#
# dbl-tee
#
################################################################################

DBL_TEE_VERSION = 1
DBL_TEE_SITE = $(DBL_TEE_PKGDIR)/src
DBL_TEE_SITE_METHOD = local
DBL_TEE_SOURCE =
DBL_TEE_LICENSE = GPL-2.0-or-later
DBL_TEE_DEPENDENCIES = optee-client

define DBL_TEE_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -Wall -Wextra \
		-I$(@D)/ta/dbl_include -o $(@D)/dbl-tee $(@D)/cli/dbl-tee.c -lteec
endef

define DBL_TEE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/dbl-tee $(TARGET_DIR)/usr/bin/dbl-tee
endef

ifeq ($(BR2_PACKAGE_DBL_TEE),y)
DBL_TEE_TAS = dbl_consent dbl_deviceid
DBL_TEE_TA_DIR = $(DBL_TEE_PKGDIR)/src/ta
define OPTEE_OS_DBL_TEE_COPY_TAS
	cp -r $(DBL_TEE_TA_DIR)/dbl_include $(addprefix $(DBL_TEE_TA_DIR)/,$(DBL_TEE_TAS)) $(@D)/ta/
endef
OPTEE_OS_PRE_BUILD_HOOKS += OPTEE_OS_DBL_TEE_COPY_TAS
OPTEE_OS_MAKE_OPTS += \
	CFG_TA_MBEDTLS_SELF_TEST=n \
	CFG_IN_TREE_EARLY_TAS="$(foreach ta,$(DBL_TEE_TAS),$(ta)/$(shell \
		sed -n 's/^user-ta-uuid := //p' $(DBL_TEE_TA_DIR)/$(ta)/user_ta.mk))"
endif

$(eval $(generic-package))
