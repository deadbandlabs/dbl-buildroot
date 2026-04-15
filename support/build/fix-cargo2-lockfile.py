#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Fix buildroot.lock cargo2 entries: remove upstream (non-mirror) URLs.
#
# buildroot.nix's make-package-lock.py includes the upstream PyPI URL for
# cargo2 tarballs (e.g. python-cryptography-*-cargo2.tar.gz). The upstream
# URL serves the raw sdist, not the cargo2 repack with vendored Cargo deps.
# Nix's fetchurl tries URLs in order and stops at the first HTTP 200, so
# it downloads the wrong file and fails the hash check.
#
# This script strips non-mirror URLs from cargo2 entries so fetchurl goes
# straight to sources.buildroot.net which hosts the correct cargo2 repacks.

import json
import sys


def fix_cargo2_uris(lockdata):
    for source, info in lockdata.items():
        if "cargo2" not in source:
            continue
        mirror_uris = [u for u in info["uris"] if "sources.buildroot.net" in u]
        if mirror_uris:
            info["uris"] = mirror_uris
    return lockdata


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <lockfile>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]
    with open(path) as f:
        data = json.load(f)

    data = fix_cargo2_uris(data)

    with open(path, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main()
