# dbl-buildroot

Buildroot external tree for STM32MP135D, targeting the **MyIR MYD-YF135-256N-256D** SOM.

# Overview

## Why this external tree exists

This external tree is for projects wanting to ship a STM32MP13 project (specifically using
the MYD-YF135 SOM) without getting stuck on stale vendor branches.

The main goal of this repo is to stay close to upstream Buildroot/kernel/firmware so security
fixes land quickly and version bumps stay practical instead of depending on vendor updates.

Highlights of this project:

- upstream tags for Buildroot/Linux/TF-A/OP-TEE/U-Boot
- board changes isolated in `board/` and `configs/`
- small drift, easier release-to-release incremental upgrades
- Nix + flakes for reproducible host tooling across developer machines/CI

To achieve this, hardware and driver functionality is limited to what is supported in
upstream Linux, U-Boot, TF-A and OP-TEE. If this matches your priorities, start with Setup and the Nix section below; the later sections cover board specifics and
implementation details.

## Navigation

If you are evaluating whether to use or fork this repo, review these resources:

- [Why this external tree exists](#why-this-external-tree-exists)
- [Setup](#setup)
- [Differences from vendor and community configs](#differences-from-vendor-and-community-configs)

If you need board bring-up details, jump to:

- [Hardware](#hardware)
- [Software stack](#software-stack)
- [Boot chain](#boot-chain)
- [Device tree](#device-tree)
- [NAND parameters and OTP](#nand-parameters-and-otp)
- [Flashing](#flashing)
- [Serial console](#serial-console)

For info on contributing:

- [CONTRIBUTING.md](CONTRIBUTING.md): patch guidelines, pre-commit setup, commit style
- [SECURITY.md](SECURITY.md): vulnerability reporting
- [docs/ci.md](docs/ci.md): GitHub Actions workflows and running CI locally with `act`

## Reproducible build environment (Nix)

Buildroot target output can be reproducible, but requires careful setup host-to-host.
Nix + flakes pins host tooling across machines, reducing distro/package mismatch work.
Buildroot flow stays normal; Nix standardizes the environment around it. This is based
on the work by https://github.com/velentr/buildroot.nix.

## Use as a submodule

To use this repo as a submodule of a superproject, create a new `BR2_EXTERNAL` tree for
project-specific packages, overlays, and defconfigs:

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

Super-project defconfigs can reference this board layer via
`$(BR2_EXTERNAL_MYD_YF135_PATH)`. Standalone behavior is unchanged when
building from this repository directly.

## Contact

For security vulnerabilities: `security@deadband.dev`

For general questions or issues: use GitHub issues and discussions.

# Setup

## Prerequisites

### Nix

NixOS or Nix installed on your OS with flakes enabled. For example, on Arch:

```bash
sudo pacman -S nix
sudo systemctl enable --now nix-daemon.service

# in /etc/nix/nix.conf
trusted-users = root <your-username>
experimental-features = nix-flakes nix-command

nix-channel --add https://nixos.org/channels/nixpkgs-unstable
nix-channel --update
```

(See https://wiki.archlinux.org/title/Nix for more details)

### Direnv

It is recommended to use [direnv](https://direnv.net) and [nix-direnv](https://github.com/nix-community/nix-direnv). The dev shell provides all host tools automatically via direnv once enabled:

```bash
direnv allow
```

### Pre-commit Environment

Use the dedicated pre-commit shell so hook tooling does not bleed into the Buildroot build shell:

```bash
./support/pre-commit/install-pre-commit.sh
```

This configures `core.hooksPath=.githooks`, installs a repository-local pre-commit launcher,
and pre-warms hook environments using flake shell `.#pre-commit`.
To run hooks manually:

```bash
./support/pre-commit.sh
./support/pre-commit.sh run --files README.md
```

## CI

GitHub Actions runs pre-commit hooks on push and PRs. See [docs/ci.md](docs/ci.md) for workflow details, caching strategy, and how to run workflows locally with `act`.

## Build

```bash
make                # release image (default)
```

### Release and Debug Variants

Debug configurations can be build by setting `MODE=debug`:

```bash
MODE=debug make     # debug symbols + verbose firmware
```

`make release` and `make debug` are available as aliases. Defconfigs can also
be applied directly: `make myd_yf135_defconfig` or `make myd_yf135_debug_defconfig`.
See [docs/debug.md](docs/debug.md) for variant details, cache setup, and host-tool reuse behavior.

All output goes to `output/release` or `output/debug` and linked to `output/latest`.
Sources are cached in `dl/` for common use and to persist on clean builds.

### Incremental Targets

Buildroot's Makefile does not generally rebuild targets that may change due to dependencies. In this
case an incremental rebuild is required. A common example of this is `uboot-rebuild` will not re-pack
into the programmed .fip without an additional `arm-trustfed-firmware-rebuild`.

```bash
make linux-extract                 # download and unpack kernel source only
make linux-menuconfig
make linux-rebuild
make arm-trusted-firmware-rebuild
make optee-os-rebuild
make uboot-rebuild
make rootfs-ubi
make savedefconfig BR2_DEFCONFIG=$(pwd)/configs/myd_yf135_defconfig
```

### Nix hermetic build

_See https://github.com/velentr/buildroot.nix?tab=readme-ov-file#reproducibility for limitations and recommendations._

```bash
make nix-lock    # update lockfile (first time or after pkg/env changes)
nix build        # full image build
nix build .#sdk  # cross-compiler SDK (relocatable tarball)
```

Build outputs:

- `nix/build.nix`: build definition
- `nix/devshell.nix`: development shell configurations

## Make vs Nix Build

For typical local development, the `make` workflow allows incremental builds. This matches typical buildroot usage. I.e.:

- rerun only specific Buildroot targets like `uboot-rebuild`, or `linux-menuconfig`
- reuse Buildroot-local caches such as `dl/` and `output/ccache` which can be easily inspected for build debugging

Use the Nix + Cachix path for reproducible full builds:

- `nix build` restores cached Nix outputs across machines and CI if cached
- `nix build .#sdk` produces a relocatable cross-compiler SDK tarball
- Replicates the repository’s GitHub Actions workflow (see [docs/ci.md](docs/ci.md))

## Flashing

Uses STM32CubeProgrammer via DFU (USB-C in download mode). `flashlayout.tsv`
targets `spi-nand0` (SPI-NAND via QSPI). Programmer is packaged in
`nix/stm32cubeprog.nix` and available in the devshell as `STM32_Programmer_CLI`.

Current `flashlayout.tsv` is a **bring-up profile**: it programs only `fsbl1`,
`fsbl2`, `fip-a`, and `UBI`. Reserved slots (`metadata*`, `fip-b`) remain for
upcoming RAUC + secure-boot/A-B update work.

Set BOOT pins before flashing ([switch settings reference](https://docs.u-boot.org/en/latest/board/st/stm32mp1.html#switch-setting-for-boot-mode)):

| Mode | BOOT pins |
|------|-----------|
| USB DFU (recovery / flashing) | `0 0 0` |
| SPI-NAND (normal boot) | `1 1 1` |

```bash
# list detected DFU devices to confirm port name
STM32_Programmer_CLI -l usb

STM32_Programmer_CLI -c port=usb1 -w board/myd-yf135/flashlayout.tsv
```

## Serial console

Runtime console uses **UART4 TTL** at **115200 8N1**.

Typical usage:

1. Connect USB-to-TTL adapter to board UART4 header (GND/RX/TX).
1. Set BOOT pins to SPI-NAND mode and reset/power-cycle board.
1. Open console with minicom:

```bash
minicom -D /dev/ttyUSB0 -b 115200 -8
```

You should see TF-A, U-Boot, and Linux boot logs on this port.

# Technical Details

## Hardware

| Component | Detail |
|-----------|--------|
| SoC | STM32MP135DAF7, Cortex-A7 single-core, up to 1 GHz |
| RAM | 256 MB LPDDR3 @ `0xc0000000` |
| Flash | 256 MB SPI-NAND (Micron MT29F2G01ABAGDWB) via QSPI |
| Console | UART4, 115200 8N1 |
| USB OTG | DWC2 / `usbotg_hs`, USB-C via PTN5150 CC controller |
| USB host | EHCI / `usbh_ehci`, standard-A port |

Ethernet, audio, display, and camera are not enabled.

## Software stack

| Component | Version |
|-----------|---------|
| Buildroot | 2025.02 LTS |
| Linux | 6.12 LTS |
| TF-A | v2.12 |
| OP-TEE | 4.3.0 |
| U-Boot | 2025.01 |
| Toolchain | Buildroot internal glibc, NEON/VFPv4 |

## Boot chain

```
ROM -> TF-A BL2 (fsbl1/fsbl2) -> FIP -> OP-TEE (BL32) -> U-Boot (BL33) -> Linux 6.12
```

TF-A produces:

- `*.stm32`: raw BL2, written to `fsbl1` / `fsbl2`
- `fip.bin`: FIP (BL32 + BL33), written to `fip-a` / `fip-b`

## Memory map

| Region | Start | Size | Description |
|--------|-------|------|-------------|
| Linux RAM | `0xc0000000` | 208 MB | Normal-world usable memory |
| OP-TEE shmem | `0xcd000000` | 16 MB reserved, 2 MB used | Shared buffer between Linux and OP-TEE (`CFG_SHMEM_SIZE=0x200000`) |
| OP-TEE secure | `0xce000000` | 32 MB | Secure OS, no-map (`CFG_TZDRAM_START`) |

## SPI-NAND partition layout

| Partition | Offset | Size | Contents |
|-----------|--------|------|----------|
| `fsbl1` | `0x000000` | 512 KB | TF-A BL2 copy 1 |
| `fsbl2` | `0x080000` | 512 KB | TF-A BL2 copy 2 |
| `metadata1` | `0x100000` | 512 KB | FWU metadata A |
| `metadata2` | `0x180000` | 512 KB | FWU metadata B |
| `fip-a` | `0x200000` | 4 MB | FIP bank A |
| `fip-b` | `0x600000` | 4 MB | FIP bank B |
| `UBI` | `0xa00000` | ~246 MB | Root filesystem + data |

## NAND parameters and OTP

The correct OTP fuse parameters are crucial for booting using the upstream bootloader.
Vendor BSP hard-codes the NAND parameters to allow avoiding considering this, so incorrect
fuse values may be set from factory.

The Micron MT29F2G01ABAGDWB on this SOM is a 2-plane SPI-NAND. The correct OTP value is `0x80424000`.

Bit breakdown (from `plat/st/stm32mp1/stm32mp1_def.h`):

| Bits | Field | Value | Meaning |
|------|-------|-------|---------|
| 31 | NAND_PARAM_STORED_IN_OTP | 1 | params from OTP |
| 30-29 | page_size | 00 | 2 KB pages |
| 28-27 | block_size | 00 | 64 pages/block (128 KB) |
| 26-19 | block_nb | 0x08 | 2048 blocks (8 × 256) |
| 18 | width | 0 | 8-bit bus |
| 17-15 | ECC | 100 | on-die ECC |
| **14** | **nb_planes** | **1** | **2 planes** |

If the board was previously programmed with e.g. `0x80420000` (missing bit 14),
it is possible to re-burn from U-Boot (be aware, OTP bits are one-way!):

```
STM32MP> fuse prog 0 9 0x00004000
STM32MP> fuse sense 0 9        # read back: should show 80424000
```

TF-A's `spi_nand_read_from_cache()` already has plane-select bit logic; it
activates automatically when `nb_planes > 1` is set via OTP. If this is set incorrectly, data
spanning planes will be read as corrupt. This can result in strange behaviour where first-stage
bootloaders may work until loading a large enough page to span planes!

## Device tree

All DTS files live in `board/myd-yf135/dts/` and are passed to each firmware
component via `BR2_*_CUSTOM_DTS_PATH`; nothing is patched into upstream source.

| File | Used by |
|------|---------|
| `stm32mp135d-myd-yf135.dts` | Linux, U-Boot |
| `stm32mp135d-myd-yf135-u-boot.dtsi` | U-Boot additions |
| `stm32mp135d-myd-yf135-tf-a.dts/.dtsi` | TF-A BL2 |
| `stm32mp135d-myd-yf135-tf-a-fw-config.dts` | BL32/BL33 load addresses |
| `stm32mp135d-myd-yf135-optee.dts` | OP-TEE secure peripherals |

Note: due to a recent refactoring of the kernel ST device tree sources, a special build step is needed
to inject dts files into the build via external.mk. This may be fixed in a future buildroot release.

### Key board-specific pin fix

Upstream `qspi_bk1_pins_a` has wrong IO2/IO3 pins for this board:

| Signal | Upstream | MYD-YF135 |
|--------|----------|-----------|
| `QSPI_BK1_IO2` | PD11 (AF9) | **PD7 (AF11)** |
| `QSPI_BK1_IO3` | PH7 (AF13) | **PD13 (AF9)** |

Fixed via `qspi_bk1_pins_b` defined in the board DTS.

## Differences from vendor and community configs

### Reference projects

- **[bootlin/buildroot-external-st](https://github.com/bootlin/buildroot-external-st)**: ST-maintained BR2 external; targets ST eval boards, uses ST kernel/OP-TEE forks
- **[BasicCode/STM32MP135_Dev_Board_Buildroot](https://github.com/BasicCode/STM32MP135_Dev_Board_Buildroot)**: community BR2 config for a similar MP135 board; useful starting point but uses ST OP-TEE fork DTS constructs that don't build with upstream OP-TEE
- **[MYiR-Dev/myir-st-linux](https://github.com/MYiR-Dev/myir-st-linux/tree/develop-yf13x-L6.6.78)**: MYIR's kernel fork (v6.6 + ~40 commits); used as pinctrl/DTS reference only
- **[MYIR BSP](https://developer.myir.cn/home/user/myProDetail/product_id/35.html)**: vendor BSP (registration required); used to confirm NAND chip identity and pin wiring

This repo uses **all upstream releases** (no ST/MYIR forks) and targets the MYD-YF135 specifically.

### NAND chip

Community docs and some BSP references incorrectly identify the flash as a Macronix MX35LF2G24AD. The actual chip is a **Micron MT29F2G01ABAGDWB**, confirmed from MYIR hardware datasheets and U-Boot probe output (`MT29F2G01AB`). DTS uses `compatible = "spi-nand"` with `spi-max-frequency = <100000000>` (100 MHz).

### TF-A: NAND plane count via OTP vs vendor hardcode

The vendor TF-A fork hardcodes NAND parameters at the top of `get_data_from_otp()`, bypassing OTP entirely (`page_size=2048`, `block_size=128KB`, `nb_planes=2`, `size=256MB`, returns 0 before reading OTP). Upstream TF-A reads these from the OTP fuse, which requires the fuse to be burned correctly with bit 14 set for 2 planes. See the [NAND parameters and OTP](#nand-parameters-and-otp) section.

### OP-TEE DTS: ST-fork nodes removed

The ST OP-TEE fork carries STM32MP1-specific DTS infrastructure not present in upstream OP-TEE 4.3.0. Community configs (BasicCode etc.) use these constructs and will not build with upstream OP-TEE:

| Node | What it does | Upstream status |
|------|-------------|-----------------|
| `&etzpc` with `st,decprot` | Peripheral security access control | Hardcoded in `core/drivers/stm32_etzpc.c` |
| `&tzc400` | TZC400 memory firewall | Hardcoded in platform C code |
| `&scmi_regu` with `VOLTD_SCMI_*` | SCMI voltage domain mapping | Static defaults in SCMI server |
| `&pwr_regulators` suspend modes | `system_suspend_supported_soc_modes` | Upstream takes only `vdd-supply`/`vdd_3v3_usbfs-supply` |

Our `stm32mp135d-myd-yf135-optee.dts` is modeled on the upstream `stm32mp135f-dk.dts` from OP-TEE OS 4.3.0.

### Kernel config: no stm32mp135_defconfig

Neither ST nor upstream ships a `stm32mp135_defconfig`. This repo uses `multi_v7_defconfig` as the base (matching ST's approach), with relevant options enabled via `make linux-menuconfig` and saved to `board/myd-yf135/linux.config`.

### Flashlayout: spi-nand0 not nand0

`nand0` is the IP name for raw FMC-attached NAND on STM32MP15x boards. SPI-NAND via QSPI registers as `spi-nand0` in U-Boot. `flashlayout.tsv` uses `spi-nand0` accordingly; other community configs targeting FMC NAND may have the wrong IP name.
