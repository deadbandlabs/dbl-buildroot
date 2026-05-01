#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Bump the dbl-buildroot submodule and propagate the new SHA to every pin
# site in the parent repo. Run from the parent repo root.
#
# Usage:
#   support/parent/update.sh         # advance to origin/main
#   support/parent/update.sh <ref>   # advance to <ref> (sha, tag, branch)
#
# Pin sites updated:
#   - modules/dbl-buildroot               (git submodule pointer)
#   - .pre-commit-config.yaml             (rev: under repo: dbl-buildroot)
#   - .github/workflows/*.yml             (uses: deadbandlabs/dbl-buildroot/...@<sha>)
#   - flake.lock                          (nix flake update)
#
# Also runs check-flake-inputs.sh + check-pinned-shas.sh at the end, so a
# successful run = a fully-consistent state ready to stage.
#
# Does NOT git-add or git-commit anything; staging is the caller's call.

set -euo pipefail

SUBMODULE_PATH="modules/dbl-buildroot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REF="${1:-origin/main}"

if [[ ! -d "$SUBMODULE_PATH" ]]; then
  echo "error: $SUBMODULE_PATH not found (run from parent repo root)" >&2
  exit 2
fi

echo "==> fetching submodule and checking out $REF"
git -C "$SUBMODULE_PATH" fetch origin --tags
git -C "$SUBMODULE_PATH" checkout "$REF"
new_sha="$(git -C "$SUBMODULE_PATH" rev-parse HEAD)"
echo "    new SHA: $new_sha"

# Pre-commit
if [[ -f .pre-commit-config.yaml ]]; then
  echo "==> updating .pre-commit-config.yaml"
  # Match `rev:` lines that appear after a dbl-buildroot repo entry. Limit to
  # the first such occurrence per repo block by tracking state in awk.
  tmp="$(mktemp)"
  awk -v sha="$new_sha" '
    /repo: .*dbl-buildroot/ { in_repo = 1; print; next }
    in_repo && /^[[:space:]]*rev:/ {
      sub(/rev:[[:space:]]*[A-Za-z0-9._-]+/, "rev: " sha)
      in_repo = 0
    }
    /^[[:space:]]*-[[:space:]]*repo:/ && in_repo { in_repo = 0 }
    { print }
  ' .pre-commit-config.yaml >"$tmp"
  mv "$tmp" .pre-commit-config.yaml
fi

# Workflow uses: refs
shopt -s nullglob
for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
  if grep -qE 'uses:[[:space:]]+deadbandlabs/dbl-buildroot/' "$wf"; then
    echo "==> updating $wf"
    sed -i -E "s|(uses:[[:space:]]+deadbandlabs/dbl-buildroot/[^@]+@)[A-Za-z0-9._-]+|\1$new_sha|g" "$wf"
  fi
done

# flake.lock: run only if expectedInputs changed
if [[ -f flake.nix ]]; then
  echo "==> refreshing flake.lock"
  nix flake update 2>&1 | sed 's/^/    /'
fi

echo "==> verifying consistency"
"$SCRIPT_DIR/sync-flake-inputs.sh" || true # autofix; non-zero just means it rewrote
"$SCRIPT_DIR/check-pinned-shas.sh" || {
  # check-pinned-shas reads from `git ls-tree HEAD` (committed pointer), so it
  # will fail until the caller stages the submodule. Soften the message.
  echo ""
  echo "note: SHA-pin check fails because the new submodule pointer is not"
  echo "      yet staged. Run: git add $SUBMODULE_PATH && rerun the check."
}

echo ""
echo "==> done. Stage with:"
echo "    git add $SUBMODULE_PATH .pre-commit-config.yaml .github/workflows/*.yml flake.lock"
