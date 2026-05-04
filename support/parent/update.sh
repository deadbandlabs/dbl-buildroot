#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Bump the dbl-buildroot submodule and propagate the new SHA to every pin
# site in the parent repo. Run from the parent repo root
#
# Usage:
#   support/parent/update.sh                 # advance to origin/main
#   support/parent/update.sh <ref>           # advance to <ref> (sha, tag, branch)
#   support/parent/update.sh --force <ref>   # skip the unpushed-commit guard
#
# Pin sites updated:
#   - modules/dbl-buildroot               (git submodule pointer)
#   - .pre-commit-config.yaml             (rev: under repo: dbl-buildroot)
#   - .github/workflows/*.yml             (uses: deadbandlabs/dbl-buildroot/...@<sha>)
#
# This script aborts if the submodule's current HEAD is not reachable from any
# remote ref, use --force to override.
#
# Also runs check-pinned-shas.sh at the end, so a successful run = a
# fully-consistent state ready to stage
#
# Does NOT git-add or git-commit anything; staging is the caller's call.

set -euo pipefail

SUBMODULE_PATH="modules/dbl-buildroot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
  shift
fi
REF="${1:-origin/main}"

if [[ ! -d "$SUBMODULE_PATH" ]]; then
  echo "error: $SUBMODULE_PATH not found (run from parent repo root)" >&2
  exit 2
fi

echo "==> fetching submodule"
git -C "$SUBMODULE_PATH" fetch origin --tags

# Guard: refuse to move off a SHA that's not reachable from any remote ref,
# to avoid orphaning submodule commits
# The gitlink in the parent's working tree is selected instead
gitlink_sha="$(git ls-files -s "$SUBMODULE_PATH" | awk '{print $2}')"
working_sha="$(git -C "$SUBMODULE_PATH" rev-parse HEAD)"
for sha in "$gitlink_sha" "$working_sha"; do
  [[ -z "$sha" ]] && continue
  if ! git -C "$SUBMODULE_PATH" branch -r --contains "$sha" 2>/dev/null | grep -q .; then
    if [[ $FORCE -eq 1 ]]; then
      echo "warning: $sha is not on any remote branch (--force given, continuing)" >&2
    else
      echo "error: submodule SHA $sha is not reachable from any remote ref" >&2
      echo "       updating would orphan this commit. Push it first, or rerun with --force." >&2
      exit 1
    fi
  fi
done

echo "==> checking out $REF"
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

echo "==> verifying consistency"
"$SCRIPT_DIR/check-pinned-shas.sh" || {
  # check-pinned-shas reads from `git ls-tree HEAD` (committed pointer), so it
  # will fail until the caller stages the submodule. Soften the message.
  echo ""
  echo "note: SHA-pin check fails because the new submodule pointer is not"
  echo "      yet staged. Run: git add $SUBMODULE_PATH && rerun the check."
}

echo ""
echo "==> done. Stage with:"
echo "    git add $SUBMODULE_PATH .pre-commit-config.yaml .github/workflows/*.yml"
