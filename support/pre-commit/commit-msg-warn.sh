#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
set -euo pipefail

msg_file="${1:-}"
if [ -z "$msg_file" ]; then
  echo "warning: commit-msg-warn.sh expected commit message filename" >&2
  exit 0
fi

if ! cz check --allow-abort --commit-msg-file "$msg_file"; then
  echo "warning: commit message is not Conventional Commits compliant" >&2
  echo "warning: commit allowed (warning-only mode)" >&2
fi

exit 0
