#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
"""Merge buildroot defconfig fragments left-to-right.

Each fragment overrides keys from prior inputs, except accumulating keys
(``*_FRAGMENT_FILES`` kernel/u-boot config fragment lists, and
``BR2_ROOTFS_OVERLAY``) whose values append to stack layers

Comments and blank lines in the base file are preserved in place. New
keys introduced by a delta append at the end of the output in delta order.

Conditional deltas: a delta may carry a ``# dbl-merge-if: KEY=value`` line.
It is applied at its argument-order position only when the merge of the
unconditional deltas contains that exact line. Callers always pass every
delta, met or not, and later deltas override earlier ones. One conditional
delta can never switch on another.

Usage: merge-defconfig.py <output> <base> [delta1 delta2 ...]
"""

import re
import sys
import tempfile
from pathlib import Path

# `CONFIG_FOO=value` (set) or `# CONFIG_FOO is not set` (explicit unset)
_KEY = re.compile(r"^([A-Z0-9_]+)=|^# ([A-Z0-9_]+) is not set$")

# Keys whose values accumulate (space-joined) across layers
# NB: `*_FRAGMENT_FILES` is matched by suffix
_ACCUMULATE = ("BR2_ROOTFS_OVERLAY",)


_COND = re.compile(r"^# dbl-merge-if: (\S+=\S+)$")


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
        elif key.endswith("_FRAGMENT_FILES") or key in _ACCUMULATE:
            values = (value_of(line), value_of(overrides[key]))
            out.append('{}="{}"'.format(key, " ".join(v for v in values if v)))
            applied.add(key)
        else:
            out.append(overrides[key])
            applied.add(key)
    out.extend(ln for key, ln in overrides.items() if key not in applied)
    return out


def condition_of(path):
    """``KEY=value`` from a ``# dbl-merge-if:`` line, or None."""
    for raw in path.read_text().splitlines():
        m = _COND.match(raw.strip())
        if m:
            return m.group(1)
    return None


def merge(base_lines, delta_paths):
    deltas = [(p, condition_of(p)) for p in delta_paths]
    # Pass 1: merge the unconditional deltas; conditions are checked
    # against that result (a condition may be set by a later delta).
    lines = base_lines
    for path, cond in deltas:
        if cond is None:
            lines = apply_delta(lines, load_overrides(path))
    final = set(lines)
    # Pass 2: apply all deltas in argument order, skipping conditional
    # ones whose condition evaludate false on the pass-1 result.
    lines = base_lines
    for path, cond in deltas:
        if cond is None or cond in final:
            lines = apply_delta(lines, load_overrides(path))
    return lines


def selftest():
    """``merge-defconfig.py --selftest``."""

    BASE = 'BR2_A=y\nBR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="base"\n'
    VERIFIED = (
        "# dbl-merge-if: BR2_PACKAGE_DBL_VERIFIED_BOOT=y\n"
        'BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="verified"\n'
        "BR2_B=y\n"
    )
    PARENT_ON = "BR2_PACKAGE_DBL_VERIFIED_BOOT=y\nBR2_B=n\n"
    PARENT_OFF = "# BR2_PACKAGE_DBL_VERIFIED_BOOT is not set\nBR2_C=y\n"
    DEBUG = 'BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="debug"\n'

    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)

        def run(*texts):
            paths = [tmp / f"in{i}" for i, _ in enumerate(texts)]
            for p, text in zip(paths, texts):
                p.write_text(text)
            return merge(BASE.splitlines(), paths)

        # Switch on (set by a later delta): applied at its own chain position,
        # fragment files stack in order, the later parent value wins.
        on = "\n".join(run(VERIFIED, PARENT_ON, DEBUG))
        assert 'FRAGMENT_FILES="base verified debug"' in on, on
        assert "BR2_B=n" in on, on
        # Switch off/absent: byte-identical to the chain without the delta.
        for parent in (PARENT_OFF, "BR2_C=y\n"):
            assert run(VERIFIED, parent, DEBUG) == run(parent, DEBUG)
    print("ok")


def main():
    if "--selftest" in sys.argv[1:]:
        selftest()
        return
    if len(sys.argv) < 3:
        sys.exit(f"Usage: {sys.argv[0]} [--selftest] <output> <base> [delta...]")
    lines = Path(sys.argv[2]).read_text().splitlines()
    # tolerate empty args from make
    lines = merge(lines, [Path(d) for d in sys.argv[3:] if d])
    Path(sys.argv[1]).write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
