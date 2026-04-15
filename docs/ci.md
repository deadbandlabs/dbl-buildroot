# CI Hooks

## GitHub Actions Workflows

### `pre-commit.yml` Pre-commit checks

Runs on push and pull requests to `main`, `release/*`, and `dev/*`.

Jobs:

- **`nix-env`**: Instantiates the `ci` devShell, applies the Buildroot defconfig, and downloads the Linux kernel source tarball into `dl/`. Fails here if the Nix environment is broken. Kernel sources provide pre-commit rules for Device Tree files.
- **`pre-commit`**: Restores `dl/` from cache, then runs all pre-commit hooks via `./support/pre-commit.sh`. Results are written to the job summary.

If `nix-env` fails, `pre-commit` is blocked and the failure is clearly attributed to the environment rather than a hook.

#### Commit message checks

Commit messages are validated against [Conventional Commits](https://www.conventionalcommits.org/) at push time (via the `pre-push` git hook) and in CI. They are intentionally not checked on every local commit to allow rebasing and fixups without friction.

To check messages manually:

```bash
# Check the last N commits
./support/pre-commit/commitizen-check-push.sh HEAD~3

# Check from a specific base
./support/pre-commit/commitizen-check-push.sh main
```

The script re-execs inside `nix develop .#pre-commit` automatically if `cz` is not on `PATH`.

#### Caching

`dl/` is cached keyed on `buildroot.lock`. The cache accumulates downloaded sources over time and is reused across runs as long as the lock file doesn't change. As more packages are added (e.g. for a full build job), their tarballs will be included automatically.

## Running locally with Act

[`act`](https://github.com/nektos/act) is included in the `default` devShell and runs GitHub Actions workflows locally via Docker.

```bash
# Run all workflows
act

# Run a specific workflow
act -W .github/workflows/pre-commit.yml

# Run a specific job from a workflow
act -W .github/workflows/pre-commit.yml -j pre-commit
```

### Known limitations

- **Nix install warning**: `cachix/install-nix-action` prints a warning about running as root inside the Act container. This is cosmetic; Nix installs and works correctly.
- **Cache action**: `actions/cache@v5` will not be using cache from GitHub. This may work differently depending on local configuration.

## The `ci` Nix devShell

The `ci` devShell (`nix develop .#ci`) contains all packages needed to run Buildroot builds in CI, identical to the `default` shell minus tools that require manual setup or are local-only:

- **`stm32cubeprog`**: Requires a manually downloaded ST zip; cannot be fetched automatically.
- **`act`, `podman`**: Local workflow tooling, not needed in CI.

Use `.#ci` in any CI step that invokes `make`. Use `.#default` locally for the full development environment including flashing tools.

To enter the CI shell locally (e.g. to reproduce a CI-specific environment failure):

```bash
nix develop .#ci
```

## Adding a new workflow

- Use `nix develop .#ci --command <cmd>` for steps needing the Buildroot environment.
- Use `nix develop .#pre-commit --command <cmd>` for lint/hook steps.
- Add `dl/` to the cache if the job downloads sources; key on `buildroot.lock`.
- If a job depends on the Nix environment being valid, add `needs: nix-env` to make the dependency explicit.
