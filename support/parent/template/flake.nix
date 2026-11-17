# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright @@COPYRIGHT_YEAR@@ @@COPYRIGHT_HOLDER@@
#
# Pins live in modules/dbl-buildroot/inputs.nix and are self-fetched by lib.nix
{
  description = "@@PROJECT_NAME@@ system image";

  nixConfig = {
    extra-substituters = [ "https://deadbandlabs.cachix.org" ];
    extra-trusted-public-keys = [
      "deadbandlabs.cachix.org-1:AizLR4DbQ0dbgsuZ0Dv+11iAc8N8JVuXjysDjihY0no="
    ];
  };

  inputs = {
    # Include git submodules (modules/dbl-buildroot) in the flake source (Nix 2.27+)
    self.submodules = true;
  };

  outputs =
    _:
    (import ./modules/dbl-buildroot/lib.nix).mkProject {
      name = "@@PROJECT_NAME@@";
      board = "@@BOARD@@";
      extraExternalSrcs = [ ./overlay ];
      configFragment = ./overlay/@@PROJECT_NAME@@.fragment;
      # Debug-only additions, used by `make debug` and `nix build .#debug`
      configFragmentDebug = ./overlay/@@PROJECT_NAME@@-debug.fragment;
      # Project-local lock covering overlay-selected packages
      # Regenerate with `make nix-lock`
      lockfile = ./buildroot.lock;
    };
}
