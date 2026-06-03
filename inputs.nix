# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Canonical, rev-pinned input URLs
#
# `lib.nix` self-fetches these via `builtins.getFlake` / `builtins.fetchTree`,
# so parent flakes do NOT need to redeclare these inputs. Bump a pin = edit
# this file, commit, bump submodule pointer in parent
{
  nixpkgs.url = "github:NixOS/nixpkgs/535f3e6942cb1cead3929c604320d3db54b542b9";
  buildroot-nix.url = "github:velentr/buildroot.nix/a9090cd64ce2b595a68b2acf2f13463b75673d80";
  # Non-flake inputs: lib.nix uses builtins.fetchGit, which requires
  # a full-SHA rev to be allowed in pure eval mode
  buildroot = {
    url = "https://gitlab.com/buildroot.org/buildroot.git";
    rev = "898251ee2b83a9cd5ae0ae5db57828035a5a6f85";
    flake = false;
  };
}
