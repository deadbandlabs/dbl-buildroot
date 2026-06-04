#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
set -eu

project_root=$1
release_o=$2
debug_o=$3
share_host_for_debug=$4
make_bin=$5

# Remove host toolchain symlinks left by a previous SHARE_HOST_FOR_DEBUG=1 run
teardown_share_links() {
  [ -L "$debug_o/host" ] && rm -f "$debug_o/host"
  for l in "$debug_o"/build/host-*; do
    [ -L "$l" ] && rm -f "$l"
  done
  return 0
}

if [ "$share_host_for_debug" != "1" ]; then
  teardown_share_links
  exit 0
fi

if [ ! -d "$release_o/host" ]; then
  echo "INFO: $release_o/host not found: building release host tools"
  "$make_bin" -C "$project_root" MODE=release host-toolchain
fi

mkdir -p "$debug_o" "$debug_o/build"

if [ -e "$debug_o/host" ] && [ ! -L "$debug_o/host" ]; then
  echo "WARN: $debug_o/host exists and is not a symlink: leaving as-is"
else
  ln -sfn "$release_o/host" "$debug_o/host"
  echo "Linking $release_o/host -> $debug_o/host"
fi

for src in "$release_o"/build/host-*; do
  [ -e "$src" ] || continue
  name=$(basename "$src")
  dst="$debug_o/build/$name"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "WARN: $dst exists and is not a symlink: leaving as-is"
    continue
  fi
  ln -sfn "$src" "$dst"
done
