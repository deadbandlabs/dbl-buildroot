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

  inputs = { };

  outputs =
    _:
    (import ./modules/dbl-buildroot/lib.nix).mkProject {
      name = "@@PROJECT_NAME@@";
      board = "@@BOARD@@";
      extraExternalSrcs = [ ./overlay ];
      configFragment = ./overlay/@@PROJECT_NAME@@.fragment;
    };
}
