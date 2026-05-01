# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Development shell configurations.
{
  pkgs,
  buildroot,
  cmake-compat,
  stm32cubeprog,
  # Downstream-injected packages added to the default shell
  extraPackages ? [ ],
}:
let
  brShellHook = ''
    export BUILDROOT_SRC="${buildroot}"
    # Nix wget has no system CA bundle; point it at the Nix-provided one
    export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    export GIT_SSL_CAINFO="$SSL_CERT_FILE"
    export CURL_CA_BUNDLE="$SSL_CERT_FILE"
  '';

  # Packages required to run Buildroot builds
  brShellPackages = with pkgs; [
    # Core build toolchain
    gcc
    binutils
    gnumake
    cmake-compat

    # Scripting / config
    # Note: Buildroot builds its own host Python
    #   Nix's gcc-wrapper injects include paths from all devShell packages via
    #   NIX_CFLAGS_COMPILE; having python3 here causes the 3.13 headers to
    #   bleed into the host-python-markupsafe C extension build, producing a
    #   cpython-313 SOABI tag that mismatches the running Python 3.12
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
    linux-pam # host-libcap pam_cap module needs security/pam_modules.h
    gnutls
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

    # CA certificates for wget/curl/git HTTPS (Nix wget has no system bundle)
    cacert

    # Source management
    git
    patch
    diffutils
    findutils
    gnugrep
    gnused
    gawk

    # Signing/secure-boot tooling
    openssl

    # dfu-util for writing rootfs.ubi to SPI-NAND via U-Boot DFU without STM32Cube
    dfu-util
  ];

  # stdenv.cc.cc.lib provides libstdc++.so.6 / libgcc_s.so.1
  # Buildroot compiles patchelf with RUNPATH=$ORIGIN/../lib; that directory
  # doesn't hold these Nix-store libs, so we expose them via LD_LIBRARY_PATH.
  # libidn2 + libunistring: host-cmake links host-OS libcurl which pulls in
  # /usr/lib/libidn2.so / libunistring.so; both must be resolvable at
  # link time and runtime.
  brShellLibPath = pkgs.lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    pkgs.libidn2
    pkgs.libunistring
  ];

  # hardeningDisable: Nix's GCC wrapper injects -Werror=format-security by
  #   default; Buildroot's host-gcc-initial (GCC 13) doesn't satisfy this in
  #   its own libcpp, so the host compiler build fails.
  brShellArgs = {
    hardeningDisable = [ "format" ];
    packages = brShellPackages;
    LD_LIBRARY_PATH = brShellLibPath;
    shellHook = brShellHook;
  };
in
{
  default = pkgs.mkShell (
    brShellArgs
    // {
      name = "dbl-buildroot";
      packages =
        brShellArgs.packages
        ++ [
          # STM32CubeProgrammer CLI for USB DFU flashing of STM32MP1
          # Requires manual download due to license; see pkgs/stm32cubeprog.nix
          stm32cubeprog

          # act: run GitHub Actions workflows locally (via podman rootless)
          pkgs.act
          pkgs.podman

          # cachix: push cached nix build results (pulls are automatic)
          pkgs.cachix
        ]
        ++ extraPackages;
      shellHook = brShellArgs.shellHook + ''
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
        echo "  nix build             # build image (both toolchain + target)"
        echo "  nix build .#toolchain # build toolchain only"
      '';
    }
  );

  ci = pkgs.mkShell (brShellArgs // { name = "dbl-buildroot-ci"; });

  pre-commit = pkgs.mkShell {
    name = "dbl-pre-commit";
    packages = with pkgs; [
      pre-commit
      git
      reuse
      shellcheck
      shfmt
      yamllint
      nixfmt-rfc-style
      perl
      gnutar
      mdformat
      commitizen
    ];

    shellHook = ''
      export PRE_COMMIT_HOME="$PWD/.cache/pre-commit"
      echo "DBL pre-commit shell"
      echo "  Cache: $PRE_COMMIT_HOME"
    '';
  };
}
