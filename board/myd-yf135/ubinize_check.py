#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
"""Compute UBI volume layout and emit ubinize.cfg.

Generate proper fitting SPI-NAND UBI partitioning on MYD-YF135.

Usage:
    ./ubinize_check.py                  # validation table only
    ./ubinize_check.py --write FILE     # also (re)generate ubinize.cfg

Re-run with --write whenever VOLUMES, NAND geometry, or reserve % change.
"""

import argparse
import sys
from dataclasses import dataclass
from typing import Optional

# NAND geometry (Micron MT29F2G01ABAGDWB) and partition layout (DTS)
NAND_SIZE = 0x10000000  # 256 MB
UBI_OFFSET = 0x1200000  # start of UBI partition (DTS)
UBI_SIZE = NAND_SIZE - UBI_OFFSET  # 0xee00000 = 238 MB; matches DTS

PEB_SIZE = 128 * 1024  # 131072 B (NAND erase block)
PAGE_SIZE = 2 * 1024  # 2048 B (NAND page; no sub-pages)
LEB_SIZE = PEB_SIZE - 2 * PAGE_SIZE  # 126976 B (PEB minus EC + VID headers)

# Reserve budgets (engineering choices, NOT UBI minimums)
#
# UBI_RESERVE_PCT: PEBs subtracted from total before sizing volumes, modeling
# bad-eraseblock retirement over the device lifetime. Must be >= UBI's actual
# internal reserve at attach time (else volume table over-allocates). For 1900
# PEBs UBI's internal reserve is ~40 PEBs (~2%): 2 layout + 1 WL + ~37 BEB
# (kernel default mtd_max_beb_per1024=20 -> ceil(20*1900/1024)). 4.5% pads
# above that for MT29F2G01 vendor lifetime BB rate (spec: <=2%).
#
# FREE_POOL_PCT: PEBs left unallocated to volumes, becoming UBI's runtime
# working pool. Used for wear-leveling moves, runtime BB replacement beyond
# the static reserve, atomic LEB updates (write-new-then-erase-old needs a
# spare PEB), and volume resize headroom. UBI's hard minimum is a handful
# of PEBs; 10% is generous margin for a write-heavy overlay volume
UBI_RESERVE_PCT = 4.5
FREE_POOL_PCT = 10.0

KB = 1024
MB = 1024 * 1024


@dataclass
class Vol:
    name: str
    vol_id: int
    size: Optional[int]  # bytes; None = consume remaining usable space
    image: Optional[str]  # ubinize image= token; None = create empty volume
    desc: str


VOLUMES = [
    Vol("rootfs_a", 0, 45 * MB, "BR2_ROOTFS_UBIFS_PATH", "Active rootfs slot A"),
    Vol("rootfs_b", 1, 45 * MB, "BR2_ROOTFS_UBIFS_PATH", "Active rootfs slot B"),
    Vol(
        "rootfs_factory",
        2,
        35 * MB,
        "BR2_ROOTFS_UBIFS_PATH",
        "Immutable factory fallback",
    ),
    Vol(
        "overlay",
        3,
        None,
        "overlay.ubifs",
        "Writable overlayfs upper (wiped on update)",
    ),
    Vol("optee_ss", 4, 4 * MB, "optee_ss.ubifs", "OP-TEE secure storage"),
    # U-Boot env volumes. ENV_SIZE=0x4000 (16 KB) fits in 1 LEB (~124 KB).
    # Pre-populated with mkenvimage(-r) output so default-env (try_boot,
    # BOOT_ORDER, ...) is present on first boot.
    Vol("env-a", 5, LEB_SIZE, "uboot.env", "U-Boot env primary"),
    Vol("env-b", 6, LEB_SIZE, "uboot.env", "U-Boot env redundant"),
]


def lebs_for(size: int) -> int:
    return (size + LEB_SIZE - 1) // LEB_SIZE


def compute():
    total_pebs = UBI_SIZE // PEB_SIZE
    reserved_pebs = int(total_pebs * UBI_RESERVE_PCT / 100)
    available_pebs = total_pebs - reserved_pebs
    free_lebs = int(available_pebs * FREE_POOL_PCT / 100)
    usable = available_pebs - free_lebs

    fixed_lebs = sum(lebs_for(v.size) for v in VOLUMES if v.size is not None)
    auto_count = sum(1 for v in VOLUMES if v.size is None)
    if auto_count > 1:
        sys.exit("ERROR: at most one auto-sized volume permitted")
    if fixed_lebs > usable:
        sys.exit(
            f"ERROR: fixed volumes ({fixed_lebs} LEBs) exceed usable ({usable} LEBs)"
        )
    auto_lebs = usable - fixed_lebs

    sized = []
    for v in VOLUMES:
        lebs = lebs_for(v.size) if v.size is not None else auto_lebs
        sized.append((v, lebs, lebs * LEB_SIZE))

    return {
        "total_pebs": total_pebs,
        "reserved_pebs": reserved_pebs,
        "available_pebs": available_pebs,
        "free_lebs": free_lebs,
        "usable": usable,
        "fixed_lebs": fixed_lebs,
        "auto_lebs": auto_lebs,
        "sized": sized,
    }


def print_summary(s):
    print(f"UBI partition: 0x{UBI_SIZE:x} ({UBI_SIZE:,} B, {UBI_SIZE // MB} MB)")
    print(f"Total PEBs:    {s['total_pebs']} x {PEB_SIZE} B")
    print(f"LEB size:      {LEB_SIZE} B (PEB - 2x{PAGE_SIZE} B headers)")
    print(
        f"BB reserve:    {UBI_RESERVE_PCT}% = {s['reserved_pebs']} PEBs (lifetime BB budget)"
    )
    print(f"Available:     {s['available_pebs']} PEBs after reserve")
    print(
        f"Free pool:     {s['free_lebs']} LEBs = {s['free_lebs'] * LEB_SIZE / MB:.1f} MB ({FREE_POOL_PCT}%) for WL"
    )
    print(f"Usable:        {s['usable']} LEBs for volume content")
    print()
    print(f"{'Volume':<18} {'Size (B)':>14} {'Size':>10} {'LEBs':>6}  Description")
    print("-" * 80)
    for v, lebs, aligned in s["sized"]:
        mb = aligned / MB
        print(f"{v.name:<18} {aligned:>14,} {mb:>9.1f} MB {lebs:>6}  {v.desc}")
    total_bytes = sum(a for _, _, a in s["sized"])
    total_lebs = sum(l for _, l, _ in s["sized"])
    print("-" * 80)
    print(
        f"{'Total':<18} {total_bytes:>14,} {total_bytes / MB:>9.1f} MB {total_lebs:>6}"
    )
    print()
    print(
        f"Layout PASS auto-sized 'overlay' = {s['auto_lebs']} LEBs ({s['auto_lebs'] * LEB_SIZE / MB:.1f} MB), "
        f"free pool = {s['free_lebs']} LEBs"
    )


CFG_HEADER = """\
## SPDX-License-Identifier: GPL-2.0-or-later
## Copyright 2026 Deadband Inc.
##
## DO NOT EDIT: GENERATED by ubinize_check.py
## To change layout: edit VOLUMES (or geometry) in ubinize_check.py and run:
##     ./ubinize_check.py --write ubinize.cfg

# UBI partition: {ubi_size_hex} ({ubi_size_mb} MB), {total_pebs} PEBs x {peb_kb} KB
# LEB size:   {leb_size} B
# BB reserve: {reserved_pebs} PEBs ({reserve_pct}%)
# Free pool:  {free_lebs} LEBs ({free_pct}%)
# Usable:     {usable} LEBs
#
# Volume map:
{vol_map}
"""


def vol_block(v: Vol, size: int) -> str:
    # image=None produces an empty volume (no payload). ubinize creates the
    # volume header at LEB 0 and stops; flashing the resulting UBI image
    # writes only that header for the volume, not size bytes of payload.
    lines = [
        f"\n[{v.name}]",
        "mode=ubi",
    ]
    if v.image is not None:
        token = (
            v.image if v.image == "BR2_ROOTFS_UBIFS_PATH" else f"BINARIES_DIR/{v.image}"
        )
        lines.append(f"image={token}")
    lines += [
        f"vol_id={v.vol_id}",
        "vol_type=dynamic",
        f"vol_name={v.name}",
        f"vol_size={size}",
        "",
    ]
    return "\n".join(lines)


def emit_cfg(s, path):
    vol_map = "\n".join(
        f"#   {v.name:<14} vol {v.vol_id}  {aligned / MB:5.1f} MB ({lebs:4d} LEBs)  {v.desc}"
        for v, lebs, aligned in s["sized"]
    )
    header = CFG_HEADER.format(
        ubi_size_hex=f"0x{UBI_SIZE:x}",
        ubi_size_mb=UBI_SIZE // MB,
        total_pebs=s["total_pebs"],
        peb_kb=PEB_SIZE // KB,
        leb_size=LEB_SIZE,
        page_size=PAGE_SIZE,
        reserve_pct=UBI_RESERVE_PCT,
        reserved_pebs=s["reserved_pebs"],
        free_lebs=s["free_lebs"],
        free_pct=FREE_POOL_PCT,
        usable=s["usable"],
        vol_map=vol_map,
    )
    body = "".join(vol_block(v, aligned) for v, _, aligned in s["sized"])
    with open(path, "w") as f:
        f.write(header + body)
    print(f"\nWrote {path}")


def apply_minimal(volumes):
    # Debug iteration: skip writing rootfs_b and rootfs_factory payloads.
    # Volume slots and sizes stay identical so vol_id assignments, RAUC,
    # and overlay scripts behave the same; only the image= line is dropped.
    # try_boot still tries B/factory on A failure; ubifsmount on the empty
    # volumes fails fast and falls through to the U-Boot prompt.
    skip = {"rootfs_b", "rootfs_factory"}
    return [
        Vol(v.name, v.vol_id, v.size, None if v.name in skip else v.image, v.desc)
        for v in volumes
    ]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--write", metavar="PATH", help="emit ubinize cfg to PATH")
    p.add_argument(
        "--minimal",
        action="store_true",
        help="emit debug variant: rootfs_b and rootfs_factory as empty volumes",
    )
    args = p.parse_args()
    if args.minimal:
        global VOLUMES
        VOLUMES = apply_minimal(VOLUMES)
    s = compute()
    print_summary(s)
    if args.write:
        emit_cfg(s, args.write)


if __name__ == "__main__":
    main()
