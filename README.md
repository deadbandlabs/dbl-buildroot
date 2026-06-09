# dbl-buildroot

Buildroot external tree for STM32MP135D, targeting the **MyIR MYD-YF135-256N-256D** SOM.

## Overview

This external tree supports projects shipping on the STM32MP13, specifically the MYD-YF135 SOM, that want to stay close to upstream Buildroot, Linux, and firmware, so that security fixes land quickly and version bumps remain practical instead of waiting on vendor updates.

Highlights:

- Upstream tags for Buildroot, Linux, TF-A, OP-TEE, and U-Boot
- Board changes isolated in `board/` and `configs/`
- Small drift, easier release-to-release incremental upgrades
- A/B firmware and root filesystem updates with factory fallback, via RAUC and a TF-A BL2 fallback walk (no out-of-tree patches)
- Nix and flakes for reproducible host tooling, plus hermetic full-image and SDK builds

Hardware and driver functionality is limited to what is supported in upstream Linux, U-Boot, TF-A, and OP-TEE.

## Build approach

Two build paths share one configuration:

- A `make` workflow that runs in a Nix development shell for fast, incremental local iteration. This is the usual Buildroot experience, with per-target rebuilds and reusable `dl/` and `ccache` caches.
- A hermetic `nix build` that produces the full image and a relocatable cross-compiler SDK in a single derivation. This path is built on [velentr/buildroot.nix](https://github.com/velentr/buildroot.nix), and is cached using [Cachix](https://deadbandlabs.cachix.org).

Both paths apply the same defconfig and fragments, so a local `make` build and a `nix build` produce the same configuration. See the [Setup](https://github.com/deadbandlabs/dbl-buildroot/wiki/1.-Setup) wiki page for the comparison and prerequisites.

## Documentation

Full documentation lives in the [wiki](https://github.com/deadbandlabs/dbl-buildroot/wiki):

- [Setup](https://github.com/deadbandlabs/dbl-buildroot/wiki/1.-Setup): Prerequisites, Nix environment, build commands, incremental targets, hermetic builds
- [Hardware](https://github.com/deadbandlabs/dbl-buildroot/wiki/2.-Hardware): SoC, RAM, flash, console, memory map, SPI-NAND partition layout
- [Boot Chain](https://github.com/deadbandlabs/dbl-buildroot/wiki/3.-Boot-Chain): Boot sequence, device tree, NAND parameters with OTP fuse details
- [Flashing](https://github.com/deadbandlabs/dbl-buildroot/wiki/4.-Flashing): DFU flashing via STM32CubeProgrammer, BOOT pin settings
- [Build Variants](https://github.com/deadbandlabs/dbl-buildroot/wiki/5.-Build-Variants): Release and debug build variants, host toolchain sharing, configuration fragments
- [CI](https://github.com/deadbandlabs/dbl-buildroot/wiki/6.-CI): GitHub Actions workflows, running locally with act, caching
- [Parent Integration](https://github.com/deadbandlabs/dbl-buildroot/wiki/7.-Parent-Integration): Submodule usage, mkProject parameters, updating, drift detection
- [Differences](https://github.com/deadbandlabs/dbl-buildroot/wiki/8.-Differences): Comparison with vendor and community configurations

## Quick start

Incremental `make` builds in the Nix development shell:

```bash
make                      # release image (default)
make debug                # debug image (debug symbols + verbose firmware)
make MODE=debug <target>  # run a specific Buildroot target in debug mode
```

Hermetic full builds via buildroot.nix:

```bash
nix build                 # release image
nix build .#sdk           # relocatable cross-compiler SDK
```

See the [Setup](https://github.com/deadbandlabs/dbl-buildroot/wiki/1.-Setup) wiki page for prerequisites and detailed build instructions.

## Use as a submodule

To use this repo as a submodule of a superproject, create a new `BR2_EXTERNAL` tree for project-specific packages, overlays, and defconfigs:

```text
superproject/
    buildroot/                  # upstream Buildroot source
    externals/
        dbl-buildroot/          # this repo as submodule
        project-external/       # your project-specific BR2_EXTERNAL
```

```bash
BR2_EXTERNAL="$PWD/externals/dbl-buildroot:$PWD/externals/project-external"
```

Super-project defconfigs can reference this board layer via `$(BR2_EXTERNAL_MYD_YF135_PATH)`. See the [Parent Integration](https://github.com/deadbandlabs/dbl-buildroot/wiki/7.-Parent-Integration) wiki page for full details including `init.sh`, drift detection, and `mkProject` parameters.

## Contributing

- [CONTRIBUTING.md](CONTRIBUTING.md): patch guidelines, pre-commit setup, commit style
- [SECURITY.md](SECURITY.md): vulnerability reporting
