#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: not inside a git repository" >&2
  exit 1
fi

# Auto-detect DBL_BUILDROOT_DIR: check caller's repo for submodule, then cwd.
if [ -z "${DBL_BUILDROOT_DIR:-}" ]; then
  if [ -d "${repo_root}/modules/dbl-buildroot" ] && [ -f "${repo_root}/modules/dbl-buildroot/flake.nix" ]; then
    DBL_BUILDROOT_DIR="${repo_root}/modules/dbl-buildroot"
  else
    DBL_BUILDROOT_DIR="."
  fi
fi

# Resolve path to pre-commit.sh relative to repo root for the hook scripts.
if [ "$DBL_BUILDROOT_DIR" = "." ]; then
  PRE_COMMIT_SCRIPT="support/pre-commit.sh"
else
  # Relative path from repo root (e.g. modules/dbl-buildroot/support/pre-commit.sh)
  PRE_COMMIT_SCRIPT="${DBL_BUILDROOT_DIR#${repo_root}/}/support/pre-commit.sh"
fi

git config core.hooksPath .githooks

mkdir -p .githooks

cat >.githooks/pre-commit <<EOF
#!/usr/bin/env bash
set -euo pipefail

repo_root="\$(git rev-parse --show-toplevel)"
exec "\$repo_root/${PRE_COMMIT_SCRIPT}" run --hook-stage pre-commit
EOF

chmod +x .githooks/pre-commit

cat >.githooks/commit-msg <<EOF
#!/usr/bin/env bash
set -euo pipefail

repo_root="\$(git rev-parse --show-toplevel)"
exec "\$repo_root/${PRE_COMMIT_SCRIPT}" run --hook-stage commit-msg --commit-msg-filename "\$1"
EOF

chmod +x .githooks/commit-msg

cat >.githooks/pre-push <<EOF
#!/usr/bin/env bash
set -euo pipefail

repo_root="\$(git rev-parse --show-toplevel)"
exec "\$repo_root/${PRE_COMMIT_SCRIPT}" run --hook-stage pre-push
EOF

chmod +x .githooks/pre-push

nix develop --option warn-dirty false "${DBL_BUILDROOT_DIR}#pre-commit" -c pre-commit install-hooks

echo "Installed pre-commit + commit-msg launchers in .githooks using flake shell .#pre-commit"
