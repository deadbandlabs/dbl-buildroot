# Security Policy

## Reporting Security Vulnerabilities

**Do not open public GitHub issues for security vulnerabilities.** Instead:

1. Email `security@deadband.dev` with details
1. Include:
   - Description of the vulnerability
   - Affected components (kernel, U-Boot, TF-A, OP-TEE, Nix flake, etc.)
   - Steps to reproduce (if applicable)
   - Proposed fix (optional)
1. Allow 90 days for a response and patch before public disclosure

## Scope

Vulnerabilities in:

- **In-scope**: Buildroot external tree configuration, device tree patches, board-level customizations, Nix flake setup
- **Out-of-scope**: Vulnerabilities in upstream projects (Linux, U-Boot, TF-A, OP-TEE): report directly to those projects

## Security Updates

This project follows upstream security releases for:

- **Buildroot**: pinned to 2025.02.12 LTS; we update when the LTS receives patches
- **Linux kernel**: updates via Buildroot LTS branch
- **U-Boot / TF-A / OP-TEE**: upstream tags pinned in `flake.nix`; we monitor upstream security advisories and update on request

If a vulnerability affects versions in active use on this repo:

- If a fix is available: we will update and release promptly
- If no fix exists: we will notify affected projects (Linux, U-Boot, TF-A, OP-TEE) and coordinate disclosure

## Recommendations for Users

1. **Pin releases**: For production, pin a specific tag (not `main`)
1. **Monitor upstream**: Subscribe to security mailing lists for Linux, U-Boot, TF-A, OP-TEE
1. **Review changes**: Before pulling updates, review commit history and Buildroot release notes
1. **Test on hardware**: Verify security patches don't regress your specific use case before deployment

## Hardware Security

The STM32MP135D supports:

- **OTP (One-Time Programmable) fuses**: can lock boot sources, disable JTAG, etc.
- **Secure boot (TF-A + OP-TEE)**: attestation and verified boot chains configured in device tree and firmware

**These are not enabled by default.** Enabling them requires:

1. Understanding OTP/fuse implications (fuse programming is permanent)
1. Secure key management (RSA keys for boot attestation)
1. Testing with Secure Boot enabled in all variants (release, debug, etc.)

Consult ST documentation and TF-A/OP-TEE security guidelines before enabling.

## Acknowledgments

Thank you to security researchers who responsibly disclose vulnerabilities. We will acknowledge contributors in security advisories (unless you request otherwise).
