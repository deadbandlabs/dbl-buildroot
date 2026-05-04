# Parent Project Integration

dbl-buildroot is designed to be consumed as a git submodule by one or more
downstream parent projects or "superprojects". A superproject adds project-specific
packages, config overlays, and CI on top of the base build system.

## Architecture

```
parent-repo/                    (superproject)
├── modules/dbl-buildroot/      (submodule)
│   ├── lib.nix                 mkProject entry point
│   ├── inputs.nix              canonical input URLs for target revs
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
- `inputs.nix`: rev-pinned input URLs (fetched by `lib.nix` to be inherited by parent flakes)
- `support/parent.mk`: Makefile fragment with `make build`, `make develop`,
  `make update-dbl-buildroot`, `make check-dbl-buildroot`
- `support/parent/update.sh`: one-shot bumper (submodule + all SHA pins)
- `support/parent/check-pinned-shas.sh`: drift gate
- `.github/workflows/downstream.yml`: Runs all build CI (checks release + debug)
- `.pre-commit-hooks.yaml`: exported hooks for downstream repos

## Quick start

```bash
git init my-project && cd my-project
git submodule add git@github.com:deadbandlabs/dbl-buildroot.git \
    modules/dbl-buildroot
modules/dbl-buildroot/support/parent/init.sh \
    --name=my-project \
    --board=myd-yf135
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

Run `init.sh --help` for all options (copyright, board, etc.).

## Updating the submodule

```bash
make update-dbl-buildroot               # advance to origin/main
make update-dbl-buildroot REF=v1.2.3    # advance to a tag
```

This runs `support/parent/update.sh` which:

1. Fetches and checks out the target ref in the submodule
1. Propagates the new SHA to `.pre-commit-config.yaml` and all workflow `uses:` refs
1. Runs consistency checks

Stage everything it reports at the end:

```bash
git add modules/dbl-buildroot .pre-commit-config.yaml .github/workflows/
```

## Drift detection

One pre-commit hook catches drift of submodule references (SHAs) before it reaches CI:

| Hook | Script | What it checks |
|------|--------|---------------|
| `dbl-buildroot-pinned-shas` | `support/parent/check-pinned-shas.sh` | Submodule SHA vs. `rev:` in pre-commit config + `uses:@<sha>` in workflows |

This is a no-op when running inside the submodule itself (repos without a
`modules/dbl-buildroot/` directory).

Bumping the buildroot/nixpkgs/buildroot-nix pins themselves is done by editing
`modules/dbl-buildroot/inputs.nix` upstream and bumping the submodule pointer
in the parent. There is no parent-side input to keep in sync.

## mkProject parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | yes | - | Project name (derivation name) |
| `board` | yes | - | Board name; drives `defconfig` + `flashLayout` defaults |
| `nixpkgs` | no | self-fetched from `inputs.nix` | Override nixpkgs source |
| `buildroot` | no | self-fetched from `inputs.nix` | Override Buildroot source |
| `buildroot-nix` | no | self-fetched from `inputs.nix` | Override buildroot.nix |
| `defconfig` | no | `<board-with-underscores>_defconfig` | Override defconfig name |
| `flashLayout` | no | `board/<board>/flashlayout.tsv` | Override flash layout path |
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
