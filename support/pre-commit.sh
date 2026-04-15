#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
set -euo pipefail

# Run pre-commit via the nix pre-commit shell.
#
# Local usage (no args):    run --all-files
# Local usage (with args):  passed through to pre-commit directly
# CI usage (CI=1, no args): run all file checks, then check commit messages
#
# Commit message check (pre-push stage) uses CZ_CHECK_BASE if set, otherwise
# falls back to git merge-base HEAD origin/main.

# Suppress nix's "Git tree is dirty" warning tree is always dirty when running hooks
NIX=(nix develop --option warn-dirty false .#pre-commit -c)

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [ "$#" -gt 0 ]; then
  exec "${NIX[@]}" pre-commit "$@"
fi

if [ -z "${CI:-}" ]; then
  exec "${NIX[@]}" pre-commit run --all-files
fi

# CI: phase 1: file checks
"${NIX[@]}" pre-commit run --all-files

# CI: phase 2: commit message checks (pre-push stage)
# Resolve base commit: prefer explicit CZ_CHECK_BASE from CI runner, fall back to merge-base.
if [ -z "${CZ_CHECK_BASE:-}" ]; then
  CZ_CHECK_BASE="$(git merge-base HEAD origin/main 2>/dev/null || true)"
fi

if [ -z "${CZ_CHECK_BASE:-}" ]; then
  echo "warning: could not determine base commit, skipping commitizen check" >&2
  exit 0
fi

head_sha="$(git rev-parse HEAD)"
echo "refs/heads/main ${head_sha} refs/heads/main ${CZ_CHECK_BASE}" |
  "${NIX[@]}" pre-commit run --hook-stage pre-push
