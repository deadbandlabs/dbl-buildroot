#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Flash a board in USB DFU mode with dfu-util,
# with bundle-images.sh generated images/flashlayout.tsv
#
# USAGE: flash-dfu <flashlayout.tsv>
# /ENDUSAGE
set -eu

usage() {
  sed -n '/^# \/ENDUSAGE/q; /^# USAGE:/,$s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
cd "$(dirname "$1")"
layout=$(basename "$1")

dfu() {
  dfu-util -w -d 0483:df11 "$@" </dev/null
}

say() {
  echo "flash-dfu: $*"
}

# Detach begins next stage, then waits for device to re-enumerate
next() {
  dfu -a 0 -e
  sleep 1
}

# dfu-util has no GetPhase (ST AN5275), a fixed order is used:
#   1. ROM loads the FSBL (id 0x01) to RAM
#   2. TF-A loads the FIP (id 0x03) to RAM
#   3. FIP U-Boot stm32prog loads the remaining entries from flashlayout.tsv
ram_img() {
  awk -F'\t' -v id="$1" '$2 == id && $5 == "none" { print $7 }' "$layout"
}
parts=$(awk -F'\t' '!/^#/ && NF >= 7 && $5 != "none" { print $2, $1, $3, $6, $7 }' "$layout" | sort)

say "layout $PWD/$layout"
say "waiting for USB DFU device 0483:df11"
say "FSBL -> RAM: $(ram_img 0x01)"
dfu -a 0 -D "$(ram_img 0x01)"
next
say "FIP -> RAM: $(ram_img 0x03)"
dfu -a 0 -D "$(ram_img 0x03)"

# For RAM-only images: detach without waiting for the DFU device
if [ -z "$parts" ]; then
  dfu-util -d 0483:df11 -a 0 -e </dev/null
  say "loaded, nothing to write"
  exit 0
fi
next

say "layout -> stm32prog"
dfu -a 0 -D "$layout"
next

# Write 'P' (Program) rows ('E' = Empty)
alt=0
while read -r _id opt name off bin; do
  case $opt in
    *E*) say "$name ($off): erase only" ;;
    *P*)
      say "$name ($off) <- $bin"
      dfu -a "$alt" -D "$bin"
      ;;
  esac
  alt=$((alt + 1))
done <<EOF
$parts
EOF

# Next alt is "virtual" (0xF1)
# GetPhase byte 0: 0xFE = all written, 0xFF = device error, message from byte 9
phase=$(mktemp -u)
trap 'rm -f "$phase"' EXIT
dfu -a "$alt" -U "$phase"
code=$(od -An -tx1 -N1 "$phase" | tr -d ' ')
if [ "$code" != fe ]; then
  echo "flash-dfu: device reports phase 0x$code: $(tail -c +10 "$phase")" >&2
  exit 1
fi
say "done"
