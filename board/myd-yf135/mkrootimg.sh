#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Build a rootfs slot image.
#
# Usage: mkrootimg.sh [--verity] [--sign-key <dir/name.key>] <zImage> <dtb> <rootfs.squashfs> <out.img>
# Requires mkimage + dtc in PATH (+ veritysetup with --verity)
#
# Layout:
#   [ FIT (kernel + DT + boot script) | pad to 4 KiB | squashfs | verity tree (--verity) ]
# Boot script contains the squashfs offset, FIT is rebuilt until its size stabilizes
#
# --verity: maps squashfs + tree to /dev/dm-0 and roots on /dev/dm-1,
# checks every dm-0 block against script's root hash
#
# --sign-key: signs conf-1 (kernel + DT + script) with key-name-hint <name>,
#   adds one spare 4 KiB block before the squashfs to re-sign in place with sign-rootimg.sh
set -eu

usage() {
  echo "Usage: $0 [--verity] [--sign-key <key>] <zImage> <dtb> <rootfs.squashfs> <out.img>" >&2
  exit 1
}

verity=0
sign_key=
while [ "$#" -gt 0 ]; do
  case $1 in
  --verity) verity=1; shift ;;
  --sign-key) [ "$#" -ge 2 ] || usage; sign_key=$(realpath "$2"); shift 2 ;;
  *) break ;;
  esac
done

[ "$#" -eq 4 ] || usage

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

sig_node=
spare=0
if [ -n "$sign_key" ]; then
  key_name=$(basename "$sign_key" .key)
  sig_node="signature-1 { algo = \"sha256,rsa2048\"; key-name-hint = \"$key_name\"; sign-images = \"kernel\", \"fdt\", \"script\"; };"
  spare=$ALIGN
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
      $sig_node
    };
  };
};
EOF
  if [ -n "$sign_key" ]; then
    mkimage -q -f "$work/rootfs.its" -k "$(dirname "$sign_key")" "$work/rootfs.itb"
  else
    mkimage -q -f "$work/rootfs.its" "$work/rootfs.itb"
  fi
}

off=0
i=0
while :; do
  write_fit $((off / SECTOR))
  fit_size=$(stat -c %s "$work/rootfs.itb")
  new=$(((fit_size + spare + ALIGN - 1) / ALIGN * ALIGN))
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
