#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tarball="$(find dl/linux -maxdepth 1 -type f \( -name 'linux-*.tar' -o -name 'linux-*.tar.*' \) | sort | tail -n1)"

if [ -z "$tarball" ]; then
  echo "error: no linux source tarball found under dl/linux" >&2
  echo "hint: build or fetch kernel sources first using 'make linux-source'" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

tar -xf "$tarball" -C "$tmpdir" --wildcards \
  '*/scripts/checkpatch.pl' \
  '*/scripts/spelling.txt' \
  '*/scripts/const_structs.checkpatch'

checkpatch="$(find "$tmpdir" -path '*/scripts/checkpatch.pl' | head -n1)"

if [ -z "$checkpatch" ]; then
  echo "error: could not extract scripts/checkpatch.pl from $tarball" >&2
  exit 1
fi

status=0
for file in "$@"; do
  if ! perl "$checkpatch" --no-tree --terse --file "$file"; then
    status=1
  fi
done

exit "$status"
