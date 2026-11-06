#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
"""dbl-bootid layout tool (board/myd-yf135/dbl-bootid.toml).

Usage:
  dbl-bootid.py dtsi  <layout.toml>
  dbl-bootid.py pack  <layout.toml> <out.bin> [SLOT=FILE ...]
  dbl-bootid.py check <layout.toml> <image.bin>

pack: writes a full EEPROM image with the header and the given slots
check: verifies every slot holds a correctly formatted object (signatures unchecked)
"""

import sys
import tomllib

HEADER_MAGIC = b"DBID"
FSBL_MAGIC = b"STM2"
FSBL_HEADER_LEN = 512
ERASED = 0xFF


def die(msg):
    sys.exit(f"dbl-bootid: {msg}")


def load(path):
    """Load layout from reference toml; as page aligned ordered slots"""
    with open(path, "rb") as f:
        lay = tomllib.load(f)
    end = 0
    for s in lay["slot"]:
        if s["offset"] != end or end % lay["eeprom"]["page"]:
            die(f"slot {s['name']} at {s['offset']:#x}, expected {end:#x} on a page boundary")
        end += s["size"]
    if end != lay["eeprom"]["size"]:
        die(f"slots end at {end:#x}, EEPROM size is {lay['eeprom']['size']:#x}")
    return lay


def der_len(b):
    """Length of the DER SEQUENCE at the start of b, or 0."""
    if len(b) < 4 or b[0] != 0x30:
        return 0
    if b[1] < 0x80:
        return 2 + b[1]
    n = b[1] & 0x7F
    if n > 2:
        return 0
    return 2 + n + int.from_bytes(b[2 : 2 + n], "big")


def object_len(fmt, b, version):
    """Length of the object at the start of slot data b, or 0 if none."""
    if b[0] == ERASED:
        return 0
    if fmt == "header":
        ok = b[:4] == HEADER_MAGIC and b[4] == version
        return 5 if ok else 0
    if fmt == "fsbl-header":
        return FSBL_HEADER_LEN if b[:4] == FSBL_MAGIC else 0
    if fmt == "x509-der":
        n = der_len(b)
        return n if n <= len(b) else 0
    return len(b)


def dtsi(layout):
    lay = load(layout)
    print("/* Generated from dbl-bootid.toml by dbl-bootid.py */")
    print("nvmem-layout {")
    print('\tcompatible = "fixed-layout";')
    print("\t#address-cells = <1>;")
    print("\t#size-cells = <1>;")
    for s in lay["slot"]:
        if s["format"] == "bytes":
            continue
        print(f"\n\t{s['name']}@{s['offset']:x} {{")
        print(f"\t\treg = <{s['offset']:#x} {s['size']:#x}>;")
        print("\t};")
    print("};")


def pack(layout, out, *items):
    lay = load(layout)
    version = lay["eeprom"]["layout_version"]
    slots = {s["name"]: s for s in lay["slot"]}
    img = bytearray([ERASED]) * lay["eeprom"]["size"]
    files = {"header": HEADER_MAGIC + bytes([version])}
    for item in items:
        name, _, path = item.partition("=")
        with open(path, "rb") as f:
            files[name] = f.read()
    for name, data in files.items():
        s = slots.get(name)
        if not s or s["format"] == "bytes":
            die(f"{name}: not a slot")
        if s["format"] == "fsbl-header":
            data = data[:FSBL_HEADER_LEN]
        if len(data) > s["size"] or object_len(s["format"], data, version) != len(data):
            die(f"{name}: not one {s['format']} of at most {s['size']} bytes")
        img[s["offset"] : s["offset"] + len(data)] = data
    with open(out, "wb") as f:
        f.write(img)


def check(layout, image):
    lay = load(layout)
    with open(image, "rb") as f:
        img = f.read()
    if len(img) != lay["eeprom"]["size"]:
        die(f"{image}: {len(img)} bytes, expected {lay['eeprom']['size']}")
    bad = []
    for s in lay["slot"]:
        b = img[s["offset"] : s["offset"] + s["size"]]
        if s["format"] != "bytes" and not object_len(s["format"], b, lay["eeprom"]["layout_version"]):
            bad.append(s["name"])
    if bad:
        die(f"{image}: no valid object in {', '.join(bad)}")


def main():
    cmds = {"dtsi": (dtsi, 1), "pack": (pack, 2), "check": (check, 2)}
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else (None, [])
    if cmd not in cmds or len(args) < cmds[cmd][1] or (cmd != "pack" and len(args) != cmds[cmd][1]):
        sys.exit(__doc__)
    cmds[cmd][0](*args)


if __name__ == "__main__":
    main()
