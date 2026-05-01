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
  # Uses the same AWK-based merge as gen-debug-defconfig.sh.
  configFragment ? null,
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

  # AWK-based defconfig fragment merger (same logic as gen-debug-defconfig.sh).
  # When configFragment is set, we merge it over the base defconfig before
  # applying. This lets downstream repos extend the base image with
  # project-specific packages/config.
  mergeConfigFragment = base: fragment: output: ''
    awk '
    function cfg_key(line, m) {
      if (match(line, /^([A-Z0-9_]+)=/, m)) return m[1]
      if (match(line, /^# ([A-Z0-9_]+) is not set$/, m)) return m[1]
      return ""
    }
    FNR == NR {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^[[:space:]]*#/) next
      k = cfg_key($0)
      if (k != "") { overrides[k] = $0; order[++n] = k }
      next
    }
    {
      k = cfg_key($0)
      if (k != "" && (k in overrides)) {
        if (!(k in emitted)) { print overrides[k]; emitted[k] = 1 }
        next
      }
      print $0
    }
    END {
      for (i = 1; i <= n; i++) {
        k = order[i]
        if (!(k in emitted)) print overrides[k]
      }
    }
    ' ${fragment} ${base} > ${output}
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

    configurePhase = ''
      mkdir -p output/images
    ''
    + pkgs.lib.optionalString (configFragment != null) (
      mergeConfigFragment baseDefconfig configFragment "merged_defconfig"
      + ''
        ${makeFHSEnv}/bin/make-with-fhs-env BR2_EXTERNAL=${brExternalValue} BR2_DEFCONFIG=merged_defconfig defconfig
      ''
    )
    + pkgs.lib.optionalString (configFragment == null) ''
      ${makeFHSEnv}/bin/make-with-fhs-env BR2_EXTERNAL=${brExternalValue} ${defconfigName}
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
    '';

    installPhase = ''
      mkdir -p $out/images $sdk

      cp -r output/images/. $out/images/
      rm -f $out/images/*_sdk-buildroot.tar.gz
      sed 's|../../output/latest/images/|./|g' ${buildExternalSrc}/${flashLayoutPath} > $out/images/flashlayout.tsv

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
