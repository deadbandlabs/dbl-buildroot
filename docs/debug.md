# Debug Build Variants

This repo provides two build variants: `release` (default) and `debug`.

## Quick start

```bash
make                # release image (default)
MODE=debug make     # debug image (debug symbols, verbose firmware)
```

`make release` and `make debug` are aliases for the above, however note incremental targets
may require MODE=debug set to build the correct target.

## Host Toolchain

To prevent rebuilding toolchain, ccache and host build path is shared between release and debug:

```bash
# shared compiler cache for release+debug (default path shown)
CCACHE_DIR=$PWD/output/ccache MODE=debug make

# default: debug reuses release host tools from debug output
MODE=debug make

# opt-out: keep separate debug host tree
SHARE_HOST_FOR_DEBUG=0 MODE=debug make
```

Host sharing is enabled by default. If release host tools are missing,
debug build auto-runs `make MODE=release host-toolchain` first.
It then links `output/debug/host` and `output/debug/build/host-*`
to release equivalents so host package stamps are reused.
See `support/build/share-host-artifacts.sh`.

Manual prebuild (optional):

```bash
make MODE=release host-toolchain
```

## Debug Configuration Fragments

| File | Role |
|------|------|
| `configs/myd_yf135_debug.fragment` | Defconfig debug override fragment |
| `board/myd-yf135/linux-debug.fragment` | Kernel debug Kconfig fragment |
| `board/myd-yf135/uboot-debug.fragment` | U-Boot debug Kconfig fragment |
| `output/<mode>/myd_yf135_debug_defconfig` | Generated debug defconfig (do not edit) |

# Changes for Debug

## Kernel config

Layered model:

- release: `board/myd-yf135/linux.config`
- debug: release config + `board/myd-yf135/linux-debug.fragment`

Super-project externals can inherit this and add project-specific fragments on top.

## Firmware verbosity

| Component | release | debug |
|-----------|---------|-------|
| TF-A | `LOG_LEVEL=0`, no `STM32MP_SDMMC` | `LOG_LEVEL=10`, `STM32MP_SDMMC=1` |
| OP-TEE | `CFG_TEE_CORE_LOG_LEVEL=0`, no `CFG_STM32_EARLY_CONSOLE_UART` | `CFG_TEE_CORE_LOG_LEVEL=0`, `CFG_STM32_EARLY_CONSOLE_UART=4` |
| U-Boot | `uboot.config` (`CONFIG_BOOTDELAY=-2`, no stop prompt) | `uboot.config` + `uboot-debug.fragment` (`CONFIG_BOOTDELAY=3`) |

U-Boot console silence uses the `silent` env var. This repo reduces noise in release
but does not force a fully silent console by default.

## Regenerating the debug defconfig

`make debug` performs the merge inline as part of `_APPLY_DEFCONFIG` (does not depend on a pre-generated `myd_yf135_debug_defconfig`).

`make regen-debug-defconfig` is provided for static inspection: it writes the merged defconfig to `$(O)/myd_yf135_debug_defconfig`
to show exactly what the build will apply, including any parent overlays.

```bash
MODE=debug make regen-debug-defconfig
less output/debug/myd_yf135_debug_defconfig
```

## Defconfig merger

All variant merges go through `support/build/merge-defconfig.py`:

```
merge-defconfig.py <output> <base> [delta1 delta2 ...]
```

Each delta overrides keys from prior inputs, *except* for keys matching
`*_FRAGMENT_FILES` (e.g. `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES`,
`BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES`), which are appended space-separated.

Both the Makefile and the nix build (`nix/build.nix`) call this script, so
shell-mode and nix builds produce identical merged defconfigs.

## Super-project integration

Pass `BR2_EXTERNAL_EXTRA` to append a second external tree:

```bash
make BR2_EXTERNAL_EXTRA=/path/to/project-external release
make BR2_EXTERNAL_EXTRA=/path/to/project-external debug
```

Or configure manually:

```bash
make BR2_EXTERNAL_EXTRA=/path/to/project-external myd_yf135_defconfig
make BR2_EXTERNAL_EXTRA=/path/to/project-external
```

Super-project variants can reference this board layer via
`$(BR2_EXTERNAL_MYD_YF135_PATH)`.

### Layered defconfig stacking from a parent overlay

When consumed via `support/parent.mk`, a parent repo can supply two
fragments that stack in this order:

```
base release defconfig
  + parent CONFIG_FRAGMENT        (DBL_BR_FRAGMENT)
  + base debug fragment           (configs/myd_yf135_debug.fragment)
  + parent CONFIG_FRAGMENT_DEBUG  (DBL_BR_FRAGMENT_DEBUG, optional)
```

Release builds stop at the parent's `CONFIG_FRAGMENT`. Debug builds extend
with the base debug fragment and an optional parent debug fragment. Each
later layer takes priority on conflicting keys; `*_FRAGMENT_FILES` keys accumulate.

Parent `Makefile`:

```make
DBL_BR_FRAGMENT       := overlay/syncro-os.fragment
DBL_BR_FRAGMENT_DEBUG := overlay/syncro-os-debug.fragment   # optional
include modules/dbl-buildroot/support/parent.mk
```

Parent `flake.nix` (when also building via nix):

```nix
(import ./modules/dbl-buildroot/lib.nix).mkProject {
  name = "syncro-os";
  board = "myd-yf135";
  extraExternalSrcs = [ ./overlay ];
  configFragment      = ./overlay/syncro-os.fragment;
  configFragmentDebug = ./overlay/syncro-os-debug.fragment;   # optional
}
```
