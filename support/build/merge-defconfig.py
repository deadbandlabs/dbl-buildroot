#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
"""Merge buildroot defconfig fragments left-to-right.

Each fragment overrides keys from prior inputs, except for keys matching
``*_FRAGMENT_FILES`` (e.g. ``BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES``,
``BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES``) which are appended
space-separated so kernel/u-boot fragment lists accumulate across layers.

Comments and blank lines in the base file are preserved in place.
New keys introduced by a delta append at the end of the output in delta order.

Usage: merge-defconfig.py <output> <base> [delta1 delta2 ...]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Kconfig key lines are generally one of:
#   CONFIG_FOO=value             (set)
#   # CONFIG_FOO is not set      (explicit unset)
_SET_LINE = re.compile(r"^([A-Z0-9_]+)=(.*)$")
_UNSET_LINE = re.compile(r"^# ([A-Z0-9_]+) is not set$")


def parse_key(line: str) -> str | None:
    """Return the CONFIG_* key defined on this line, or None."""
    m = _SET_LINE.match(line)
    if m:
        return m.group(1)
    m = _UNSET_LINE.match(line)
    if m:
        return m.group(1)
    return None


def parse_value(line: str) -> str:
    """Return the unquoted RHS of a ``KEY=value`` line, or '' otherwise."""
    m = _SET_LINE.match(line)
    if not m:
        return ""
    raw = m.group(2)
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        return raw[1:-1]
    return raw


def is_fragment_list_key(key: str) -> bool:
    return key.endswith("_FRAGMENT_FILES")


def load_overrides(path: Path) -> dict[str, str]:
    """Read a delta file, returning ``{key: full_line}`` in file order.

    Blank lines and pure comments are skipped, but ``# X is not set`` lines
    are kept (they're unset assertions, not simply commentary)
    """
    overrides: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        stripped = line.lstrip()
        if stripped.startswith("#") and not stripped.endswith("is not set"):
            continue
        key = parse_key(line)
        if key is not None:
            # Later occurrence in the same file wins.
            overrides[key] = line
    return overrides


def apply_delta(base_lines: list[str], overrides: dict[str, str]) -> list[str]:
    """Return ``base_lines`` with ``overrides`` applied.

    - Matching base lines are replaced in place.
    - For ``*_FRAGMENT_FILES`` keys, the override's value is appended to
      the base's value rather than replacing it.
    - Override keys absent from the base are appended at the end in
      delta order.
    """
    out: list[str] = []
    applied: set[str] = set()
    for line in base_lines:
        key = parse_key(line)
        if key is None or key not in overrides:
            out.append(line)
            continue
        override_line = overrides[key]
        if is_fragment_list_key(key):
            base_val = parse_value(line)
            new_val = parse_value(override_line)
            combined = " ".join(v for v in (base_val, new_val) if v)
            out.append(f'{key}="{combined}"')
        else:
            out.append(override_line)
        applied.add(key)
    for key, override_line in overrides.items():
        if key not in applied:
            out.append(override_line)
    return out


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(f"Usage: {argv[0]} <output> <base> [delta...]", file=sys.stderr)
        return 1

    output = Path(argv[1])
    base = Path(argv[2])
    deltas = [Path(p) for p in argv[3:] if p]  # tolerate empty args

    lines = base.read_text().splitlines()
    for delta in deltas:
        lines = apply_delta(lines, load_overrides(delta))

    output.write_text("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
