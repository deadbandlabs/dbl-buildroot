# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
include $(sort $(wildcard $(BR2_EXTERNAL_MYD_YF135_PATH)/package/*/*.mk))

# Copy the board DTS into the kernel source tree after patching as a post-patch
# hook and append the dtb to the ST Makefile at build time:
#
# CUSTOM_DTS_PATH would normally be used, but copies to arch/arm/boot/dts/, but
# Linux 6.12+ refactored STM32MP device trees to arch/arm/boot/dts/st/, which is 
# incompatible with this standard method
define LINUX_MYD_YF135_COPY_DTS
	cp $(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/dts/stm32mp135d-myd-yf135.dts \
		$(@D)/arch/arm/boot/dts/st/stm32mp135d-myd-yf135.dts
	grep -q 'stm32mp135d-myd-yf135\.dtb' $(@D)/arch/arm/boot/dts/st/Makefile || \
		printf '\ndtb-$$(CONFIG_ARCH_STM32) += stm32mp135d-myd-yf135.dtb\n' \
			>> $(@D)/arch/arm/boot/dts/st/Makefile
endef
LINUX_POST_PATCH_HOOKS += LINUX_MYD_YF135_COPY_DTS
