#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Re-sign the FIT of a finished rootfs.img (mkrootimg.sh --sign-key) in place
# Squashfs and verity tree stay untouched; fails if in sufficient room
#
# Usage: sign-rootimg.sh [-N <engine>] <rootfs.img> <u-boot.dtb> <keydir> <keyname>
#   keydir: directory with <keyname>.key/.crt, or with -N pkcs11 a key prefix
# Requires mkimage, fit_check_sign, dumpimage (U-Boot tools) + fdtput in PATH
set -eu

usage() {
  echo "Usage: $0 [-N <engine>] <rootfs.img> <u-boot.dtb> <keydir> <keyname>" >&2
  exit 1
}

engine=
if [ "${1:-}" = -N ]; then
  [ "$#" -ge 2 ] || usage
  engine=$2
  shift 2
fi
[ "$#" -eq 4 ] || usage

img=$1
ubdtb=$2
keydir=$3
keyname=$4

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# FIT totalsize: FDT header, bytes 4-7 big-endian
fit_size=$(od -An -tu4 --endian=big -j4 -N4 "$img" | tr -d ' ')
head -c "$fit_size" "$img" >"$work/rootfs.itb"

# Squashfs offset (sectors) = last field of rimg's linear target in the boot script
dumpimage -T flat_dt -p 2 -o "$work/boot.scr" "$work/rootfs.itb" >/dev/null
off_sectors=$(sed -n 's/.*linear \/dev\/ubiblock0_${slot_vol} \([0-9]*\).*/\1/p' "$work/boot.scr")
if [ -z "$off_sectors" ]; then
  echo "sign-rootimg: squashfs offset not found in FIT boot script" >&2
  exit 1
fi
off=$((off_sectors * 512))

sig=/configurations/conf-1/signature-1
fdtput -t s "$work/rootfs.itb" $sig key-name-hint "$keyname"
# mkimage -F exits 0 when signing fails, keeping the old signature: drop it first
fdtput -d "$work/rootfs.itb" $sig value
mkimage -q -F -k "$keydir" ${engine:+-N "$engine"} -r "$work/rootfs.itb"

new_size=$(stat -c %s "$work/rootfs.itb")
if [ "$new_size" -gt "$off" ]; then
  echo "sign-rootimg: signed FIT $new_size B > squashfs offset $off B" >&2
  exit 1
fi

if ! fit_check_sign -f "$work/rootfs.itb" -k "$ubdtb" >"$work/check.log" 2>&1; then
  cat "$work/check.log" >&2
  echo "sign-rootimg: signed FIT does not verify against $ubdtb" >&2
  exit 1
fi

# Zero the old FIT area, then write the new FIT
head -c "$off" /dev/zero | dd of="$img" conv=notrunc status=none
dd if="$work/rootfs.itb" of="$img" conv=notrunc status=none

echo "sign-rootimg: FIT $fit_size -> $new_size B (room $off B), signed with $keyname"
