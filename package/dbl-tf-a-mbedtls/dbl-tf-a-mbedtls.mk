# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
################################################################################
#
# dbl-tf-a-mbedtls
#
################################################################################

DBL_TF_A_MBEDTLS_VERSION = 3.6.7
DBL_TF_A_MBEDTLS_SITE = https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$(DBL_TF_A_MBEDTLS_VERSION)
DBL_TF_A_MBEDTLS_SOURCE = mbedtls-$(DBL_TF_A_MBEDTLS_VERSION).tar.bz2
DBL_TF_A_MBEDTLS_LICENSE = Apache-2.0 or GPL-2.0+
DBL_TF_A_MBEDTLS_LICENSE_FILES = LICENSE
DBL_TF_A_MBEDTLS_CPE_ID_VENDOR = arm
DBL_TF_A_MBEDTLS_CPE_ID_PRODUCT = mbed_tls
DBL_TF_A_MBEDTLS_INSTALL_TARGET = NO

$(eval $(generic-package))
