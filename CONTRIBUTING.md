# Contributing to dbl-buildroot

Contributions are welcome. This document covers how to report issues, how to submit changes, and the conventions the project follows.

## Code of conduct

Please keep all interactions respectful and constructive. The project aims to provide a welcoming and inclusive environment.

## Reporting issues

GitHub Issues track bugs and feature requests. Discussions are not enabled, so questions also go through Issues.

- For a bug, describe the problem, the steps to reproduce it, and the expected versus actual behaviour.
- For a feature request, explain the use case and why it would benefit the project.
- For a question, open an issue with a clear title.

## Submitting changes

1. Fork the repository and create a feature branch, for example `git checkout -b fix/serial-init` or `git checkout -b feat/debug-variant`.
1. Make the change.
1. Write commit messages in [Conventional Commits](https://www.conventionalcommits.org/) format, for example `fix: correct serial init` or `feat: add debug variant`. Commitizen enforces this at pre-push time, and a non-conforming message blocks the push.
1. Install the pre-commit hooks with `./support/pre-commit/install-pre-commit.sh`.
1. Run the hooks with `./support/pre-commit.sh run --all-files`, which uses the Nix environment automatically.
1. Push to your fork, open a pull request, and link any related issues in the description.

## Code style

All code is auto-formatted and linted by pre-commit hooks:

- Shell scripts use `shfmt` with a two-space indent, together with `shellcheck`.
- Nix files use `nixfmt` (RFC style).
- YAML files use `yamllint`.
- Markdown files use `mdformat`.
- Device tree sources are checked against the Linux kernel `checkpatch.pl` style on `.dts` and `.dtsi` files.
- Tabs are forbidden in text files and required only in Makefiles.
- `reuse lint` enforces SPDX headers on every file.

Run `./support/pre-commit.sh run --all-files` before pushing, or install the hooks so that they run automatically.

## Licensing

This project is licensed under GPL-2.0-or-later, with some files under CC0-1.0. By contributing, you agree that your contributions are licensed under the same terms.

- Upstream code from Linux, U-Boot, TF-A, and OP-TEE retains its original license.
- New code is GPL-2.0-or-later by default.
- Metadata and configuration files, such as lock files and `.gitignore`, are CC0-1.0.

Every file must include an SPDX header. See [REUSE.toml](REUSE.toml) for compliance details.

## Design principles

Before proposing a large change, review the goals of the project:

- Stay close to upstream. The Buildroot, Linux, U-Boot, TF-A, and OP-TEE versions are pinned, and fixes or features belong upstream rather than in downstream patches.
- Keep drift minimal. Board changes stay in `board/` and `configs/`, and the core external tree stays generic.
- Preserve reproducibility. Nix flakes pin the tooling, and changes should not degrade the hermetic builds.
- Keep the surface area small. Only upstream-supported hardware is in scope, and anything the vendor ships that is unsupported upstream is out of scope.

## CI

GitHub Actions workflows run automatically on pushes and pull requests. See the [CI](https://github.com/deadbandlabs/dbl-buildroot/wiki/6.-CI) wiki page for details.

## Testing

- Test on actual hardware where possible, on the MYD-YF135-256N-256D or a similar STM32MP135D board.
- For changes to `board/`, `configs/`, or the Makefiles, document the target testing in the commit or pull request, for example "tested: release build, debug build, flashing".
- For changes to scripts, test them in the Nix environment.

## Questions

Open a GitHub Issue, or check the [README](README.md) and the [wiki](https://github.com/deadbandlabs/dbl-buildroot/wiki) for existing documentation.
