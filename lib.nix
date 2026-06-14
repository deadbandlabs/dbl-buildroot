# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Plain-nix entry point for downstream consumers
#
# Imported directly so downstream repos consuming the submodule via
# `import ./modules/dbl-buildroot/lib.nix` get a single integration point
#
# Inputs are self-fetched from ./inputs.nix so parent flakes do NOT need to
# redeclare nixpkgs/buildroot/buildroot-nix. Override args remain on
# `mkProject` if a parent ever needs to override a pinned rev
#
# Single export:
#
#   mkProject :: { name, board, ... } -> flake-output-attrset
#     Returns `{ packages.${system}; devShells.${system}; }` for each system
#     in `systems`, for the parent flake to splat into its own outputs
let
  pins = import ./inputs.nix;
  loadInput =
    p:
    if p.flake or true then
      builtins.getFlake p.url
    else
      # Non-flake input: fetchGit with a full-SHA rev is treated as locked
      # in pure eval mode, no narHash needed
      builtins.fetchGit {
        inherit (p) url rev;
      };
  defaultPins = builtins.mapAttrs (_: loadInput) pins;
in
{
  mkProject =
    {
      name,
      board,
      nixpkgs ? defaultPins.nixpkgs,
      buildroot ? defaultPins.buildroot,
      buildroot-nix ? defaultPins.buildroot-nix,
      defconfig ? "${builtins.replaceStrings [ "-" ] [ "_" ] board}_defconfig",
      flashLayout ? "board/${board}/flashlayout.tsv",
      configFragment ? null,
      # Path (relative to the build's external source) to a programmer-variant
      # defconfig fragment. Defaults to the submodule's MYD-YF135 fragment so
      # downstream consumers get a working USB DFU loader bundled into their
      # images by default. Override with a project-specific fragment path, or
      # set to null to disable the programmer build entirely.
      programmerFragment ? "configs/myd_yf135_programmer.fragment",
      extraExternalSrcs ? [ ],
      # Buildroot package lockfile. Defaults to local
      # Downstream repos with overlay packages can provide e.g. `lockfile = ./buildroot.lock;`
      lockfile ? (./. + "/buildroot.lock"),
      systems ? [
        "x86_64-linux"
        "aarch64-linux"
      ],
      extraDevShellPackages ? [ ],
    }:
    let
      lib = nixpkgs.lib;

      mkForSystem =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            # stm32cubeprog is unfree (ST license); allow it explicitly.
            config.allowUnfreePredicate = pkg: pkg.pname == "stm32cubeprog";
          };

          stm32cubeprog =
            if pkgs.stdenv.hostPlatform.isx86_64 then pkgs.callPackage ./nix/stm32cubeprog.nix { } else null;
          cmake-compat = pkgs.callPackage ./nix/cmake-compat.nix { };

          # Shared CA cert env for Nix-provided wget/curl/git (no system CA bundle)
          wgetrc = pkgs.writeText "wgetrc" ''
            ca_certificate = ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          '';
          certEnv = ''
            export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            export GIT_SSL_CAINFO="$SSL_CERT_FILE"
            export CURL_CA_BUNDLE="$SSL_CERT_FILE"
            export WGETRC="${wgetrc}"
          '';

          buildPkgs = import ./nix/build.nix {
            inherit
              pkgs
              buildroot
              buildroot-nix
              cmake-compat
              certEnv
              extraExternalSrcs
              configFragment
              programmerFragment
              ;
            self = ./.;
            projectName = name;
            defconfigName = defconfig;
            flashLayoutPath = flashLayout;
            lockfilePath = lockfile;
          };

          shells = import ./nix/devshell.nix {
            inherit
              pkgs
              cmake-compat
              stm32cubeprog
              certEnv
              ;
            inherit buildroot;
            extraPackages = extraDevShellPackages;
          };
        in
        {
          packages.${system} = {
            inherit (buildPkgs) default sdk lockfile;
          }
          // lib.optionalAttrs (stm32cubeprog != null) { inherit stm32cubeprog; };
          devShells.${system} = shells;
        };
    in
    lib.foldl' lib.recursiveUpdate { } (map mkForSystem systems);
}
