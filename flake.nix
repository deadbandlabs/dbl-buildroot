# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# This flake exists for the submodule's own dev shell + CI build
# Downstream repos should import lib.nix directly (see lib.nix docstring)
# Do not consume this flake directly
{
  description = "Buildroot for MYD-YF135-256N-256D (STM32MP135D) SOM";

  nixConfig = {
    extra-substituters = [ "https://deadbandlabs.cachix.org" ];
    extra-trusted-public-keys = [
      "deadbandlabs.cachix.org-1:AizLR4DbQ0dbgsuZ0Dv+11iAc8N8JVuXjysDjihY0no="
    ];
  };

  # Note: Inputs auto-generated from inputs.nix by sync-flake-inputs.sh
  inputs = {
    # DBL_BR_INPUTS_BEGIN
    buildroot = {
      flake = false;
      url = "gitlab:buildroot.org/buildroot/2025.02.12";
    };
    buildroot-nix = {
      inputs = {
        buildroot = {
          follows = "buildroot";
        };
        nixpkgs = {
          follows = "nixpkgs";
        };
      };
      url = "github:velentr/buildroot.nix/master";
    };
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-25.11";
    };
    # DBL_BR_INPUTS_END
  };

  outputs =
    {
      self,
      nixpkgs,
      buildroot-nix,
      buildroot,
    }:
    (import ./lib.nix).mkProject {
      inherit nixpkgs buildroot buildroot-nix;
      name = "myd-yf135";
      defconfig = "myd_yf135_defconfig";
      flashLayout = "board/myd-yf135/flashlayout.tsv";
    };
}
