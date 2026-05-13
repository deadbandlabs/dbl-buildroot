#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Bundle programmer artefacts into a variant's images/ directory and write a
# self-contained flashlayout.tsv whose binary paths resolve relative to that
# directory.
#
# Used by both the make and nix builds.
#
# Usage: bundle-images.sh <variant_images_dir> <programmer_images_dir> <src_tsv>
set -eu

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <variant_images_dir> <programmer_images_dir> <src_tsv>" >&2
  exit 1
fi

variant_images=$1
programmer_images=$2
src_tsv=$3

prog_stm32=$(find "$programmer_images" -maxdepth 1 -name 'tf-a-*.stm32' 2>/dev/null)
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
