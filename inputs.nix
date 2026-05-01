# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Canonical flake-inputs declaration for both the submodule's own flake.nix
# and any downstream parent flake.
#
# To update nixpkgs, buildroot, buildroot-nix, edit this file and run
# `support/parent/sync-flake-inputs.sh` to propagate changes
# (or commit and let the pre-commit hook do it)
{
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  buildroot-nix = {
    url = "github:velentr/buildroot.nix/master";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.buildroot.follows = "buildroot";
  };
  buildroot = {
    url = "gitlab:buildroot.org/buildroot/2025.02.12";
    flake = false;
  };
}
