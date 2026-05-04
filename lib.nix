# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Plain-nix entry point for downstream consumers
#
# This file is imported directly (not as a flake input) so that downstream
# repos consuming the submodule via `import ./modules/dbl-buildroot/lib.nix`
# get a single-pin (submodule SHA) integration with no flake-input duplication
#
# Two exports:
#
#   expectedInputs : { name = url-or-attrset; ... }
#     The flake inputs the submodule expects the parent to declare.
#     `support/parent/check-flake-inputs.sh` diffs this against the parent's
#     `flake.nix` and fails on drift
#
#   mkProject : { nixpkgs, buildroot, buildroot-nix
#               , name, defconfig, flashLayout
#               , extraExternalSrcs ? [], configFragment ? null
#               , system ? "x86_64-linux"
#               , extraDevShellPackages ? []
#               } -> flake-output-attrset
#     Returns `{ packages.${system}; devShells.${system}; }` for the parent
#     flake to splat into its own outputs
{
  # Canonical inputs declaration exported here so downstream consumers
  # can introspect via lib.expectedInputs without an extra import
  expectedInputs = import ./inputs.nix;

  mkProject =
    {
      nixpkgs,
      buildroot,
      buildroot-nix,
      name,
      defconfig,
      flashLayout,
      extraExternalSrcs ? [ ],
      configFragment ? null,
      system ? "x86_64-linux",
      extraDevShellPackages ? [ ],
    }:
    let
      pkgs = import nixpkgs {
        inherit system;
        # stm32cubeprog is unfree (ST license); allow it explicitly.
        config.allowUnfreePredicate = pkg: pkg.pname == "stm32cubeprog";
      };

      stm32cubeprog = pkgs.callPackage ./nix/stm32cubeprog.nix { };
      cmake-compat = pkgs.callPackage ./nix/cmake-compat.nix { };

      buildPkgs = import ./nix/build.nix {
        inherit
          pkgs
          buildroot-nix
          buildroot
          cmake-compat
          extraExternalSrcs
          configFragment
          ;
        # Path to the submodule root for buildExternalSrc + configs/
        self = ./.;
        projectName = name;
        defconfigName = defconfig;
        flashLayoutPath = flashLayout;
      };

      shells = import ./nix/devshell.nix {
        inherit
          pkgs
          buildroot
          cmake-compat
          stm32cubeprog
          ;
        extraPackages = extraDevShellPackages;
      };
    in
    {
      packages.${system} = {
        inherit (buildPkgs) default sdk lockfile;
        inherit stm32cubeprog;
      };
      devShells.${system} = shells;
    };
}
