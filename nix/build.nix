# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Single-stage hermetic Buildroot build, following the buildroot-nix approach.
# Source is filtered to only dirs that affect the build output, so changes to
# docs/, .github/, nix/, support/, etc. do not trigger a rebuild.
#
# Downstream repos call dblBuildroot.lib.mkProject (see flake.nix)
# which wires up pkgs/cmake-compat/etc. and invokes this module.
# Direct callers (the submodule's own outputs) pass the full arg set.
{
  pkgs,
  buildroot-nix,
  buildroot,
  self,
  cmake-compat,
  # Derivation name + defconfig + flashlayout. Defaults match the in-tree
  # MYD-YF135 board so the submodule can dogfood mkProject; downstream repos
  # override via lib.mkProject args.
  projectName ? "myd-yf135",
  defconfigName ? "myd_yf135_defconfig",
  flashLayoutPath ? "board/myd-yf135/flashlayout.tsv",
  # Additional BR2_EXTERNAL source trees (e.g. downstream overlay/).
  # Each entry is a path containing external.desc, external.mk, Config.in, etc.
  extraExternalSrcs ? [ ],
  # Optional defconfig fragment to merge over the base defconfig.
  # Merged via support/build/merge-defconfig.py.
  configFragment ? null,
  # Note: The nix flake currently only builds the release variant today, so CONFIG_FRAGMENT_DEBUG is unused
  # Wired through lib.nix so a future debug derivation can consume it
  configFragmentDebug ? null,
  # Optional programmer (USB DFU loader TF-A + FIP) defconfig fragment.
  # Bundled into $out/images as tf-a-programmer.stm32 / fip-programmer.bin.
  programmerFragment ? null,
}:
let
  ## Lockfile generation (via upstream buildroot.nix)

  buildrootPackages = buildroot-nix.lib.mkBuildroot {
    name = projectName;
    inherit pkgs;
    src = buildroot;
    externalSrc = buildExternalSrc;
    defconfig = defconfigName;
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

  # Combined BR2_EXTERNAL value: base external + any downstream overlays.
  # Buildroot uses colon-separated list for multiple external trees.
  allExternalSrcs = [ buildExternalSrc ] ++ extraExternalSrcs;
  brExternalValue = pkgs.lib.concatStringsSep ":" allExternalSrcs;

  # bundle-images.sh imported as its own store path to prevent including all support/ scripts
  bundleImagesScript = self + "/support/build/bundle-images.sh";

  # Shared defconfig merger also used by Makefile build
  mergeDefconfigScript = self + "/support/build/merge-defconfig.py";

  # Returns a shell snippet that merges `base + deltas` into `output`
  # `deltas` is a list of store paths; null entries are filtered out
  mergeFragments =
    output: base: deltas:
    let
      nonEmpty = builtins.filter (d: d != null) deltas;
      argv = pkgs.lib.concatMapStringsSep " " (d: toString d) nonEmpty;
    in
    ''
      ${pkgs.python3}/bin/python3 ${mergeDefconfigScript} ${output} ${base} ${argv}
    '';

  ## Build

  # defconfig name depends on whether a config fragment is injected.
  # When no fragment: use the built-in defconfig target directly.
  # When fragment: generate merged defconfig and apply it.
  baseDefconfig = self + "/configs/${defconfigName}";

  build = pkgs.stdenv.mkDerivation {
    name = projectName;
    src = buildroot;
    outputs = [
      "out"
      "sdk"
    ];

    patchPhase = ''
      sed -i 's%--disable-makeinstall-chown%--disable-makeinstall-chown --disable-makeinstall-setuid%' \
          package/util-linux/util-linux.mk
    '';

    configurePhase =
      let
        releaseDeltas = pkgs.lib.optional (configFragment != null) configFragment;
      in
      ''
        mkdir -p output/images
      ''
      + (
        if releaseDeltas != [ ] then
          mergeFragments "merged_defconfig" baseDefconfig releaseDeltas
          + ''
            ${makeFHSEnv}/bin/make-with-fhs-env BR2_EXTERNAL=${brExternalValue} BR2_DEFCONFIG=merged_defconfig defconfig
          ''
        else
          ''
            ${makeFHSEnv}/bin/make-with-fhs-env BR2_EXTERNAL=${brExternalValue} ${defconfigName}
          ''
      );

    buildPhase = ''
      export BR2_DL_DIR="$PWD/dl"
      mkdir -p "$BR2_DL_DIR"
      for lockedInput in ${lockedSources}/*; do
        ln -s $lockedInput "$BR2_DL_DIR/$(basename $lockedInput)"
      done

      ${makeFHSEnv}/bin/make-with-fhs-env \
        BR2_JLEVEL=$NIX_BUILD_CORES \
        BR2_EXTERNAL=${brExternalValue}
      ${makeFHSEnv}/bin/make-with-fhs-env \
        BR2_JLEVEL=$NIX_BUILD_CORES \
        BR2_EXTERNAL=${brExternalValue} \
        sdk
    ''
    + pkgs.lib.optionalString (programmerFragment != null) (
      # Programmer merge chain: base + parent CONFIG_FRAGMENT + programmer fragment
      let
        progFragmentPath = buildExternalSrc + "/${programmerFragment}";
        deltas = (pkgs.lib.optional (configFragment != null) configFragment) ++ [ progFragmentPath ];
      in
      mergeFragments "programmer_defconfig" baseDefconfig deltas
      + ''
        ${makeFHSEnv}/bin/make-with-fhs-env \
          O=$PWD/output-programmer \
          BR2_EXTERNAL=${brExternalValue} \
          BR2_DEFCONFIG=$PWD/programmer_defconfig defconfig
        ${makeFHSEnv}/bin/make-with-fhs-env \
          O=$PWD/output-programmer \
          BR2_JLEVEL=$NIX_BUILD_CORES \
          BR2_EXTERNAL=${brExternalValue} \
          arm-trusted-firmware
      ''
    );

    installPhase = ''
      mkdir -p $out/images $sdk

      cp -r output/images/. $out/images/
      rm -f $out/images/*_sdk-buildroot.tar.gz
    ''
    + (
      if programmerFragment != null then
        # When programmer is used, run the bundleImagesScript to produce a flashlayout.tsv
        # This replaces a previous sed inplace replacement to unify with Makefile builds
        ''
          ${pkgs.bash}/bin/bash ${bundleImagesScript} \
            $out/images \
            $PWD/output-programmer/images \
            ${buildExternalSrc}/${flashLayoutPath}
        ''
      else
        ''
          sed 's|../../output/latest/images/|./|g' ${buildExternalSrc}/${flashLayoutPath} > $out/images/flashlayout.tsv
        ''
    )
    + ''

      cp output/images/*_sdk-buildroot.tar.gz $sdk/sdk.tar.gz
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
