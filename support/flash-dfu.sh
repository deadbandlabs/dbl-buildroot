#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Flash a board in USB boot mode with dfu-util, from a variant's
# images/flashlayout.tsv (bundle-images.sh).
#
# Usage: flash-dfu <flashlayout.tsv>

set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: flash-dfu <flashlayout.tsv>" >&2
  exit 1
fi
cd "$(dirname "$1")"
layout=$(basename "$1")

dfu() {
  dfu-util -w -d 0483:df11 "$@" </dev/null
}

# Detach starts the next stage
# Wait for the device to re-enumerate after dropping
next() {
  dfu -a 0 -e
  sleep 1
}

# dfu-util has no GetPhase (ST AN5275), a fixed order is used:
#   1. ROM loads the FSBL (id 0x01) to RAM
#   2. TF-A loads the FIP (id 0x03) to RAM
#   3. U-Boot stm32prog takes the layout
# RAM rows have IP "none"
for id in 0x01 0x03; do
  dfu -a 0 -D "$(awk -F'\t' -v id="$id" '$2 == id && $5 == "none" { print $7 }' "$layout")"
  next
done

dfu -a 0 -D "$layout"
next

# U-Boot gives every non-RAM row an alt, numbered in id order
# Write 'P' (Program) rows ('E' = Empty)
parts=$(awk -F'\t' '!/^#/ && NF >= 7 && $5 != "none" { print $2, $1, $7 }' "$layout" | sort)
alt=0
while read -r _id opt bin; do
  case $opt in
    *E*) ;;
    *P*) dfu -a "$alt" -D "$bin" ;;
  esac
  alt=$((alt + 1))
done <<EOF
$parts
EOF

# Next alt is "virtual" (0xF1)
# GetPhase byte 0: 0xFE = all written, 0xFF = device error, message from byte 9
phase=$(mktemp -u)
dfu -a "$alt" -U "$phase"
code=$(od -An -tx1 -N1 "$phase" | tr -d ' ')
msg=$(tail -c +10 "$phase")
rm -f "$phase"
if [ "$code" != fe ]; then
  echo "flash-dfu: device reports phase 0x$code: $msg" >&2
  exit 1
fi
echo "flash-dfu: done"
