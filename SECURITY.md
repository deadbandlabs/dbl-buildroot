# Security Policy

## Reporting Security Vulnerabilities

**Do not open public GitHub issues for security vulnerabilities.** Use one of the below channels:

1. **GitHub private vulnerability reporting** (preferred): use the "Report a vulnerability" button on the Security tab
1. **Email**: `security@deadband.dev`

Include:

- Description of the vulnerability
- Affected components (kernel, U-Boot, TF-A, OP-TEE, board config, Nix build, etc.)
- Steps to reproduce (if applicable)
- Proposed fix (optional)

We aim to:

- **Acknowledge** your report within 7 business days
- **Provide an initial assessment** (severity, affected components, whether we can reproduce) within 14 business days
- **Coordinate disclosure** on a 90-day timeline from the initial report, or sooner once a fix is available

If a report stalls on our end, you are free to disclose after the 90-day window. We will work with you on extensions for complex hardware-level issues (e.g. secure boot, OTP) where coordination with upstream (TF-A, OP-TEE) or silicon vendors is required.

## Scope

We accept reports for anything actionable in this repo:

- Buildroot external tree configuration, device tree patches, board-level customizations
- Nix build setup, `buildroot.lock` integrity

Requests to update a pinned upstream component (Linux, U-Boot, TF-A, OP-TEE, RAUC) to resolve a known vulnerability can be filed as a regular GitHub issue (a general update request).

## Security Updates

This project tracks upstream LTS releases via Buildroot 2025.02.y (LTS). All component versions are pinned in the defconfig and locked in `buildroot.lock` with SHA-256 checksums. Updates are manually applied when a new Buildroot LTS point release is available and tested.

| Component | Version | Info |
|-----------|---------|--------|
| Buildroot | 2025.02.y (LTS) | [CHANGES](https://gitlab.com/buildroot.org/buildroot/-/blob/2025.02/CHANGES) |
| Linux kernel | 6.12.y (LTS) | pinned in defconfig `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`, updated via Buildroot LTS |
| U-Boot | 2025.01 | via Buildroot 2025.02 `BR2_TARGET_UBOOT_LATEST_VERSION` |
| TF-A | v2.12 | via Buildroot 2025.02 `BR2_TARGET_ARM_TRUSTED_FIRMWARE_LATEST_VERSION` |
| OP-TEE | 4.3.0 | via Buildroot 2025.02 `BR2_TARGET_OPTEE_OS_LATEST` |

If a vulnerability in a pinned upstream component has a fix available, we will bump the pin and release promptly.

Downstream consumers using this repo as a submodule should bump the submodule pointer to receive updates. Use `make update-dbl-buildroot` (advances to latest `main`) or `make update-dbl-buildroot REF=v1.2.3` to pin to a specific tag or SHA. The make target is used to ensure the submodule, pre-commit hooks, and CI workflow pins remain in sync.

## Recommendations for Users

1. **Pin releases**: for production, pin a specific commit SHA or tag
1. **Monitor upstream**: subscribe to security mailing lists for Linux, U-Boot, TF-A, OP-TEE
1. **Review changes**: before pulling updates, review commit history and Buildroot release notes
1. **Test on hardware**: validate updates on your board before deploying to production

## Hardware Security

The STM32MP135D supports:

- **OTP (One-Time Programmable) fuses**: can lock boot sources, disable JTAG, etc.
- **Secure boot (TF-A + OP-TEE)**: verified boot chain

**Neither is enabled by default.** Secure boot (`TRUSTED_BOARD_BOOT`) is not yet integrated. Enabling it requires:

1. Understanding OTP/fuse implications (fuse programming is permanent)
1. Secure key management (RSA keys for boot attestation)
1. Testing with Secure Boot enabled in all variants (release, debug, etc.)

Consult ST documentation and TF-A/OP-TEE security guidelines before enabling.

## OTA Updates

RAUC integration is scaffolded, and RAUC Bundle signing is configured but **no signing key is shipped**. Downstream consumers must generate and manage their own keys before deploying OTA updates.

## Safe Harbour & Acknowledgements

We welcome good-faith security research. Report what you find and we'll work with you to fix it. No hard feelings! We'll also credit you in any resulting security advisory, unless you'd rather stay anonymous.

Please: test only against your own devices and builds (not someone else's deployed hardware), don't destroy data or violate privacy, and give us a chance to fix things before going public. We can only speak for ourselves, anyone shipping this in their own products keeps their own rights.
