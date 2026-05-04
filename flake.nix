# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# This flake exists for the submodule's own dev shell + CI build
# Downstream repos should import lib.nix, do not consume this flake directly
#
# lib.nix self-fetches pins from inputs.nix
{
  description = "Buildroot for MYD-YF135-256N-256D (STM32MP135D) SOM";

  nixConfig = {
    extra-substituters = [ "https://deadbandlabs.cachix.org" ];
    extra-trusted-public-keys = [
      "deadbandlabs.cachix.org-1:AizLR4DbQ0dbgsuZ0Dv+11iAc8N8JVuXjysDjihY0no="
    ];
  };

  inputs = { };

  outputs =
    _:
    (import ./lib.nix).mkProject {
      name = "myd-yf135";
      board = "myd-yf135";
    };
}
