#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
"""Merge buildroot defconfig fragments left-to-right.

Each fragment overrides keys from prior inputs, except keys matching
``*_FRAGMENT_FILES`` (kernel/u-boot config fragment lists) whose values
append space-separated so fragment lists accumulate across layers.

Comments and blank lines in the base file are preserved in place. New
keys introduced by a delta append at the end of the output in delta order.

Usage: merge-defconfig.py <output> <base> [delta1 delta2 ...]
"""

import re
import sys
from pathlib import Path

# `CONFIG_FOO=value` (set) or `# CONFIG_FOO is not set` (explicit unset)
_KEY = re.compile(r"^([A-Z0-9_]+)=|^# ([A-Z0-9_]+) is not set$")


def key_of(line):
    m = _KEY.match(line)
    return (m.group(1) or m.group(2)) if m else None


def value_of(line):
    """Unquoted RHS of a ``KEY=value`` line, or '' otherwise."""
    value = line.partition("=")[2]
    if len(value) >= 2 and value[0] == value[-1] == '"':
        value = value[1:-1]
    return value


def load_overrides(path):
    """Read a delta file as ``{key: full_line}`` in file order.

    Pure comments are skipped; ``# X is not set`` lines are kept (they are
    unset assertions, not commentary). Later occurrences in a file win.
    """
    lines = (raw.rstrip() for raw in path.read_text().splitlines())
    return {key_of(ln): ln for ln in lines if key_of(ln) is not None}


def apply_delta(base_lines, overrides):
    """Replace matching base lines in place (appending the value instead for
    ``*_FRAGMENT_FILES`` keys); append unmatched override keys at the end."""
    out = []
    applied = set()
    for line in base_lines:
        key = key_of(line)
        if key is None or key not in overrides:
            out.append(line)
        elif key.endswith("_FRAGMENT_FILES"):
            values = (value_of(line), value_of(overrides[key]))
            out.append('{}="{}"'.format(key, " ".join(v for v in values if v)))
            applied.add(key)
        else:
            out.append(overrides[key])
            applied.add(key)
    out.extend(ln for key, ln in overrides.items() if key not in applied)
    return out


def main():
    if len(sys.argv) < 3:
        sys.exit(f"Usage: {sys.argv[0]} <output> <base> [delta...]")
    lines = Path(sys.argv[2]).read_text().splitlines()
    for delta in sys.argv[3:]:
        if delta:  # tolerate empty args from make
            lines = apply_delta(lines, load_overrides(Path(delta)))
    Path(sys.argv[1]).write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
