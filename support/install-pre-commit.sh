#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: not inside a git repository" >&2
  exit 1
fi

git config core.hooksPath .githooks

mkdir -p .githooks

cat >.githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
exec "$repo_root/support/pre-commit.sh" run --hook-stage pre-commit
EOF

chmod +x .githooks/pre-commit

nix develop .#pre-commit -c pre-commit install-hooks

echo "Installed pre-commit launcher in .githooks using flake shell .#pre-commit"
