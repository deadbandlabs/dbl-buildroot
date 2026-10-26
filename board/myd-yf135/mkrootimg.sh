#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Build rootfs slot image:
#   [ FIT (kernel + DT + boot script) | pad to 4 KiB | squashfs ]
#   --verity: [ FIT | pad to 4 KiB | squashfs | dm-verity hash tree ]
#
# At boot, the boot script maps the squashfs (past the FIT) to /dev/dm-0.
# With --verity, the root is /dev/dm-1 instead: it checks every block of
# dm-0 against a root hash stored in the FIT.
# All of dm-1 is read by read-rootfs.conf before RAUC marks the slot good, and
# any block that fails the check reboots the board, loading a fallback slot
# after retries are exhaused.
#
# NB: Loops until stable, offset depends on FIT size, and FIT contains offset
#
# Usage: mkrootimg.sh [--verity] <zImage> <dtb> <rootfs.squashfs> <out.img>
# Needs mkimage + dtc in PATH (+ veritysetup with --verity)
set -eu

verity=0
if [ "${1:-}" = --verity ]; then
  verity=1
  shift
fi

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 [--verity] <zImage> <dtb> <rootfs.squashfs> <out.img>" >&2
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

img_sectors=$sq_sectors
dm_extra=
root_dev=/dev/dm-0
if [ "$verity" -eq 1 ]; then
  # Tree right after the squashfs inside rimg (hash dev = data dev = dm-0).
  # Salt = squashfs sha256 (reproducible)
  sq_blocks=$((sq_size / ALIGN))
  salt=$(sha256sum "$squashfs" | cut -c1-64)
  veritysetup format --no-superblock --hash=sha256 \
    --data-block-size=$ALIGN --hash-block-size=$ALIGN \
    --salt="$salt" --root-hash-file="$work/roothash" \
    "$squashfs" "$work/verity" >/dev/null
  roothash=$(cat "$work/roothash")
  tree_size=$(stat -c %s "$work/verity")
  img_sectors=$(((sq_size + tree_size) / SECTOR))
  dm_extra=";vroot,,,ro,0 ${sq_sectors} verity 1 /dev/dm-0 /dev/dm-0 $ALIGN $ALIGN ${sq_blocks} ${sq_blocks} sha256 ${roothash} ${salt} 1 restart_on_corruption"
  root_dev=/dev/dm-1
fi

# $1 = squashfs offset in sectors
write_fit() {
  # Must stay in sourced script: `run` of env var strips quotes in dm-mod.create
  cat >"$work/boot.scr" <<EOF
setenv dm_create "rimg,,,ro,0 ${img_sectors} linear /dev/ubiblock0_\${slot_vol} $1${dm_extra}"
setenv bootargs "ubi.mtd=UBI ubi.block=0,\${slot_vol} dm-mod.waitfor=/dev/ubiblock0_\${slot_vol} dm-mod.create=\\"\${dm_create}\\" root=${root_dev} rootfstype=squashfs ro rauc.slot=\${rauc_slot} console=ttySTM0,115200 earlycon \${machine_id_arg}"
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
if [ "$verity" -eq 1 ]; then
  cat "$work/verity" >>"$out"
  echo "mkrootimg: verity tree $tree_size B at $((off + sq_size)) B, root hash $roothash"
fi

echo "mkrootimg: FIT $fit_size B, squashfs at $off B ($((off / SECTOR)) sectors), $sq_size B ($sq_sectors sectors), total $(stat -c %s "$out") B"
