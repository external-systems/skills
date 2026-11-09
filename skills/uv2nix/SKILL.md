---
name: uv2nix
description: "uv2nix and pyproject.nix: build Python packages, apps and virtualenvs from a uv workspace (pyproject.toml + uv.lock) in a flake-parts repo, the org layout (inputs, flake-parts/python.nix, devenv editable venv, pkgs overlay packages), overrides for native libs and sdist build systems, maintaining the lock, and debugging failed builds. Load whenever Python meets Nix: packaging a Python app or CLI, a pyproject.toml or uv.lock in a flake, a Python dev shell, or uv2nix/pyproject.nix errors."
---

# uv2nix

uv2nix turns a **uv workspace** (`pyproject.toml` + `uv.lock`) into Nix
derivations in pure Nix: no codegen, no IFD, nothing committed but the
lock. It is built on **pyproject.nix**'s builders, and
**build-system-pkgs** supplies the build backends uv never locks. All
three live under github.com/pyproject-nix. The source of truth is the
code; clone it when this skill runs out:
`git clone https://github.com/pyproject-nix/uv2nix` (`lib/workspace.nix`,
`lib/build.nix`, `doc/src/`), same for `pyproject.nix` (`build/`).

Facts below were verified on 2026-11-09 against uv2nix `c361746`,
pyproject.nix `d43f0e7`, the org nixpkgs (uv 0.13.5, python313 3.13.16)
and devenv 2.4 by building a flake-parts demo end to end.

## Pick the tool first

| Need | Use |
|---|---|
| Ship a Python app, CLI, service or image from a flake | uv2nix (this skill) |
| A dev shell whose venv matches the Nix build exactly | uv2nix editable venv in devenv |
| A dev shell only, nothing shipped by Nix | devenv `languages.python.uv` (impure `uv sync`), no uv2nix |
| A few well-known libs for a script or docs build | `python3.withPackages` from nixpkgs |
| A lib or tool already in nixpkgs, small fix needed | `overridePythonAttrs` on nixpkgs |

uv2nix wins when the dependency set is wider or newer than nixpkgs: a
uv lock pins every version, so there is no fighting nixpkgs' single
version per package (the pkgs repo's `headroom` overrides `filelock`,
`mcp` and `typer` by hand for exactly that reason).

## Mental model

```
pyproject.toml + uv.lock
  └─ uv2nix.lib.workspace.loadWorkspace {workspaceRoot}      -> workspace
       └─ workspace.mkPyprojectOverlay {sourcePreference}    -> overlay (one drv per locked pkg)
pkgs.callPackage pyproject-nix.build.packages {python}       -> empty base scope
  .overrideScope (composeManyExtensions [
     pyproject-build-systems.overlays.wheel   # build backends
     overlay                                  # the lock
     overrides                                # your fixups, last
  ])                                                         -> pythonSet
pythonSet.mkVirtualEnv "name" workspace.deps.default         -> venv (bin/python, scripts)
mkApplication {venv; package = pythonSet.NAME;}               -> app without venv cruft
```

- **Every package is a separate derivation** built from a wheel or an
  sdist. Runtime deps sit in `passthru.dependencies`, never propagated:
  nothing is importable until packages are joined in a venv with
  `mkVirtualEnv`. Tests therefore run against a venv, not inside a
  package build.
- **sourcePreference** is required (or inferred from `tool.uv.no-build`
  / `no-binary`). Use `"wheel"`: wheels need only native libs, sdists
  also need build systems. Flip a single package with
  `prev.foo.override {sourcePreference = "sdist";}` or
  `tool.uv.no-binary-package`.
- **No bundled overrides.** uv.lock carries no native libraries and no
  build systems; fill gaps in your overrides overlay
  ([references/overrides.md](references/overrides.md)).
- **Dependency specs** are attrsets of `name = [extras-or-groups]`.
  `workspace.deps` has four presets: `default` (no extras or groups, plus
  `tool.uv.default-groups`), `optionals`, `groups`, `all`.
- **The lock is the input.** uv2nix reads `uv.lock`, not the resolver:
  a `pyproject.toml` edited without `uv lock` builds silently from the
  stale lock (a new dependency is just missing). The `uv-lock` check in
  the recipe catches it.

## The org layout

Every org repo is a flake-parts flake on `org-pkgs`, with a devenv CLI
shell and no flake `devShells` (the `external-systems` skill). uv2nix
fits it like this; full, tested files are in
[references/org-recipes.md](references/org-recipes.md).

**Inputs come from org-pkgs.** external-systems/pkgs pins
`pyproject-nix`, `uv2nix` and `pyproject-build-systems` (each following
the org nixpkgs), just as it pins `nixpkgs`. A Python repo follows them
in `flake.nix` and `devenv.yaml` and declares no URL of its own:

```nix
pyproject-nix.follows = "org-pkgs/pyproject-nix";
uv2nix.follows = "org-pkgs/uv2nix";
pyproject-build-systems.follows = "org-pkgs/pyproject-build-systems";
```

One pin then serves the org, and `nix flake update org-pkgs` +
`sync-locks` moves flake.lock and devenv.lock together. Bumping uv2nix
is a pkgs PR (`nix flake update pyproject-nix uv2nix
pyproject-build-systems` there), merged before consumers update
`org-pkgs`. Lock `org-pkgs` to pkgs `main` only; an unmerged pkgs
branch or commit is for local testing
(`--override-input org-pkgs github:external-systems/pkgs/SHA`), never
committed.

**Standalone Python repo** (the workspace is the repo):

```
pyproject.toml uv.lock src/NAME/ tests/      # the uv workspace, repo root
flake-parts/python.nix                       # packages + checks (import-tree)
flake-parts/_python/python-set.nix           # plain function: workspace -> sets, venvs
flake-parts/_python/overrides.nix            # fixup overlay
devenv.yaml devenv.nix                       # editable dev venv, same set
```

`_python/` is underscore-prefixed so import-tree skips it: those files
are plain Nix functions, not flake-parts modules. `python-set.nix` is
shared by the flake module and `devenv.nix`, so the shell and the build
use one Python set.

**A Python package in pkgs** (or any repo that ships many packages):
vendor the uv project next to the package file
(`pkgs/NAME/{package.nix,pyproject.toml,uv.lock,src/}`), write
`package.nix` as a `callPackage` function that takes `uv2nix`,
`pyproject-nix` and `pyproject-build-systems` as arguments, and wire it
in an input-closing overlay in `flake-parts/overlays.nix` (the plain
`overlays/*.nix` files close over no inputs). Package against the
consumer's nixpkgs: take `python313` from the callPackage scope.

**New project.** `uv init --package --name NAME .` inside the devenv
shell, where `UV_PYTHON` is the set's interpreter; outside it pass
`--python`, or uv writes `requires-python` from whatever Python is on
PATH. Its backend is `uv_build`, which builds and installs editable
with no overrides; hatchling needs `editables` added for the editable
venv (recipe).

## Tool loop

Inside the devenv shell (`uv`, `fmt`, `check` on PATH; outside it:
`devenv shell -- CMD`):

```sh
uv add httpx               # or edit pyproject.toml, then: uv lock
uv lock --upgrade-package httpx   # bump one dependency; uv lock --upgrade for all
git add -A                 # uv.lock untracked = "is not tracked by Git"
fmt && check               # check runs pytest + the uv-lock freshness check
nix build .#NAME -L && ./result/bin/NAME
```

- Re-enter the shell (or let devenv reload) after `uv add`; the editable
  venv is rebuilt from the new lock. Editing `.py` files needs nothing.
- `UV_NO_SYNC=1` keeps uv from creating `.venv`; uv only edits the lock.
  `uv run` and `uv sync` bypass the Nix venv: call the scripts directly
  (`pytest`, `NAME`).
- Pick up a newer uv2nix after its pkgs PR merges: `nix flake update
  org-pkgs`, then `sync-locks`, in one commit.
- Read `nix log /nix/store/...drv` for a failed package build; `-L`
  streams it.

## Debugging

The full symptom table with exact error text is
[references/debugging.md](references/debugging.md). The usual causes:

| Symptom | Fix |
|---|---|
| `assertion '(all (spec: ((pep440).comparators...` in `overlays.nix` | Interpreter outside `requires-python`: pick another `python3xx` (or `pythonVersion` arg) |
| `No sourcePreference was passed` | Pass `sourcePreference = "wheel"` |
| Backends built from source, slow first build | `pyproject-build-systems.overlays.default` is the sdist variant: use `.wheel` |
| `ModuleNotFoundError: No module named 'flit_core'` (any backend) in a package build | sdist with no build system: `resolveBuildSystem` in overrides, or prefer its wheel |
| `auto-patchelf could not satisfy dependency libX.so` | Wheel needs a native lib: `buildInputs = [pkgs.X]` |
| `No module named 'editables'` building the editable venv | hatchling member: add `editables` (recipe) |
| `Editable root was passed as a Nix store path` | `mkEditablePyprojectOverlay {root = "$DEVENV_ROOT";}` |
| `Two or more packages are trying to provide the same file` | `venvIgnoreCollisions` on the venv |
| New dependency missing at runtime, no error | Stale lock: `uv lock`, `git add uv.lock` |
| `attribute 'foo' missing` | Name not in the resolved lock for this platform/spec; check name, markers, extras |

## References

- [references/org-recipes.md](references/org-recipes.md): every file of
  the standalone layout, the pkgs overlay package, workspaces with several
  members, OCI images, the impure-shell alternative. Read before creating
  or restructuring a Python flake.
- [references/api.md](references/api.md): every uv2nix and
  pyproject.nix function and argument (`loadWorkspace`, the overlays,
  `deps`, the `tool.uv` settings honoured, `mkVirtualEnv`, `hacks`,
  `mkApplication`, PEP 723 scripts). Read when calling anything not in
  the recipes.
- [references/overrides.md](references/overrides.md): fixing packages
  (native libs, build systems, patches, nixpkgs prebuilt, Rust/maturin,
  private indexes, cross, platform quirks, conflicts, source filtering).
  Read when a package fails to build or run.
- [references/debugging.md](references/debugging.md): symptom, cause and
  fix for every failure seen, with the exact messages.
