# Security policy

## Reporting security vulnerabilities

Please do not open public GitHub issues for security vulnerabilities. Use one of the following channels instead:

1. GitHub private vulnerability reporting (preferred): use the "Report a vulnerability" button on the Security tab.
1. Email: `security@deadband.dev`.

Please include the following where it applies:

- A description of the vulnerability.
- The affected components, such as the kernel, U-Boot, TF-A, OP-TEE, the board configuration, or the Nix build.
- The steps to reproduce it, if applicable.
- A proposed fix, which is optional.

The project aims to acknowledge a report within 7 business days, to provide an initial assessment of severity, affected components, and reproducibility within 14 business days, and to coordinate disclosure on a 90-day timeline from the initial report, or sooner once a fix is available.

If a report stalls on the maintainers' end, you are free to disclose after the 90-day window. The maintainers will work with you on extensions for complex hardware-level issues, such as secure boot or OTP, where coordination with upstream projects (TF-A, OP-TEE) or silicon vendors is required.

## Scope

The project accepts reports for anything actionable in this repository:

- The Buildroot external tree configuration, device tree patches, and board-level customizations.
- The Nix build setup and `buildroot.lock` / `toolchain.lock` integrity.

A request to update a pinned upstream component (Linux, U-Boot, TF-A, OP-TEE, or RAUC) to resolve a known vulnerability can be filed as a regular GitHub issue, as a general update request.

## Security updates

This project tracks upstream LTS releases through Buildroot 2025.02.y (LTS). All component versions are pinned in the defconfig and locked in `buildroot.lock` (and the toolchain in `toolchain.lock`) with SHA-256 checksums. Updates are applied manually when a new Buildroot LTS point release is available and tested.

| Component | Version | Info |
|-----------|---------|--------|
| Buildroot | 2025.02.y (LTS) | [CHANGES](https://gitlab.com/buildroot.org/buildroot/-/blob/2025.02/CHANGES) |
| Linux kernel | 6.12.y (LTS) | pinned in defconfig `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`, updated via Buildroot LTS |
| U-Boot | 2025.01 | via Buildroot 2025.02 `BR2_TARGET_UBOOT_LATEST_VERSION` |
| TF-A | v2.12 | via Buildroot 2025.02 `BR2_TARGET_ARM_TRUSTED_FIRMWARE_LATEST_VERSION` |
| OP-TEE | 4.3.0 | via Buildroot 2025.02 `BR2_TARGET_OPTEE_OS_LATEST` |

When a fix is available for a vulnerability in a pinned upstream component, the maintainers bump the pin and release promptly.

Downstream consumers that use this repository as a submodule should bump the submodule pointer to receive updates. Use `make update-dbl-buildroot` to advance to the latest `main`, or `make update-dbl-buildroot REF=v1.2.3` to pin a specific tag or SHA. This target keeps the submodule, the pre-commit hooks, and the CI workflow pins in sync.

## Recommendations for users

1. Pin releases. For production, pin a specific commit SHA or tag.
1. Monitor upstream. Subscribe to the security mailing lists for Linux, U-Boot, TF-A, and OP-TEE.
1. Review changes. Before pulling updates, review the commit history and the Buildroot release notes.
1. Test on hardware. Validate updates on your board before deploying to production.

## Hardware security

The STM32MP135D supports two hardware security features:

- OTP (one-time programmable) fuses, which can lock boot sources, disable JTAG, and similar.
- Secure boot through TF-A and OP-TEE, which provides a verified boot chain.

Neither is enabled by default, and secure boot (`TRUSTED_BOARD_BOOT`) is not yet integrated. Enabling it requires an understanding of the OTP and fuse implications (fuse programming is permanent), secure key management (RSA keys for boot attestation), and testing with secure boot enabled in all variants (release, debug, and so on). Consult the ST documentation and the TF-A and OP-TEE security guidelines before enabling it.

## OTA updates

RAUC integration is scaffolded, and RAUC bundle signing is configured, but no signing key is shipped. Downstream consumers must generate and manage their own keys before deploying OTA updates.

## Safe harbour and acknowledgements

The project welcomes good-faith security research. Report what you find, and the maintainers will work with you to fix it. You will be credited in any resulting security advisory unless you would rather stay anonymous.

Please test only against your own devices and builds, rather than against someone else's deployed hardware, avoid destroying data or violating privacy, and give the maintainers a chance to fix an issue before going public. The maintainers can speak only for themselves; anyone shipping this in their own products retains their own rights.
