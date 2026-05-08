#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
# RAUC post-install hook: update FIP (TF-A + OP-TEE + U-Boot) on SPI-NAND
#
# Expects fip.bin as first arg (from RAUC bundle).
# Writes to inactive FIP bank (A/B mirroring per TF-A FWU layout).
#
# NAND FIP partitions (from DTS):
#   fip-a1: 0x200000  4 MB  Bank A primary
#   fip-a2: 0x600000  4 MB  Bank A backup
#   fip-b1: 0xa00000  4 MB  Bank B primary
#   fip-b2: 0xe00000  4 MB  Bank B backup
#
# Uses /dev/mtd/by-name/ symlinks for robustness against mtd renumbering.

set -e

FIP="$1"

if [ -z "$FIP" ] || [ ! -f "$FIP" ]; then
  echo "rauc-update-fip: no fip.bin provided, skipping"
  exit 0
fi

FIP_SIZE=$(wc -c <"$FIP")
FIP_MAX=4194304 # 4 MB
if [ "$FIP_SIZE" -gt "$FIP_MAX" ]; then
  echo "rauc-update-fip: FIP too large (${FIP_SIZE} > ${FIP_MAX})"
  exit 1
fi

# Determine active rootfs slot
ACTIVE=$(fw_printenv -n bootroot 2>/dev/null || echo "rootfs_a")

if [ "$ACTIVE" = "rootfs_a" ]; then
  echo "rauc-update-fip: active=rootfs_a, updating bank B"
  FIP_PRI="/dev/mtd/by-name/fip-b1"
  FIP_BAK="/dev/mtd/by-name/fip-b2"
else
  echo "rauc-update-fip: active=rootfs_b, updating bank A"
  FIP_PRI="/dev/mtd/by-name/fip-a1"
  FIP_BAK="/dev/mtd/by-name/fip-a2"
fi

echo "rauc-update-fip: writing ${FIP_SIZE} bytes to ${FIP_PRI}"
flashcp -v "$FIP" "$FIP_PRI"

echo "rauc-update-fip: mirroring to ${FIP_BAK}"
flashcp -v "$FIP" "$FIP_BAK"

echo "rauc-update-fip: done. Reboot to activate."
exit 0
