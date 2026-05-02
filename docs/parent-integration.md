# Parent Project Integration

dbl-buildroot is designed to be consumed as a git submodule by one or more
downstream parent projects or "superprojects". A superproject adds project-specific
packages, config overlays, and CI on top of the base build system.

## Architecture

```
parent-repo/                    (superproject)
├── modules/dbl-buildroot/      (submodule)
│   ├── lib.nix                 mkProject entry point
│   ├── inputs.nix              canonical flake-input URLs
│   ├── nix/build.nix           hermetic build derivation
│   └── support/parent/         integration scripts
├── overlay/                    (BR2_EXTERNAL tree)
│   ├── external.desc
│   ├── Config.in
│   └── my-project.fragment     (defconfig overlay)
├── flake.nix
├── Makefile
└── .pre-commit-config.yaml
```

The submodule provides:

- `lib.mkProject`: builds `packages + devShells` from a single call
- `inputs.nix`: canonical input URLs (single source of truth)
- `support/parent.mk`: Makefile fragment with `make build`, `make develop`,
  `make update-dbl-buildroot`, `make check-dbl-buildroot`
- `support/parent/update.sh`: one-shot bumper (submodule + all SHA pins)
- `support/parent/check-pinned-shas.sh`: drift gate
- `support/parent/sync-flake-inputs.sh`: pre-commit autofix for inputs block
- `.github/workflows/downstream.yml`: Runs all build CI (checks release + debug)
- `.pre-commit-hooks.yaml`: exported hooks for downstream repos

## Quick start

```bash
git init my-project && cd my-project
git submodule add git@github.com:deadbandlabs/dbl-buildroot.git \
    modules/dbl-buildroot
modules/dbl-buildroot/support/parent/init.sh \
    --name=my-project \
    --defconfig=myd_yf135_defconfig \
    --flash-layout=board/myd-yf135/flashlayout.tsv
```

This generates everything from the template in `support/parent/template/`:

| Generated file | Purpose |
|----------------|---------|
| `flake.nix` | Nix flake calling `mkProject` with overlay + fragment |
| `Makefile` | Includes `support/parent.mk`; forwards `make` to submodule, provides `make build` for nix |
| `overlay/` | BR2_EXTERNAL tree (external.desc, Config.in, fragment, package/Config.in) |
| `.pre-commit-config.yaml` | Hook IDs from submodule, SHA pinned |
| `.github/workflows/build.yml` | Calls `downstream.yml` at pinned SHA |
| `.envrc` | direnv integration |
| `.gitignore` | Standard patterns |
| `REUSE.toml` | License annotations |

After init, review the generated files, stage, and verify:

```bash
git add -A
make check-dbl-buildroot  # drift gates pass
make build                # hermetic nix build
```

Run `init.sh --help` for all options (copyright, defconfig override, etc.).

## Updating the submodule

```bash
make update-dbl-buildroot               # advance to origin/main
make update-dbl-buildroot REF=v1.2.3    # advance to a tag
```

This runs `support/parent/update.sh` which:

1. Fetches and checks out the target ref in the submodule
1. Propagates the new SHA to `.pre-commit-config.yaml` and all workflow `uses:` refs
1. Refreshes `flake.lock`
1. Runs consistency checks

Stage everything it reports at the end:

```bash
git add modules/dbl-buildroot .pre-commit-config.yaml .github/workflows/ flake.lock
```

## Drift detection

Two pre-commit hooks catch drift of submodule references (SHAs) before it reaches CI:

| Hook | Script | What it checks |
|------|--------|---------------|
| `dbl-buildroot-sync-inputs` | `support/parent/sync-flake-inputs.sh` | `inputs.nix` vs. `flake.nix` inputs block |
| `dbl-buildroot-pinned-shas` | `support/parent/check-pinned-shas.sh` | Submodule SHA vs. `rev:` in pre-commit config + `uses:@<sha>` in workflows |

These are registered as no-op when running inside the submodule itself
(repos without a `modules/dbl-buildroot/` directory).

## mkProject parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `nixpkgs` | yes | - | nixpkgs flake input |
| `buildroot` | yes | - | Buildroot source (non-flake) |
| `buildroot-nix` | yes | - | buildroot.nix flake input |
| `name` | yes | - | Project name (derivation name) |
| `defconfig` | yes | - | Buildroot defconfig to apply |
| `flashLayout` | yes | - | Path to flash layout TSV |
| `extraExternalSrcs` | no | `[]` | Additional BR2_EXTERNAL trees |
| `configFragment` | no | `null` | Defconfig fragment to merge over base |
| `system` | no | `"x86_64-linux"` | Target system |
| `extraDevShellPackages` | no | `[]` | Additional packages in dev shell |

## Local development

```bash
make develop          # enter nix dev shell
make build            # hermetic release build (nix build)
make sdk              # SDK tarball
make                  # interactive make (debug, menuconfig, etc.)
make debug            # debug variant via make
```
