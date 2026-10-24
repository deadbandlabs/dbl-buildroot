#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Build rootfs slot image:
#   [ FIT (kernel + DT + boot script) | pad to 4 KiB | squashfs ]
#
# Boot script holds squashfs offset + size (512 B sectors) for dm linear
# NB: Loops until stable, offset depends on FIT size, and FIT contains offset
#
# Usage: mkrootimg.sh <zImage> <dtb> <rootfs.squashfs> <out.img>
# Needs mkimage + dtc in PATH
set -eu

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <zImage> <dtb> <rootfs.squashfs> <out.img>" >&2
  exit 1
fi

kernel=$(realpath "$1")
dtb=$(realpath "$2")
squashfs=$(realpath "$3")
out=$4

ALIGN=4096
SECTOR=512

sq_size=$(stat -c %s "$squashfs")
if [ $((sq_size % ALIGN)) -ne 0 ]; then
  echo "mkrootimg: $squashfs is not 4 KiB padded (BR2_TARGET_ROOTFS_SQUASHFS_PAD)" >&2
  exit 1
fi
sq_sectors=$((sq_size / SECTOR))

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# $1 = squashfs offset in sectors
write_fit() {
  # Must stay in sourced script: `run` of env var strips quotes in dm-mod.create
  cat >"$work/boot.scr" <<EOF
setenv dm_rimg "rimg,,,ro,0 ${sq_sectors} linear /dev/ubiblock0_\${slot_vol} $1"
setenv bootargs "ubi.mtd=UBI ubi.block=0,\${slot_vol} dm-mod.waitfor=/dev/ubiblock0_\${slot_vol} dm-mod.create=\\"\${dm_rimg}\\" root=/dev/dm-0 rootfstype=squashfs ro rauc.slot=\${rauc_slot} console=ttySTM0,115200 earlycon \${machine_id_arg}"
bootm \${fitaddr}#conf-1
EOF
  cat >"$work/rootfs.its" <<EOF
/dts-v1/;

/ {
  description = "DBL MYD-YF135 kernel, DT and boot script";
  #address-cells = <1>;

  images {
    kernel-1 {
      description = "Linux zImage";
      data = /incbin/("$kernel");
      type = "kernel_noload";
      arch = "arm";
      os = "linux";
      compression = "none";
      load = <0>;
      entry = <0>;
      hash-1 { algo = "sha256"; };
    };
    fdt-1 {
      description = "Linux DT";
      data = /incbin/("$dtb");
      type = "flat_dt";
      arch = "arm";
      compression = "none";
      hash-1 { algo = "sha256"; };
    };
    script-1 {
      description = "Boot script: cmdline + bootm";
      data = /incbin/("$work/boot.scr");
      type = "script";
      compression = "none";
      hash-1 { algo = "sha256"; };
    };
  };

  configurations {
    default = "conf-1";
    conf-1 {
      kernel = "kernel-1";
      fdt = "fdt-1";
      script = "script-1";
    };
  };
};
EOF
  mkimage -q -f "$work/rootfs.its" "$work/rootfs.itb"
}

off=0
i=0
while :; do
  write_fit $((off / SECTOR))
  fit_size=$(stat -c %s "$work/rootfs.itb")
  new=$(((fit_size + ALIGN - 1) / ALIGN * ALIGN))
  [ "$new" -eq "$off" ] && break
  off=$new
  i=$((i + 1))
  if [ "$i" -gt 4 ]; then
    echo "mkrootimg: FIT offset did not converge" >&2
    exit 1
  fi
done

cp "$work/rootfs.itb" "$out"
truncate -s "$off" "$out"
cat "$squashfs" >>"$out"

echo "mkrootimg: FIT $fit_size B, squashfs at $off B ($((off / SECTOR)) sectors), $sq_size B ($sq_sectors sectors), total $(stat -c %s "$out") B"
