#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
set -eu

if [ "$#" -ne 3 ]; then
  printf 'Usage: %s <release_defconfig> <debug_delta> <output_debug_defconfig>\n' "$0" >&2
  exit 1
fi

release_defconfig=$1
debug_delta=$2
output_defconfig=$3

awk '
function cfg_key(line, m) {
  if (match(line, /^([A-Z0-9_]+)=/, m)) return m[1]
  if (match(line, /^# ([A-Z0-9_]+) is not set$/, m)) return m[1]
  return ""
}
FNR == NR {
  if ($0 ~ /^[[:space:]]*$/) next
  if ($0 ~ /^[[:space:]]*#/) next
  k = cfg_key($0)
  if (k != "") {
    overrides[k] = $0
    order[++n] = k
  }
  next
}
{
  k = cfg_key($0)
  if (k != "" && (k in overrides)) {
    if (!(k in emitted)) {
      print overrides[k]
      emitted[k] = 1
    }
    next
  }
  print $0
}
END {
  for (i = 1; i <= n; i++) {
    k = order[i]
    if (!(k in emitted))
      print overrides[k]
  }
}
' "$debug_delta" "$release_defconfig" >"$output_defconfig"
