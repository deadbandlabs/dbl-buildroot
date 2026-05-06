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

# Latest U-Boot DTC requires libyaml. Directly add host-libyaml as an
# order-only prerequisite of U-Boot's build stamp so it is guaranteed to be
# installed into output/host/ before the DTC Makefile runs.
$(UBOOT_DIR)/.stamp_built: | host-libyaml

# Copy the board DTS into the U-Boot source tree after patching
# dtb-y cannot be passed on the make command line because scripts/Makefile.lib
# now processes it globally, causing scripts_basic load DTB from incorrect dir.
# Instead, inject it into arch/arm/dts/Makefile.
define UBOOT_MYD_YF135_COPY_DTS
	cp $(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/dts/stm32mp135d-myd-yf135.dts \
		$(BR2_EXTERNAL_MYD_YF135_PATH)/board/myd-yf135/dts/stm32mp135d-myd-yf135-u-boot.dtsi \
		$(@D)/arch/arm/dts/
	grep -q 'stm32mp135d-myd-yf135\.dtb' $(@D)/arch/arm/dts/Makefile || \
		printf '\ndtb-$$(CONFIG_STM32MP) += stm32mp135d-myd-yf135.dtb\n' \
			>> $(@D)/arch/arm/dts/Makefile
endef
UBOOT_POST_PATCH_HOOKS += UBOOT_MYD_YF135_COPY_DTS
