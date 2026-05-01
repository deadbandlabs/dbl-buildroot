# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Cmake 4.x compatibility wrapper.
# Imported by both flake.nix (devShell + build) and downstream repos that
# call build.nix directly.
#
#  1. Configure mode: inject -DCMAKE_POLICY_VERSION_MINIMUM=3.5 so
#     packages with cmake_minimum_required < 3.5 still configure.
#  2. Build mode: strip a bare trailing -- that cmake 4.x no longer
#     accepts when no native-tool args follow it.
{ pkgs }:
pkgs.writeShellScriptBin "cmake" ''
  case "$1" in
    --build)
      # cmake 4.x: strip bare trailing -- with no following native args
      args=("$@")
      if [ "''${args[-1]}" = "--" ]; then unset 'args[-1]'; fi
      exec ${pkgs.cmake}/bin/cmake "''${args[@]}"
      ;;
    --*)
      # Other mode flags (--install, --open, --version, etc.): pass through
      exec ${pkgs.cmake}/bin/cmake "$@"
      ;;
    *)
      # Configure mode: inject policy version minimum for old CMakeLists.txt
      exec ${pkgs.cmake}/bin/cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "$@"
      ;;
  esac
''
