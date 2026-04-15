# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
{
  description = "Buildroot for MYD-YF135-256N-256D (STM32MP135D) SOM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    buildroot-nix = {
      url = "github:velentr/buildroot.nix/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Buildroot 2025.02.12 (LTS)
    buildroot = {
      url = "gitlab:buildroot.org/buildroot/2025.02.12";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, buildroot-nix, buildroot }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      # stm32cubeprog is unfree (ST license); allow it explicitly.
      config.allowUnfreePredicate = pkg: pkg.pname == "stm32cubeprog";
    };

    stm32cubeprog = pkgs.callPackage ./pkgs/stm32cubeprog.nix {};

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

    # Our repo is a BR2_EXTERNAL tree; src points at upstream buildroot
    # Generate the lockfile with:
    #   nix build .#lockfile && cp -L result buildroot.lock
    # Then build the image with:
    #   nix build
    buildrootPackages = buildroot-nix.lib.mkBuildroot {
      name = "myd-yf135";
      inherit pkgs;
      src = buildroot;
      externalSrc = self;
      defconfig = "myd_yf135_defconfig";
      lockfile = ./buildroot.lock;
      nativeBuildInputs = [ cmake-compat pkgs.linux-pam pkgs.gnutls.dev ];
    };
  in
  {
    packages.${system} = {
      lockfile = buildrootPackages.packageLockFile;
      default = buildrootPackages.buildroot;
      inherit stm32cubeprog;
    };

    devShells = {
      "${system}" = {
        default = pkgs.mkShell {
          name = "dbl-buildroot";

          # Nix's GCC wrapper injects -Werror=format-security by default
          # Buildroot's host-gcc-initial (GCC 13) doesn't satisfy this in its own
          # libcpp, so the host compiler build fails. Disable for this shell
          hardeningDisable = [ "format" ];

          packages = with pkgs; [
            # Core build toolchain
            gcc
            binutils
            gnumake
            cmake-compat

            # Scripting / config
            # Note: Buildroot builds its own host Python
            # Nix's gcc-wrapper injects include paths from all devShell packages via
            # NIX_CFLAGS_COMPILE; having python3 here causes the 3.13 headers to
            # bleed into the host-python-markupsafe C extension build, producing a
            # cpython-313 SOABI tag that mismatches the running Python 3.12
            perl
            bison
            flex

            # Buildroot host dependencies (mirrors buildroot.nix FHS env)
            bc
            cpio
            file
            rsync
            unzip
            wget
            which
            util-linux
            libxcrypt
            pkg-config
            linux-pam  # host-libcap pam_cap module needs security/pam_modules.h
            gnutls.dev # u-boot mkeficapsule needs gnutls/gnutls.h

            # ncurses for menuconfig / linux configurators
            ncurses
            ncurses.dev

            # Compression
            gzip
            lzop
            lz4

            # Device tree tooling
            dtc

            # Source management
            git
            patch
            diffutils
            findutils
            gnugrep
            gnused
            gawk

            # Optional: openssl for signing/secure-boot tooling
            openssl

            # STM32CubeProgrammer CLI for USB DFU flashing of STM32MP1
            # Requires manual download due to license; see pkgs/stm32cubeprog.nix
            stm32cubeprog

            # dfu-util for writing rootfs.ubi to SPI-NAND via U-Boot DFU
            dfu-util
          ];

          # stdenv.cc.cc.lib provides libstdc++.so.6 / libgcc_s.so.1
          # Buildroot compiles patchelf with RUNPATH=$ORIGIN/../lib; that directory
          # doesn't hold these Nix-store libs, so we expose them via LD_LIBRARY_PATH.
          # libidn2 + libunistring: host-cmake links host-OS libcurl which pulls in
          # /usr/lib/libidn2.so / libunistring.so; both must be resolvable at
          # link time and runtime.
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            pkgs.stdenv.cc.cc.lib
            pkgs.libidn2
            pkgs.libunistring
          ];

          shellHook = ''
            echo "DBL buildroot development shell"
            echo "  Buildroot: 2025.02 LTS"
            echo "  Target:    STM32MP135D (MYD-YF135-256N-256D)"
            echo ""
            echo "Common commands:"
            echo "  make myd_yf135_defconfig"
            echo "  make menuconfig"
            echo ""
            echo "Nix hermetic build:"
            echo "  make nix-lock         # first time / after pkg version changes"
            echo "  nix build             # build image"
            export BUILDROOT_SRC="${buildroot}"
          '';
        };

        lint = pkgs.mkShell {
          name = "dbl-lint";
          packages = with pkgs; [ pre-commit ];
        };

        pre-commit = pkgs.mkShell {
          name = "dbl-pre-commit";
          packages = with pkgs; [ pre-commit git reuse ];

          shellHook = ''
            export PRE_COMMIT_HOME="$PWD/.cache/pre-commit"
            echo "DBL pre-commit shell"
            echo "  Cache: $PRE_COMMIT_HOME"
          '';
        };
      };
    };
  };
}
