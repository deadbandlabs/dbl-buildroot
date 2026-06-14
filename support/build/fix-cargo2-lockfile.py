#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
"""Fix buildroot.lock cargo2 entries: remove upstream (non-mirror) URLs.

buildroot.nix's make-package-lock.py includes the upstream PyPI URL for
cargo2 tarballs (e.g. python-cryptography-*-cargo2.tar.gz). The upstream
URL serves the raw sdist, not the cargo2 repack with vendored Cargo deps.
Nix's fetchurl tries URLs in order and stops at the first HTTP 200, so it
downloads the wrong file and fails the hash check. Keeping only the
sources.buildroot.net mirror URLs makes fetchurl get the correct repack.

Usage: fix-cargo2-lockfile.py <lockfile>
"""

import json
import sys

if len(sys.argv) != 2:
    sys.exit(f"Usage: {sys.argv[0]} <lockfile>")

with open(sys.argv[1]) as f:
    data = json.load(f)

for source, info in data.items():
    if "cargo2" in source and isinstance(info, dict) and isinstance(info.get("uris"), list):
        mirrors = [u for u in info["uris"] if "sources.buildroot.net" in u]
        if mirrors:
            info["uris"] = mirrors

with open(sys.argv[1], "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
