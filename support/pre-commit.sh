#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if [ "$#" -eq 0 ]; then
  set -- run --all-files
fi

exec nix develop .#pre-commit -c pre-commit "$@"
