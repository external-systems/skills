---
name: uv2nix
description: "Python in the org: uv2nix and pyproject.nix builds of a uv workspace (pyproject.toml + uv.lock) through external-systems/pkgs flakeModules.python and the org-pkgs/devenv/python shell, the Astral toolchain (uv, ruff, ty), release-number versioning and --version, consuming org Python packages (flake inputs, uv git sources), VS Code/VSCodium and nixd setup, overrides for native libs and sdist build systems, and debugging failed builds. Load whenever Python meets Nix: a Python app, CLI or library, a pyproject.toml or uv.lock, a Python dev shell or editor setup, ruff or ty findings, or uv2nix/pyproject.nix errors."
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

Facts below were verified on 2026-11-14 against uv2nix `c361746`,
pyproject.nix `d43f0e7`, the org nixpkgs (uv 0.13.5, ruff 0.17.2,
ty 0.0.91, python313 3.13.16), devenv 2.4 and Nix 2.34, by moving
andrewthomaslee/moscripts onto `flakeModules.python` end to end.

## Pick the tool first

| Need | Use |
|---|---|
| An org Python app, CLI, library or service | a uv workspace + `flakeModules.python` (this skill) |
| A dev shell whose venv matches the Nix build exactly | `org-pkgs/devenv/python` (editable uv2nix venv) |
| A third-party Python app packaged in pkgs | a vendored uv project + `package.nix` (headroom) |
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

Every org Python project is a uv workspace at a repo root, built by
external-systems/pkgs **`flakeModules.python`** (part of
`flakeModules.default`) and edited in the **`org-pkgs/devenv/python`**
shell. Both use one builder, `lib.python.mkWorkspace`
(`flakeModules/python/workspace.nix` in pkgs), bound to pkgs' own
uv2nix, pyproject.nix and build-system-pkgs pins. A Python repo declares
**no** uv2nix input and writes almost no Nix:

```
pyproject.toml uv.lock src/NAME/ tests/   # the uv workspace, repo root
flake-parts/python.nix                    # optional: perSystem.python settings
flake-parts/_python/overrides.nix         # optional: {pkgs}: final: prev: {...}
devenv.yaml                               # imports org-pkgs/devenv + org-pkgs/devenv/python
.vscode/settings.json, extensions.json    # from the pkgs template
```

The module switches itself on when `pyproject.toml` and `uv.lock` exist
and gives `packages.<project>`/`.default` (scripts wrapped, `pname`,
`version`, `meta`), `apps.<script>`, `checks.python-{pytest,ty,uv-lock,
version}`, ruff in `checks.treefmt`, `vmTests.python-cli` and
`legacyPackages.python`. Generated packages and apps are `mkDefault`: a
repo that defines one itself wins. Settings, options and the full file
set: [references/org-recipes.md](references/org-recipes.md). The pkgs
docs page `documentation/docs/python.md` is the human version.

**The Astral toolchain**, one version of each, the org nixpkgs':

- **uv** edits `uv.lock` only; the venv is Nix's (`UV_NO_SYNC`,
  `UV_PROJECT_ENVIRONMENT` = the Nix venv, no downloads).
- **ruff** lints and formats through treefmt (`fmt`, `checks.treefmt`)
  with Astral's default rules: no `select`, only `extend-select`.
- **ty** type-checks (`checks.python-ty`, warnings fail; `python.ty.args`)
  and is the editor language server (VS Code and VSCodium, no Pylance).
- Never put ruff, ty or pyrefly in a uv dependency group: the editor
  would pick the PyPI copy and disagree with CI.

Editors, nixd and ty's import resolution:
[references/toolchain.md](references/toolchain.md).

**Versions follow the org release number**
`<major>.<minor>.<git rev-list --count HEAD>`:

- `pyproject.toml` holds `"<major>.<minor>.0"`, matching `major`/`minor`
  in `.github/workflows/ci.yml` (`checks.python-version`).
- The shipped set stamps the patch from the flake's `self.revCount`
  (store name, wheel metadata, `importlib.metadata`). Checks build the
  unstamped set. `github:` inputs and dirty trees have no revCount and
  keep `X.Y.0`; consumers wanting the exact number use `git+https://`.
- Every CLI answers `--version` with `<project> <version>`; the
  `python-cli` VM test asserts it. The Typer pattern is in
  [references/org-recipes.md](references/org-recipes.md).

**Consuming org Python packages:**

| Consumer | How |
|---|---|
| Nix config (an app, a CLI, a service) | pkgs takes the repo as `git+https://github.com/OWNER/REPO?ref=main` with `inputs.org-pkgs.follows = ""` and names the package in its overlay (static names: never merge the repo's whole overlay) |
| Python code in another repo (a library) | `uv add git+https://github.com/OWNER/REPO --tag RELEASE`: a uv git source pinned in `uv.lock`, no flake input. uv2nix stamps it from its fetched commit count |

- Libraries reach Python code through `uv.lock` only, never a flake
  overlay (two resolutions, last overlay wins, double bumps).
- Keep the dependency line unversioned (`"mylib"`); the tag is the pin.
  uv reads `X.Y.0` from the source and rejects `mylib>=X.Y.N`.
- uv follows a git dependency's own git sources (a library on another
  org library): consumers do not repeat them.
- Private repos: `gh auth setup-git` locally; CI gives git the
  `private-repos` token (Nix's git fetcher ignores `access-tokens`).

**A vendored third-party Python app in pkgs** (headroom): vendor the uv
project next to the package file
(`pkgs/NAME/{package.nix,pyproject.toml,uv.lock}`), write `package.nix`
as a `callPackage` function taking `uv2nix`, `pyproject-nix` and
`pyproject-build-systems`, and wire it in the input-closing overlay in
`flake-parts/overlays.nix`. Its version is upstream's; no stamping.

**Start a Python repo** (or add Python to an org repo):

1. `nix flake init -t github:external-systems/pkgs` (new repo only);
   uncomment `org-pkgs/devenv/python` in `devenv.yaml`.
2. Create the uv project. The devenv shell cannot evaluate before
   `uv.lock` exists, so take uv and the interpreter from the org
   nixpkgs:

   ```sh
   nix shell --inputs-from . nixpkgs#uv nixpkgs#python313 -c sh -c '
     export UV_NO_SYNC=1 UV_PYTHON_DOWNLOADS=never
     uv init --package --name NAME --python "$(command -v python3.13)" .
     uv version 0.1.0   # <major>.<minor>.0 of ci.yml
     uv add --dev pytest'
   ```

   Without `--python`, uv writes `requires-python` from whatever Python
   is on PATH. Keep the `uv_build` backend: it builds and installs
   editable with no overrides.
3. Add `--version` to every script (the Typer pattern), and
   `flake-parts/python.nix` only if the scripts exec programs
   (`runtimeInputs`).
4. `git add -A`, `fmt`, `check`, `vm-test python-cli --remote`.

Done when `check` is green (ruff, ty, pytest, uv-lock, version ran),
`nix run .#SCRIPT -- --version` prints `NAME X.Y.0` (a dirty tree) and in
`devenv shell` `python -c 'import NAME; print(NAME.__file__)'` prints a
path in the repo, not in `/nix/store`.

## Tool loop

Inside the devenv shell (`uv`, `ruff`, `ty`, `fmt`, `check` on PATH;
outside it: `devenv shell -- CMD`):

```sh
uv add httpx               # or edit pyproject.toml, then: uv lock
uv lock --upgrade-package httpx   # bump one dependency; uv lock --upgrade for all
pytest && ty check         # fast loop in the shell
git add -A                 # uv.lock untracked = "is not tracked by Git"
fmt && check               # ruff, ty, pytest, uv-lock, version, docs
nix build && ./result/bin/SCRIPT --version
vm-test python-cli --remote --rebuild
```

- Editing `.py` files rebuilds nothing; `uv add` rebuilds the venv on
  the next shell entry.
- `uv run` uses the Nix venv (`UV_PROJECT_ENVIRONMENT`); `uv sync` cannot
  write the store and fails loudly. Call scripts directly.
- Pick up a newer uv2nix, ruff or ty after their pkgs PR merges:
  `nix flake update org-pkgs`, then `sync-locks`, in one commit. A ty
  bump can add diagnostics (beta, 0.0.x): fix them in that PR.
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
| `Editable root was passed as a Nix store path` | `mkEditablePyprojectOverlay {root = "/abs/checkout";}` (a non-store string; the org devenv module passes `config.devenv.root`) |
| `Two or more packages are trying to provide the same file` | `venvIgnoreCollisions` on the venv |
| New dependency missing at runtime, no error | Stale lock: `uv lock`, `git add uv.lock` |
| `attribute 'foo' missing` | Name not in the resolved lock for this platform/spec; check name, markers, extras |
| Package or `--version` stuck at `X.Y.0` | No `self.revCount`: a `github:` input (use `git+https`), a dirty tree, or `--override-input` |
| ty `unresolved-import` on a workspace member | ty ignores editable `.pth` files: add the member's `src` to `[tool.ty.environment] root` |

## References

- [references/org-recipes.md](references/org-recipes.md): the module's
  options and outputs, the repo files, `--version`, versioning internals,
  git dependencies, workspaces, the pkgs vendored package, shipping. Read
  before creating or restructuring a Python repo.
- [references/toolchain.md](references/toolchain.md): ty, ruff and uv
  settings, VS Code / VSCodium (extensions, interpreter, language
  server; the repo `.vscode/` and the user-level
  `homeSpec.programs.vscodium` defaults), nixd. Read when an editor, a linter or the type checker
  misbehaves or a repo's editor setup is created.
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
