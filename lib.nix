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
      # Extra defconfig fragment for the debug image only (`debug` package output)
      # Merged after configs/myc_yf135_debug.fragment, like DBL_BR_FRAGMENT_DEBUG
      # Must not add packages absent from `lockfile` (release config)
      configFragmentDebug ? null,
      # Path (relative to the build's external source) to a programmer-variant
      # defconfig fragment. Defaults to the submodule's MYC-YF135 fragment so
      # downstream consumers get a working USB DFU loader bundled into their
      # images by default. Override with a project-specific fragment path, or
      # set to null to disable the programmer build entirely.
      programmerFragment ? "configs/myc_yf135_programmer.fragment",
      # Consent session variant fragment, built alongside programmer variant
      # with BR2_PACKAGE_DBL_VERIFIED_BOOT=y. Set to null to disable.
      consentFragment ? "configs/myc_yf135_consent.fragment",
      extraExternalSrcs ? [ ],
      # Extra rootfs overlay dirs to stack onto BR2_ROOTFS_OVERLAY
      # for image content built by Nix instead of a Buildroot package
      # (e.g. a cross-built rust binary)
      # Passed `sdk` (the image's toolchain) and `pkgs` to ensure binary is linked against image libc
      extraRootfsOverlays ? ({ sdk, pkgs }: [ ]),
      # Buildroot target package lockfile (override when using overlay packages)
      lockfile ? (./. + "/buildroot.lock"),
      # Extra { "<filename>" = "<sha256>"; } over nix/source-hashes.nix
      extraSourceHashes ? { },
      # Custom toolchain (leave null to reuse this repo's cached SDK)
      toolchainName ? null,
      toolchainDefconfig ? null,
      toolchainLockfile ? null,
      toolchainFragment ? null,
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
          pkgs = import nixpkgs { inherit system; };

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

          buildPkgs = import ./nix/build.nix (
            {
              inherit
                pkgs
                buildroot
                buildroot-nix
                cmake-compat
                certEnv
                extraExternalSrcs
                extraRootfsOverlays
                configFragment
                configFragmentDebug
                programmerFragment
                consentFragment
                extraSourceHashes
                ;
              self = ./.;
              projectName = name;
              defconfigName = defconfig;
              flashLayoutPath = flashLayout;
              lockfilePath = lockfile;
            }
            // lib.optionalAttrs (toolchainName != null) { inherit toolchainName; }
            // lib.optionalAttrs (toolchainDefconfig != null) { inherit toolchainDefconfig; }
            // lib.optionalAttrs (toolchainLockfile != null) { inherit toolchainLockfile; }
            // lib.optionalAttrs (toolchainFragment != null) { inherit toolchainFragment; }
          );

          shells = import ./nix/devshell.nix {
            inherit
              pkgs
              cmake-compat
              certEnv
              ;
            inherit buildroot;
            extraPackages = extraDevShellPackages;
            # dev/ci make builds use this repo's cached toolchain SDK
            # A custom toolchain is not resolvable from the submodule flake,
            # pass TOOLCHAIN_SDK=<path> instead
            nixToolchain =
              toolchainName == null
              && toolchainDefconfig == null
              && toolchainLockfile == null
              && toolchainFragment == null;
          };
        in
        {
          packages.${system} = {
            inherit (buildPkgs)
              default
              debug
              sdk
              lockfile
              toolchain
              toolchain-lockfile
              ;
            # dbl-bootid EEPROM layout + example image for host tools
            dbl-bootid-layout = pkgs.runCommand "dbl-bootid-layout" { } ''
              mkdir -p $out
              cp ${./board/myc-yf135/dbl-bootid.toml} $out/dbl-bootid.toml
              cp ${./board/myc-yf135/dbl-bootid-example.bin} $out/dbl-bootid-example.bin
            '';
          };
          devShells.${system} = shells;
        };
    in
    lib.foldl' lib.recursiveUpdate { } (map mkForSystem systems);
}
