# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
{
  description = "Buildroot for MYD-YF135-256N-256D (STM32MP135D) SOM";

  nixConfig = {
    extra-substituters = [ "https://deadbandlabs.cachix.org" ];
    extra-trusted-public-keys = [
      "deadbandlabs.cachix.org-1:AizLR4DbQ0dbgsuZ0Dv+11iAc8N8JVuXjysDjihY0no="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    buildroot-nix = {
      url = "github:velentr/buildroot.nix/master";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.buildroot.follows = "buildroot"; # avoid duplicate fetches
    };

    # Buildroot 2025.02.12 (LTS)
    buildroot = {
      url = "gitlab:buildroot.org/buildroot/2025.02.12";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      buildroot-nix,
      buildroot,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # stm32cubeprog is unfree (ST license); allow it explicitly.
        config.allowUnfreePredicate = pkg: pkg.pname == "stm32cubeprog";
      };

      stm32cubeprog = pkgs.callPackage ./pkgs/stm32cubeprog.nix { };

      # Cmake 4.x compat wrapper fixer:
      #  1. Cmake configure mode: inject -DCMAKE_POLICY_VERSION_MINIMUM=3.5 so
      #     packages with cmake_minimum_required < 3.5 still configure.
      #  2. Cmake --build mode: strip a bare trailing -- that cmake 4.x no longer
      #     accepts when no native-tool args follow it.
      # Shared by both the devShell and the nix build FHS env (via nativeBuildInputs).
      cmake-compat = pkgs.writeShellScriptBin "cmake" ''
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
      '';

      # Two-stage hermetic build (see nix/build.nix)
      #   Stage 1: toolchain (cached across board-level changes)
      #   Stage 2: target packages + images
      buildPkgs = import ./nix/build.nix {
        inherit
          pkgs
          buildroot-nix
          buildroot
          self
          cmake-compat
          ;
      };

      # Development shells (see nix/devshell.nix)
      shells = import ./nix/devshell.nix {
        inherit
          pkgs
          buildroot
          cmake-compat
          stm32cubeprog
          ;
      };

    in
    {
      packages.${system} = {
        lockfile = buildPkgs.lockfile;
        default = buildPkgs.default;
        sdk = buildPkgs.sdk;
        inherit stm32cubeprog;
      };

      devShells.${system} = shells;
    };
}
