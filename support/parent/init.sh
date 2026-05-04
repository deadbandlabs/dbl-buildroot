#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Bootstrap a new dbl-buildroot-based parent project from the canonical
# template (modules/dbl-buildroot/support/parent/template/).
#
# Usage from the new project root, AFTER adding the submodule:
#
#   git init my-project && cd my-project
#   git submodule add git@github.com:deadbandlabs/dbl-buildroot.git \
#       modules/dbl-buildroot
#   modules/dbl-buildroot/support/parent/init.sh \
#       --name=my-project \
#       --copyright="2026 Acme Inc."
#
# Required:
#   --name=NAME              project name (used in flake, fragment filename, etc.)
#
# Optional:
#   --board=NAME             board name (drives defconfig + flashlayout convention,
#                            default: myd-yf135)
#   --copyright="YEAR HOLDER"  default: current year + "Deadband Inc."
#   --target-dir=DIR         default: cwd
#   --force                  overwrite existing files
#
# After init, review the generated files, run `make build` to verify, then
# stage + commit. Init does not run git for you.

set -euo pipefail

NAME=""
BOARD="myd-yf135"
COPYRIGHT_YEAR="$(date +%Y)"
COPYRIGHT_HOLDER="Deadband Inc."
TARGET_DIR="."
FORCE=0

usage() {
  sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //;s/^#//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name=*) NAME="${1#*=}" ;;
    --board=*) BOARD="${1#*=}" ;;
    --copyright=*)
      cp_value="${1#*=}"
      COPYRIGHT_YEAR="${cp_value%% *}"
      COPYRIGHT_HOLDER="${cp_value#* }"
      ;;
    --target-dir=*) TARGET_DIR="${1#*=}" ;;
    --force) FORCE=1 ;;
    -h | --help) usage 0 ;;
    *)
      echo "error: unknown arg: $1" >&2
      usage 2
      ;;
  esac
  shift
done

[[ -z "$NAME" ]] && {
  echo "error: --name is required" >&2
  usage 2
}

# Project name in upper-snake-case for BR2_EXTERNAL_<NAME>_PATH variable.
NAME_UPPER="${NAME^^}"
NAME_UPPER="${NAME_UPPER//-/_}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_DIR="$SUBMODULE_ROOT/support/parent/template"

if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "error: template dir not found: $TEMPLATE_DIR" >&2
  exit 2
fi

TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
SUBMODULE_PATH="$TARGET_DIR/modules/dbl-buildroot"

if [[ ! -e "$SUBMODULE_PATH/lib.nix" ]]; then
  echo "error: $SUBMODULE_PATH does not look like the dbl-buildroot submodule." >&2
  echo "       Add the submodule first:" >&2
  echo "       git submodule add git@github.com:deadbandlabs/dbl-buildroot.git modules/dbl-buildroot" >&2
  exit 2
fi

SUBMODULE_SHA="$(git -C "$SUBMODULE_PATH" rev-parse HEAD)"

echo "==> initializing project from template"
echo "    name:          $NAME"
echo "    board:         $BOARD"
echo "    copyright:     $COPYRIGHT_YEAR $COPYRIGHT_HOLDER"
echo "    target:        $TARGET_DIR"
echo "    submodule SHA: $SUBMODULE_SHA"
echo ""

substitute() {
  sed \
    -e "s|@@PROJECT_NAME@@|$NAME|g" \
    -e "s|@@PROJECT_NAME_UPPER@@|$NAME_UPPER|g" \
    -e "s|@@BOARD@@|$BOARD|g" \
    -e "s|@@COPYRIGHT_YEAR@@|$COPYRIGHT_YEAR|g" \
    -e "s|@@COPYRIGHT_HOLDER@@|$COPYRIGHT_HOLDER|g" \
    -e "s|@@SUBMODULE_SHA@@|$SUBMODULE_SHA|g"
}

# find -L follows the (presumed empty) overlay/package dir; -mindepth 1
# avoids the dot itself.
while IFS= read -r src; do
  rel="${src#"$TEMPLATE_DIR"/}"
  # filename substitution
  rel_subst="${rel//@@PROJECT_NAME@@/$NAME}"
  dst="$TARGET_DIR/$rel_subst"

  if [[ -e "$dst" && "$FORCE" -ne 1 ]]; then
    echo "skip (exists): $rel_subst"
    continue
  fi

  mkdir -p "$(dirname "$dst")"
  substitute <"$src" >"$dst"
  # Preserve executable bit
  if [[ -x "$src" ]]; then chmod +x "$dst"; fi
  echo "created: $rel_subst"
done < <(find "$TEMPLATE_DIR" -mindepth 1 -type f)

echo ""
echo "Init complete! Typical next steps:"
echo "  cd $TARGET_DIR"
echo "  git add -A && git commit -m 'feat: bootstrap from dbl-buildroot template'"
echo "  make build    # smoke-test the hermetic build"
echo "  ./modules/dbl-buildroot/support/pre-commit/install-pre-commit.sh"
