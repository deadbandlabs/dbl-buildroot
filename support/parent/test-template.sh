#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Verify the parent template by instantiating it into a temp dir and
# running the same checks a real parent would run on commit.
#
# Tests:
#   - template files missing required placeholders (or extras)
#   - init.sh substitution bugs
#   - generated flake failing `nix flake check`
#   - hooks added to template but missing from .pre-commit-hooks.yaml
#
# Run locally:
#   support/parent/test-template.sh
#
# Run in CI: see .github/workflows/template-test.yml
#
# Exit 0 = template is valid, 1 = drift detected.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> work dir: $WORK"

# Copy submodule as regular files (not a git submodule) for the test env
cp -a "$SUBMODULE_ROOT" "$WORK/modules-source"
mkdir -p "$WORK/parent/modules"
cp -a "$WORK/modules-source/." "$WORK/parent/modules/dbl-buildroot/"
rm -rf "$WORK/parent/modules/dbl-buildroot/.git"

# Create temp git repo for init.sh to get a SHA for support tools
git -C "$WORK/parent/modules/dbl-buildroot" init -q -b main
git -C "$WORK/parent/modules/dbl-buildroot" add -A
git -C "$WORK/parent/modules/dbl-buildroot" \
  -c user.email=test@local -c user.name=test \
  commit -q -m "snapshot for template test"

# Init parent repo
git -C "$WORK/parent" init -q -b main

echo "==> running init.sh"
cd "$WORK/parent"
"$WORK/parent/modules/dbl-buildroot/support/parent/init.sh" \
  --name=template-test \
  --copyright="2026 Test Inc."

# Remove/clean git context for test
rm -rf "$WORK/parent/modules/dbl-buildroot/.git"
git -C "$WORK/parent" add -A
git -C "$WORK/parent" \
  -c user.email=test@local -c user.name=test \
  commit -q -m "initial commit"

# All template files present?
for f in flake.nix Makefile .envrc .gitignore .pre-commit-config.yaml \
  REUSE.toml .github/workflows/build.yml \
  overlay/Config.in overlay/external.desc overlay/external.mk \
  overlay/template-test.fragment overlay/package/Config.in; do
  if [[ ! -f "$WORK/parent/$f" ]]; then
    echo "FAIL: expected template file missing: $f" >&2
    exit 1
  fi
done

# No leftover @@PLACEHOLDER@@ tokens?
if grep -rE '@@[A-Z_]+@@' "$WORK/parent" \
  --exclude-dir=modules --exclude-dir=.git >/dev/null; then
  echo "FAIL: leftover @@PLACEHOLDER@@ tokens in generated files:" >&2
  grep -rEn '@@[A-Z_]+@@' "$WORK/parent" \
    --exclude-dir=modules --exclude-dir=.git >&2
  exit 1
fi

# Every hook ID in template's .pre-commit-config.yaml must exist in
# the submodule's .pre-commit-hooks.yaml.
listed_ids="$(awk '/^[[:space:]]*-[[:space:]]*id:/ { print $3 }' \
  "$WORK/parent/.pre-commit-config.yaml")"
defined_ids="$(awk '/^-[[:space:]]*id:/ { print $3 }' \
  "$WORK/parent/modules/dbl-buildroot/.pre-commit-hooks.yaml")"
for id in $listed_ids; do
  if ! grep -qxF "$id" <<<"$defined_ids"; then
    echo "FAIL: template lists hook '$id' but it is not in .pre-commit-hooks.yaml" >&2
    exit 1
  fi
done

# Hermetic flake-eval check.
echo "==> nix flake check"
nix flake check --no-build "$WORK/parent"

echo ""
echo "PASS: template instantiates cleanly and passes all parent checks."
