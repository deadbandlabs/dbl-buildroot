#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Keep configs/myd_yf135_toolchain_defconfig + myd_yf135_external_toolchain.fragment
# consistent with the standalone myd_yf135_defconfig.
#
# toolchain_defconfig is a minimal mirror holding no target packages,
# used to inform what is needed for the host toolchain that matches the target. It is
# updated directly by this script based on common keys, not normally manually updated.
#
# toolchain.fragment must agree with myd_yf135_defconfig however it is used to define
# the EXTERNAL "completed" toolchain configuration used for the target build. Due to
# different keys used, checks are advisory only and need manual updates when flagged.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
main=$here/configs/myd_yf135_defconfig
out=$here/configs/myd_yf135_toolchain_defconfig
frag=$here/configs/myd_yf135_external_toolchain.fragment

# Emit the toolchain defconfig with each tracked symbol's value taken from main
gen() {
  local line sym
  while IFS= read -r line; do
    if [[ $line =~ ^#\ (BR2_[A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
      sym=${BASH_REMATCH[1]}
    elif [[ $line =~ ^(BR2_[A-Za-z0-9_]+)= ]]; then
      sym=${BASH_REMATCH[1]}
    else
      # Header, comment or blank line: keep as-is
      printf '%s\n' "$line"
      continue
    fi

    if main_line=$(grep -m1 -E "^${sym}=" "$main"); then
      printf '%s\n' "$main_line"
    elif main_line=$(grep -m1 -xF "# ${sym} is not set" "$main"); then
      printf '%s\n' "$main_line"
    else
      echo "ERROR: tracked symbol ${sym} is absent from myd_yf135_defconfig" >&2
      return 1
    fi
  done <"$out"
}

# Compare the fragment properties that have an internal + external counterparts
check_fragment() {
  local rc=0 m f
  # libc: BR2_TOOLCHAIN_BUILDROOT_<LIBC> <-> BR2_TOOLCHAIN_EXTERNAL_CUSTOM_<LIBC>
  m=$(sed -nE 's/^BR2_TOOLCHAIN_BUILDROOT_(GLIBC|UCLIBC|MUSL)=y$/\1/p' "$main" | head -1)
  f=$(sed -nE 's/^BR2_TOOLCHAIN_EXTERNAL_CUSTOM_(GLIBC|UCLIBC|MUSL)=y$/\1/p' "$frag" | head -1)
  [[ "$m" == "$f" ]] || {
    echo "fragment libc ($f) disagrees with main ($m)" >&2
    rc=1
  }
  # kernel headers version
  m=$(sed -nE 's/^BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_([0-9_]+)=y$/\1/p' "$main" | head -1)
  f=$(sed -nE 's/^BR2_TOOLCHAIN_EXTERNAL_HEADERS_([0-9_]+)=y$/\1/p' "$frag" | head -1)
  [[ "$m" == "$f" ]] || {
    echo "fragment headers ($f) disagrees with main ($m)" >&2
    rc=1
  }
  # C++ support
  m=$(grep -qxF 'BR2_TOOLCHAIN_BUILDROOT_CXX=y' "$main" && echo y || echo n)
  f=$(grep -qxF 'BR2_TOOLCHAIN_EXTERNAL_CXX=y' "$frag" && echo y || echo n)
  [[ "$m" == "$f" ]] || {
    echo "fragment C++ ($f) disagrees with main ($m)" >&2
    rc=1
  }
  return $rc
}

rc=0

# Sync files in place (fails if a symbol is missing)
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
if gen >"$tmp"; then
  if ! cmp -s "$tmp" "$out"; then
    mv "$tmp" "$out"
    echo "synced $out from myd_yf135_defconfig" >&2
  fi
else
  rc=1
fi

check_fragment || {
  echo "Update $frag to match myd_yf135_defconfig, then re-run." >&2
  rc=1
}

exit $rc
