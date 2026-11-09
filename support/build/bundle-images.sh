#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Bundle programmer artefacts into a variant's images/ directory and write a
# self-contained flashlayout.tsv whose binary paths resolve relative to that
# directory.
#
# With a consent images dir, also bundles fip-consent.bin and writes
# consent.tsv as FSBL + consent FIP loaded to RAM only
#
# Used by both the make and nix builds.
#
# USAGE: bundle-images.sh <variant_images_dir> <programmer_images_dir> <src_tsv> [<consent_images_dir>]
# /ENDUSAGE
set -eu

usage() {
  sed -n '/^# \/ENDUSAGE/q; /^# USAGE:/,$s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

[ "$#" -eq 3 ] || [ "$#" -eq 4 ] || usage

variant_images=$1
programmer_images=$2
src_tsv=$3
consent_images=${4:-}

prog_stm32=$(find "$programmer_images" -maxdepth 1 -name 'tf-a-*.stm32' -print -quit 2>/dev/null)
if [ -z "$prog_stm32" ]; then
  echo "bundle-images: no tf-a-*.stm32 in $programmer_images" >&2
  exit 1
fi
if [ ! -f "$programmer_images/fip.bin" ]; then
  echo "bundle-images: missing $programmer_images/fip.bin" >&2
  exit 1
fi

cp "$prog_stm32" "$variant_images/tf-a-programmer.stm32"
cp "$programmer_images/fip.bin" "$variant_images/fip-programmer.bin"

sed -E \
  -e 's|\.\./\.\./output/programmer/images/tf-a-[^[:space:]]*\.stm32|tf-a-programmer.stm32|g' \
  -e 's|\.\./\.\./output/programmer/images/fip\.bin|fip-programmer.bin|g' \
  -e 's|\.\./\.\./output/latest/images/||g' \
  "$src_tsv" >"$variant_images/flashlayout.tsv"

if [ -n "$consent_images" ]; then
  consent_stm32=$(find "$consent_images" -maxdepth 1 -name 'tf-a-*.stm32' -print -quit 2>/dev/null)
  if [ -z "$consent_stm32" ] || [ ! -f "$consent_images/fip.bin" ]; then
    echo "bundle-images: missing tf-a-*.stm32 or fip.bin in $consent_images" >&2
    exit 1
  fi
  cp "$consent_stm32" "$variant_images/tf-a-consent.stm32"
  cp "$consent_images/fip.bin" "$variant_images/fip-consent.bin"
  # flashlayout.tsv header + RAM rows (IP "none"), pointed at the consent files
  if ! awk -F'\t' -v OFS='\t' '
    /^#Opt/ { print; next }
    /^#/ || NF < 7 || $5 != "none" { next }
    $7 == "tf-a-programmer.stm32" { $7 = "tf-a-consent.stm32"; n++ }
    $7 == "fip-programmer.bin" { $7 = "fip-consent.bin"; n++ }
    { print }
    END { exit n != 2 }
  ' "$variant_images/flashlayout.tsv" >"$variant_images/consent.tsv"; then
    echo "bundle-images: consent.tsv requires RAM rows from flashlayout.tsv" >&2
    exit 1
  fi
fi
