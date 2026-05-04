# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Canonical, rev-pinned input URLs
#
# `lib.nix` self-fetches these via `builtins.getFlake` / `builtins.fetchTree`,
# so parent flakes do NOT need to redeclare these inputs. Bump a pin = edit
# this file, commit, bump submodule pointer in parent
{
  nixpkgs.url = "github:NixOS/nixpkgs/7e495b747b51f95ae15e74377c5ce1fe69c1765f";
  buildroot-nix.url = "github:velentr/buildroot.nix/a9090cd64ce2b595a68b2acf2f13463b75673d80";
  # Non-flake inputs: lib.nix uses builtins.fetchGit, which requires
  # a full-SHA rev to be allowed in pure eval mode
  buildroot = {
    url = "https://gitlab.com/buildroot.org/buildroot.git";
    rev = "137a566bf5353831d97c068a4c22e6df5b4d07a0";
    flake = false;
  };
}
