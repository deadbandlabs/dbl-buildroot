#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
# RAUC pre-install hook: wipe overlay volume before update
# Ensures stale overlay data doesn't persist across updates
#
# Size must match ubinize.cfg vol_size for [overlay]
# (regenerate via board/myd-yf135/ubinize_check.py)
set -e
OVERLAY_SIZE=71233536
echo "rauc-wipe-overlay: formatting overlay volume (${OVERLAY_SIZE} bytes)"
ubirmvol /dev/ubi0_3 -y
ubimkvol /dev/ubi0_3 -n 3 -N overlay -s "${OVERLAY_SIZE}"
echo "rauc-wipe-overlay: done"
exit 0
