#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Regenerate the `inputs = { ... };` block of a target flake.nix from the
# canonical modules/dbl-buildroot/inputs.nix.
#
# Marker comments delimit the auto-managed region:
#
#   inputs = {
#     # DBL_BR_INPUTS_BEGIN
#     ...auto-generated...
#     # DBL_BR_INPUTS_END
#   };
#
# Targets:
#   default = ./flake.nix in cwd (parent repo)
#   plus the submodule's own modules/dbl-buildroot/flake.nix (so a bump in
#   inputs.nix flows to both with one commit)
#
# Designed as a pre-commit autofix hook: rewrites in place, exits 1 if any
# file changed (which makes pre-commit re-run after fix).
#
# Usage:
#   support/parent/sync-flake-inputs.sh           # parent + submodule
#   support/parent/sync-flake-inputs.sh <file>... # explicit targets
#
# Exit codes: 0 = no changes, 1 = changes written, 2 = invocation error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INPUTS_NIX="$SUBMODULE_ROOT/inputs.nix"

if [[ ! -f "$INPUTS_NIX" ]]; then
  echo "error: $INPUTS_NIX not found" >&2
  exit 2
fi

if [[ $# -eq 0 ]]; then
  set -- ./flake.nix "$SUBMODULE_ROOT/flake.nix"
fi

# Render inputs.nix as a body to slot between markers. We use nix-instantiate
# to print the attrset, then strip the outer braces. nix's pretty-printer
# emits each attribute on its own line.
# shellcheck disable=SC2016
body="$(nix eval --file "$INPUTS_NIX" --raw --apply '
  inputs:
  let
    lib = (import <nixpkgs> {}).lib;
    # Walk the attrset and render each top-level binding as a single nix
    # expression line. Sub-attrsets are printed with proper indent.
    renderVal = v: indent:
      if builtins.isAttrs v then
        "{\n" +
        lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v2:
          "${indent}  ${k} = ${renderVal v2 (indent + "  ")};"
        ) v) +
        "\n${indent}}"
      else if builtins.isString v then "\"${v}\""
      else if builtins.isBool v then (if v then "true" else "false")
      else throw "unsupported value type";
  in
    lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v:
      "    ${k} = ${renderVal v "    "};"
    ) inputs)
' 2>/dev/null)"

if [[ -z "$body" ]]; then
  echo "error: failed to render inputs.nix (need <nixpkgs> in NIX_PATH)" >&2
  exit 2
fi

changed=0

for target in "$@"; do
  if [[ ! -f "$target" ]]; then
    echo "skip: $target not found" >&2
    continue
  fi

  if ! grep -q "DBL_BR_INPUTS_BEGIN" "$target"; then
    echo "skip: $target has no DBL_BR_INPUTS_BEGIN marker" >&2
    continue
  fi

  tmp="$(mktemp)"
  awk -v body="$body" '
    /DBL_BR_INPUTS_BEGIN/ {
      print
      print body
      in_block = 1
      next
    }
    /DBL_BR_INPUTS_END/ {
      in_block = 0
      print
      next
    }
    !in_block { print }
  ' "$target" >"$tmp"

  if ! cmp -s "$target" "$tmp"; then
    mv "$tmp" "$target"
    echo "rewrote: $target"
    changed=1
  else
    rm -f "$tmp"
  fi
done

exit $changed
