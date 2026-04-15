#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
set -euo pipefail

status=0

for file in "$@"; do
  if grep -n $'\t' "$file" >/dev/null; then
    echo "tabs found in $file:" >&2
    grep -n $'\t' "$file" >&2
    status=1
  fi
done

exit "$status"
