# Contributing to dbl-buildroot

Thank you for your interest in contributing to dbl-buildroot!

## Code of Conduct

We are committed to providing a welcoming and inclusive environment. Please be respectful and constructive in all interactions.

## How to Contribute

### Reporting Issues

- **Bugs**: Describe the problem, reproduction steps, and expected vs. actual behavior
- **Feature requests**: Explain the use case and why it would benefit the project
- **Questions**: Use discussions; GitHub Issues are for bugs and features

### Submitting Changes

1. Fork the repository
1. Create a feature branch: `git checkout -b fix/your-fix` or `git checkout -b feat/your-feature`
1. Make your changes
1. **Use [Conventional Commits](https://www.conventionalcommits.org/) format**: Commitizen checks this at commit-msg time in warning-only mode (e.g., `fix: correct serial init`, `feat: add debug variant`)
1. Install pre-commit hooks: `./support/pre-commit/install-pre-commit.sh`
1. Run hooks: `./support/pre-commit.sh run --all-files` uses the Nix environment automatically
1. Push to your fork and submit a pull request
1. Link any related issues in the PR description

### Code Style

All code is auto-formatted by pre-commit hooks:

- Shell scripts: `shfmt` (2-space indent)
- Nix: `nixfmt` (RFC style)
- YAML: `yamllint`
- Markdown: `mdformat`
- Tabs: forbidden in text files (tabs required in Makefiles only)

Run `./support/pre-commit.sh run --all-files` before pushing or install hooks via `support/pre-commit/install-pre-commit.sh`.

### Licensing

This project is licensed under GPL-2.0-or-later (plus some files under CC0-1.0). By contributing, you agree that your contributions will be licensed under the same terms.

- Upstream code from Linux/U-Boot/TF-A/OP-TEE patches retain their original licenses
- New code: GPL-2.0-or-later by default
- Metadata/config files (lock files, .gitignore, etc.): CC0-1.0

All files must include SPDX headers. See [REUSE.toml](REUSE.toml) for compliance details.

### Design Principles

Before proposing large changes, review the project's goals:

- **Stay close to upstream**: Buildroot, Linux, U-Boot, TF-A, OP-TEE upstream versions are pinned; prefer fixes/features in upstream over downstream patches
- **Minimal drift**: board changes stay in `board/` and `configs/` only; keep core external tree generic
- **Reproducibility**: Nix flakes pin tooling; changes should not degrade hermetic builds
- **Small surface area**: support upstream-only hardware; if the vendor ships something unsupported upstream, it's out of scope

### Testing

- Test on actual hardware if possible (MYD-YF135-256N-256D or similar STM32MP135D)
- For changes to `board/`, `configs/`, or Makefiles: document target testing (e.g., "tested: release build, debug build, flashing") in the commit or PR
- For changes to scripts: test in the Nix environment

### Questions?

Open a discussion on GitHub, or check [README.md](README.md) for existing documentation.
