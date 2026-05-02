# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright @@COPYRIGHT_YEAR@@ @@COPYRIGHT_HOLDER@@
{
  description = "@@PROJECT_NAME@@ system image";

  nixConfig = {
    extra-substituters = [ "https://deadbandlabs.cachix.org" ];
    extra-trusted-public-keys = [
      "deadbandlabs.cachix.org-1:AizLR4DbQ0dbgsuZ0Dv+11iAc8N8JVuXjysDjihY0no="
    ];
  };

  # Inputs auto-managed by modules/dbl-buildroot/support/parent/sync-flake-inputs.sh.
  # !! Do not edit between the markers (will be overwritten by pre-commit) !!
  inputs = {
    # DBL_BR_INPUTS_BEGIN
    # DBL_BR_INPUTS_END
  };

  outputs =
    {
      nixpkgs,
      buildroot,
      buildroot-nix,
      ...
    }:
    (import ./modules/dbl-buildroot/lib.nix).mkProject {
      inherit nixpkgs buildroot buildroot-nix;
      name = "@@PROJECT_NAME@@";
      defconfig = "@@DEFCONFIG@@";
      flashLayout = "@@FLASH_LAYOUT@@";
      extraExternalSrcs = [ ./overlay ];
      configFragment = ./overlay/@@PROJECT_NAME@@.fragment;
    };
}
