# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Single-stage hermetic Buildroot build, following the buildroot-nix approach.
# Source is filtered to only dirs that affect the build output, so changes to
# docs/, .github/, nix/, support/, etc. do not trigger a rebuild.
{
  pkgs,
  buildroot-nix,
  buildroot,
  self,
  cmake-compat,
}:
let
  ## Lockfile generation (via upstream buildroot.nix)

  buildrootPackages = buildroot-nix.lib.mkBuildroot {
    name = "myd-yf135";
    inherit pkgs;
    src = buildroot;
    externalSrc = buildExternalSrc;
    defconfig = "myd_yf135_defconfig";
    lockfile = self + "/buildroot.lock";
    nativeBuildInputs = [
      cmake-compat
      pkgs.git
      pkgs.linux-pam
      pkgs.gnutls
      pkgs.gnutls.dev
    ];
  };

  ## FHS environment

  makeFHSEnv = pkgs.buildFHSEnv {
    name = "make-with-fhs-env";
    targetPkgs =
      pkgs: with pkgs; [
        bc
        cpio
        file
        libxcrypt
        perl
        rsync
        unzip
        util-linux
        wget
        which
        cmake-compat
        git
        linux-pam
        gnutls # libgnutls.so for linking (u-boot mkeficapsule)
        gnutls.dev # gnutls/gnutls.h headers
      ];
    runScript = "make";
  };

  lockedSources = buildrootPackages.packageInputs;

  # Filtered external source to only dirs that affect the Buildroot output
  # Excludes docs/, .github/, nix/, support/, README.md, etc. so that changes
  # to those files do not invalidate the build cache.
  buildExternalSrc = builtins.path {
    name = "external";
    path = self;
    filter =
      path: _type:
      let
        base = toString self;
        relPath = pkgs.lib.removePrefix (base + "/") (toString path);
        topLevel = builtins.head (builtins.split "/" relPath);
      in
      topLevel == "Config.in"
      || topLevel == "external.desc"
      || topLevel == "external.mk"
      || topLevel == "configs"
      || topLevel == "package"
      || topLevel == "board";
  };

  ## Build

  build = pkgs.stdenv.mkDerivation {
    name = "myd-yf135";
    src = buildroot;
    outputs = [
      "out"
      "sdk"
    ];

    patchPhase = ''
      sed -i 's%--disable-makeinstall-chown%--disable-makeinstall-chown --disable-makeinstall-setuid%' \
          package/util-linux/util-linux.mk
    '';

    configurePhase = ''
      ${makeFHSEnv}/bin/make-with-fhs-env BR2_EXTERNAL=${buildExternalSrc} myd_yf135_defconfig
    '';

    buildPhase = ''
      export BR2_DL_DIR="$PWD/dl"
      mkdir -p "$BR2_DL_DIR"
      for lockedInput in ${lockedSources}/*; do
        ln -s $lockedInput "$BR2_DL_DIR/$(basename $lockedInput)"
      done

      ${makeFHSEnv}/bin/make-with-fhs-env \
        BR2_JLEVEL=$NIX_BUILD_CORES \
        BR2_EXTERNAL=${buildExternalSrc}
      ${makeFHSEnv}/bin/make-with-fhs-env \
        BR2_JLEVEL=$NIX_BUILD_CORES \
        BR2_EXTERNAL=${buildExternalSrc} \
        sdk
    '';

    installPhase = ''
      mkdir -p $out $sdk

      cp -r output/images $out/
      sed 's|../../output/latest/images/|./|g' ${buildExternalSrc}/board/myd-yf135/flashlayout.tsv > $out/images/flashlayout.tsv

      cp -r output/host/* $sdk/
      sh $sdk/relocate-sdk.sh
    '';

    hardeningDisable = [ "format" ];
    dontFixup = true;
  };
in
{
  lockfile = buildrootPackages.packageLockFile;
  default = build;
  sdk = build.sdk;
}
