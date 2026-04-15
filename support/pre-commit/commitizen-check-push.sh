#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
set -euo pipefail

# Check all commits being pushed conform to Conventional Commits.
# pre-commit passes pushed refs on stdin: <local-ref> <local-sha> <remote-ref> <remote-sha>
# In CI, set CZ_CHECK_BASE to the base commit SHA to check HEAD against instead.
#
# Usage: commitizen-check-push.sh [<base>]
#   <base>  Check commits from <base>..HEAD (e.g. HEAD~3, a commit SHA, main)
#           Overrides CZ_CHECK_BASE env var.

if [ "${1:-}" != "" ]; then
  CZ_CHECK_BASE="$(git rev-parse "$1")"
fi

# When run directly (not via pre-commit hook or CI), re-exec inside the
# pre-commit nix shell so cz is available.
if [ -z "${CI:-}" ] && ! command -v cz >/dev/null 2>&1; then
  repo_root="$(git rev-parse --show-toplevel)"
  exec nix develop --option warn-dirty false "${repo_root}#pre-commit" -c "$0" "$@"
fi

check_commit() {
  local sha="$1"
  local msg
  msg=$(git log -1 --format="%s" "$sha")
  if ! cz check --allow-abort --commit-msg-file <(echo "$msg") 2>&1; then
    return 1
  fi
}

status=0

if [ -n "${CZ_CHECK_BASE:-}" ]; then
  # CI mode: check all commits between base and HEAD
  for sha in $(git log --format="%H" "${CZ_CHECK_BASE}..HEAD"); do
    check_commit "$sha" || status=1
  done
else
  # Hook mode: read refs from stdin (git pre-push protocol)
  while read -r _local_ref local_sha _remote_ref remote_sha; do
    # Branch deletion: nothing to check
    if [ "$local_sha" = "0000000000000000000000000000000000000000" ]; then
      continue
    fi

    # New branch: check all commits not reachable from any remote ref
    if [ "$remote_sha" = "0000000000000000000000000000000000000000" ]; then
      commits=$(git log --format="%H" "$local_sha" --not --remotes 2>/dev/null || true)
    else
      commits=$(git log --format="%H" "${remote_sha}..${local_sha}")
    fi

    for sha in $commits; do
      check_commit "$sha" || status=1
    done
  done
fi

exit "$status"
