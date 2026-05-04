#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Verify all SHA pins in the parent repo point at the currently-checked-out
# submodule SHA.
#
# Three pin sites:
#   1. .gitmodules / git submodule status   (canonical = committed pointer)
#   2. .pre-commit-config.yaml `rev:` for the dbl-buildroot repo
#   3. .github/workflows/*.yml `uses: deadbandlabs/dbl-buildroot/...@<sha>`
#
# Drift = parent CI runs against a different submodule SHA than the working
# tree, so build/lint/test results diverge from local dev.
#
# Usage: support/parent/check-pinned-shas.sh
# Run from the parent repo root.
#
# Exit 0 = all match, 1 = drift, 2 = invocation error.

set -euo pipefail

SUBMODULE_PATH="modules/dbl-buildroot"

if [[ ! -d "$SUBMODULE_PATH/.git" && ! -f "$SUBMODULE_PATH/.git" ]]; then
  echo "error: $SUBMODULE_PATH is not a git submodule (run from parent repo root)" >&2
  exit 2
fi

# Canonical SHA = the commit the parent's HEAD index points to for the
# submodule. (Not the submodule's working-tree HEAD; that may be ahead/behind.)
# If HEAD does not exist (first commit), read from the index via ls-files.
if git rev-parse HEAD >/dev/null 2>&1; then
  canonical="$(git ls-tree HEAD "$SUBMODULE_PATH" | awk '{print $3}')"
else
  canonical="$(git ls-files -s "$SUBMODULE_PATH" | awk '{print $2}')"
fi
if [[ -z "$canonical" ]]; then
  echo "error: could not read submodule SHA from git index" >&2
  exit 2
fi

drift=0

check_pin() {
  local label="$1" sha="$2" location="$3"
  if [[ "$sha" != "$canonical" ]]; then
    echo "drift: $label = $sha (expected $canonical, at $location)" >&2
    drift=1
  fi
}

# Pre-commit
if [[ -f .pre-commit-config.yaml ]]; then
  pc_sha="$(awk '
    /repo: .*dbl-buildroot/ { in_repo = 1; next }
    in_repo && /^[[:space:]]*rev:/ { print $2; exit }
    /^[[:space:]]*-[[:space:]]*repo:/ && in_repo { in_repo = 0 }
  ' .pre-commit-config.yaml | tr -d '"' | tr -d "'")"
  if [[ -n "$pc_sha" ]]; then
    check_pin "pre-commit rev" "$pc_sha" ".pre-commit-config.yaml"
  fi
fi

# GitHub workflows: uses: <repo>@<sha>
shopt -s nullglob
for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
  while IFS= read -r line; do
    # extract sha after the last @
    wf_sha="${line##*@}"
    wf_sha="${wf_sha%%[[:space:]]*}"
    check_pin "workflow uses" "$wf_sha" "$wf"
  done < <(grep -E 'uses:[[:space:]]+deadbandlabs/dbl-buildroot/' "$wf" || true)
done

if [[ $drift -eq 0 ]]; then
  exit 0
fi

echo "" >&2
echo "Run: make update-dbl-buildroot" >&2
exit 1
