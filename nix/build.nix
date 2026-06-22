# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Two-stage hermetic Buildroot build, following the buildroot-nix approach:
#  * cached toolchain SDK (stage 1) consumed as an external toolchain
#  * image build (stage 2)
# Source is filtered to only dirs that affect the build output
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
  # Toolchain SDK derivation name
  # Parents that reuse this toolchain with their own projectName still substitute the same
  # store path for the CI-built SDK from cachix
  toolchainName ? "myd-yf135-toolchain",
  # Toolchain defconfig, its lockfile, and the external-toolchain description
  # Default to the submodule's files so parents reuse the cached SDK
  # override all (with toolchainName) to build a custom toolchain.
  toolchainDefconfig ? (self + "/configs/myd_yf135_toolchain_defconfig"),
  toolchainLockfile ? (self + "/toolchain.lock"),
  toolchainFragment ? (self + "/configs/myd_yf135_external_toolchain.fragment"),
  # Additional BR2_EXTERNAL source trees (e.g. downstream overlay/).
  # Each entry is a path containing external.desc, external.mk, Config.in, etc.
  extraExternalSrcs ? [ ],
  # Extra rootfs overlay dirs; `sdk` is the image's toolchain SDK
  # (See lib.nix's extraRootfsOverlays)
  extraRootfsOverlays ? ({ sdk, pkgs }: [ ]),
  # Optional defconfig fragment to merge over the base defconfig.
  # Merged via support/build/merge-defconfig.py.
  configFragment ? null,
  certEnv ? "",
  # Optional programmer (USB DFU loader TF-A + FIP) defconfig fragment.
  # Bundled into $out/images as tf-a-programmer.stm32 / fip-programmer.bin.
  programmerFragment ? null,
  # Lockfile path used for source prefetch + lock generation
  # Parent repos override this via lib.nix's `lockfile` param
  # (paths resolve relative to the parent repo root)
  lockfilePath ? (self + "/buildroot.lock"),
}:
let
  ## FHS environment

  makeFHSEnv = pkgs.buildFHSEnv {
    name = "make-with-fhs-env";
    targetPkgs =
      pkgs: with pkgs; [
        bc
        cacert
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
    profile = certEnv;
    runScript = "make";
  };

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

  # Strips non-mirror cargo2 URLs from a generated lock (see script header).
  fixCargo2Script = self + "/support/build/fix-cargo2-lockfile.py";

  # Returns a shell snippet that merges `base + deltas` into `output`
  # `deltas` is a list of store paths; null entries are filtered out
  mergeFragments =
    output: base: deltas:
    let
      nonEmpty = builtins.filter (d: d != null) deltas;
      argv = pkgs.lib.concatMapStringsSep " " (d: "${d}") nonEmpty;
    in
    ''
      ${pkgs.python3}/bin/python3 ${mergeDefconfigScript} ${output} ${base} ${argv}
    '';

  ## Toolchain SDK (stage 1)
  # Inputs exclude board/, package/, overlays and the image defconfig
  toolchainPackages = buildroot-nix.lib.mkBuildroot {
    name = toolchainName;
    inherit pkgs;
    src = buildroot;
    defconfig = "defconfig BR2_DEFCONFIG=${toolchainDefconfig}";
    lockfile = toolchainLockfile;
    nativeBuildInputs = [
      cmake-compat
      pkgs.git
    ];
  };

  toolchainSdk = pkgs.stdenv.mkDerivation {
    name = "${toolchainName}-sdk";
    src = buildroot;
    configurePhase = ''
      ${makeFHSEnv}/bin/make-with-fhs-env BR2_DEFCONFIG=${toolchainDefconfig} defconfig
    '';
    buildPhase = ''
      export BR2_DL_DIR="$PWD/dl"
      mkdir -p "$BR2_DL_DIR"
      for lockedInput in ${toolchainPackages.packageInputs}/*; do
        ln -s $lockedInput "$BR2_DL_DIR/$(basename $lockedInput)"
      done
      ${makeFHSEnv}/bin/make-with-fhs-env BR2_JLEVEL=$NIX_BUILD_CORES sdk
    '';
    installPhase = ''
      mkdir -p $out
      tar -xf output/images/*_sdk-buildroot.tar.gz -C $out --strip-components=1
      ${pkgs.bash}/bin/bash $out/relocate-sdk.sh
    '';
    hardeningDisable = [ "format" ];
    dontFixup = true;
  };

  # Append the nix-specific SDK store path to the committed external-toolchain fragment
  externalToolchainFragment = pkgs.runCommand "external-toolchain.fragment" { } ''
    cp ${toolchainFragment} $out
    chmod +w $out
    echo 'BR2_TOOLCHAIN_EXTERNAL_PATH="${toolchainSdk}"' >> $out
  '';

  ## Build (stage 2)

  baseDefconfig = self + "/configs/${defconfigName}";

  # defconfig passed to mkBuildroot for lock generation, in mkBuildroot's
  # string form: `defconfig BR2_DEFCONFIG=<path>`
  # Uses toolchainFragment to avoid BR2_TOOLCHAIN_EXTERNAL_PATH forcing an SDK build to derive
  lockDefconfig = "defconfig BR2_DEFCONFIG=${
    pkgs.runCommand "lock-defconfig" { } (
      mergeFragments "$out" baseDefconfig [
        configFragment
        toolchainFragment
      ]
    )
  }";

  ## Lockfile generation (via upstream buildroot.nix)
  # Feed lock generation the same externals + defconfig as the real build so
  # overlay-selected packages are enumerated and locked in the nix cache.
  buildrootPackages = buildroot-nix.lib.mkBuildroot {
    name = projectName;
    inherit pkgs;
    src = buildroot;
    externalSrc = brExternalValue;
    defconfig = lockDefconfig;
    lockfile = lockfilePath;
    nativeBuildInputs = [
      cmake-compat
      pkgs.git
      pkgs.linux-pam
      pkgs.gnutls
      pkgs.gnutls.dev
    ];
  };

  lockedSources = buildrootPackages.packageInputs;

  # Resolve the extra overlays and express them as a defconfig fragment whose
  # BR2_ROOTFS_OVERLAY value accumulates onto the base/consumer rootfsOverlays
  # so no in-place edit of the merged defconfig is needed
  # null when there are none (NB: see merge-defconfig.py)
  rootfsOverlays = extraRootfsOverlays { sdk = toolchainSdk; inherit pkgs; };
  rootfsOverlayFragment =
    if rootfsOverlays == [ ] then
      null
    else
      pkgs.writeText "rootfs-overlays.fragment" ''
        BR2_ROOTFS_OVERLAY="${pkgs.lib.concatMapStringsSep " " toString rootfsOverlays}"
      '';

  # Process the generated lock to drop non-mirror cargo2 URLs during derivation
  lockfile = pkgs.runCommand "${projectName}-buildroot.lock" { } ''
    cp ${buildrootPackages.packageLockFile} $out
    chmod +w $out
    ${pkgs.python3}/bin/python3 ${fixCargo2Script} $out
  '';

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

    # mergeFragments drops null deltas.
    configurePhase =
      mergeFragments "merged_defconfig" baseDefconfig [
        configFragment
        externalToolchainFragment
        rootfsOverlayFragment
      ]
      + ''
        mkdir -p output/images
        ${makeFHSEnv}/bin/make-with-fhs-env BR2_EXTERNAL=${brExternalValue} BR2_DEFCONFIG=merged_defconfig defconfig
      '';

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
        deltas = (pkgs.lib.optional (configFragment != null) configFragment) ++ [
          progFragmentPath
          externalToolchainFragment
        ];
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
  inherit lockfile;
  default = build;
  sdk = build.sdk;
  toolchain = toolchainSdk;
  toolchain-lockfile = toolchainPackages.packageLockFile;
}
