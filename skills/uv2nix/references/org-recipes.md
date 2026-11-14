# uv2nix recipes for org repos

Verified on 2026-11-14 by moving andrewthomaslee/moscripts (four Typer
CLIs, pytest, `uv_build`) onto external-systems/pkgs
`flakeModules.python`: `nix run .#flake-check`, `vm-test --all --remote
--rebuild` and `devenv shell` passing. The module's source is
`flakeModules/python.nix` and `flakeModules/python/workspace.nix` in
pkgs; read them when an option below is not enough.

Contents: the repo files; module options and outputs; versioning
internals; `--version`; git dependencies; workspaces; a package vendored
in pkgs; shipping.

## The repo files

A Python repo is the org template plus the uv workspace. Nothing in
`flake.nix` is Python-specific: `org-pkgs.flakeModules.default` brings
`flakeModules.python`, which switches on when `pyproject.toml` and
`uv.lock` are at the root.

```yaml
# devenv.yaml
inputs:
  org-pkgs:
    url: github:external-systems/pkgs/<rev in flake.lock>   # sync-locks
  nixpkgs:
    follows: org-pkgs/nixpkgs
imports:
  - org-pkgs/devenv
  - org-pkgs/devenv/python
```

```nix
# devenv.nix: only what the repo's own commands need beyond the venv
{pkgs, ...}: {
  packages = [pkgs.gum pkgs.mpv];
}
```

```nix
# flake-parts/python.nix: only settings that differ (all optional)
_: {
  perSystem = {pkgs, ...}: {
    python = {
      runtimeInputs = [pkgs.gum pkgs.uv pkgs.mpv]; # programs the scripts exec (--suffix PATH)
      checkInputs = [pkgs.which];                  # extra PATH in the checks
    };
  };
}
```

```nix
# flake-parts/_python/overrides.nix: build fixups (references/overrides.md)
{pkgs}: _final: prev: {
  psycopg2 = prev.psycopg2.overrideAttrs (old: {
    buildInputs = (old.buildInputs or []) ++ [pkgs.libpq];
  });
}
```

`pyproject.toml` essentials:

```toml
[project]
name = "NAME"
version = "0.1.0"            # <major>.<minor>.0 = ci.yml major/minor
requires-python = ">=3.13"   # also ruff's target and ty's python-version

[project.scripts]
NAME = "NAME.cli:app"

[build-system]
requires = ["uv_build>=0.13,<0.14"]
build-backend = "uv_build"

[dependency-groups]
dev = ["pytest>=8"]          # never ruff, ty or pyrefly: they come from Nix
```

`.vscode/` comes from the pkgs template (references/toolchain.md).

## Module options and outputs

| Option | Default | Use |
|---|---|---|
| `python.enable` (top level) | `pyproject.toml` and `uv.lock` exist | off: no outputs, uv2nix never fetched |
| `python.vmTest.enable` (top level) | `true` | the generated `python-cli` VM test |
| `perSystem.python.runtimeInputs` | `[]` | programs the scripts exec; also on PATH in checks |
| `perSystem.python.checkInputs` | `[]` | extra PATH in the checks only |
| `perSystem.python.checks.<name>` | `{}` | shell script, run in a copy of the sources with the test venv: `checks.python-<name>` |
| `perSystem.python.overrides` | `flake-parts/_python/overrides.nix` if present | overlay or path |
| `perSystem.python.python` | first nixpkgs Python in `requires-python` | interpreter |
| `perSystem.python.ty.args` | `["--error-on-warning"]` | `[]` lets ty warnings pass |
| `perSystem.python.workspace` | read-only | the `mkWorkspace` result |

| Output | What |
|---|---|
| `packages.<project>`, `.default` | `mkApplication` wrapped with `makeWrapper` per script (Typer usage lines show the real name), `pname`/`version`/`meta` (`description`, `homepage` from `[project.urls]`, `mainProgram` for one script); a library (no scripts) is its venv |
| `packages.<project>-venv` | the shipped venv |
| `apps.<script>` | every `[project.scripts]` entry |
| `checks.python-pytest` | `pytest -p no:cacheprovider tests` on the installed (not editable) package, when `tests/` exists |
| `checks.python-ty` | `ty check --python <test venv> --error-on-warning` |
| `checks.python-uv-lock` | `uv lock --check --offline` (works with git dependencies) |
| `checks.python-version` | pyproject `X.Y.0` vs ci.yml `major`/`minor` |
| `checks.treefmt` | + `ruff-check` (`--fix`, priority 1) and `ruff-format` |
| `vmTests.python-cli` | every script `--version` (`^<project> \d+\.\d+\.\d+$`) and `--help` as user `alice` on an offline VM |
| `legacyPackages.python` | `pythonSet`, `shipSet`, `venv`, `testVenv` |

The checks copy only `pyproject.toml`, `uv.lock`, `README.md`,
`LICENSE`, `src`, `tests` and the workspace members' directories, so
docs and Nix edits do not rerun them.

## Versioning internals

- `shipSet` = `pythonSet` + the own projects stamped with
  `self.revCount`. The stamp rewrites the first `version = "..."` in the
  `[project]` table of the package's `pyproject.toml` in `postPatch`
  (the build backend reads it, so the wheel metadata agrees) and sets
  `version` (restating `src`, which silences nixpkgs' "overridden with
  version but not src" warning).
- Stamping uses static names: the own projects and git dependencies come
  from `uv.lock` (`source.editable`, `source.git`). Deciding from the
  derivations (`drv.src ? revCount`) recurses through the overlay.
- `self.revCount` exists for a clean git checkout and `git+https`/`git+ssh`
  inputs, not for `github:` inputs, a dirty tree, or a build with
  `--override-input` (the changed lock makes the tree dirty). To test
  stamping against an unmerged pkgs, lock it
  (`nix flake lock --override-input org-pkgs git+file:///path/to/pkgs?rev=SHA`),
  commit locally, build, and reset before pushing.
- `checks.python-version` reads `major:`/`minor:` lines from
  `.github/workflows/ci.yml` (no YAML parser in Nix) and passes with a
  message when there is no ci.yml.

## --version

Every CLI answers `--version` with `<project> <version>` from
`importlib.metadata`. Typer, without turning a single command into a
group:

```python
# NAME/utilities.py
from importlib.metadata import version as dist_version
from typing import Annotated

import typer


def _print_version(value: bool | None) -> None:
    if value:
        typer.echo(f"NAME {dist_version('NAME')}")
        raise typer.Exit


VersionOption = Annotated[
    bool | None,
    typer.Option("--version", callback=_print_version, is_eager=True,
                 help="Show the version and exit."),
]

# every command:
@app.command()
def main(_version: VersionOption = None, ...) -> None: ...
```

Test it with `typer.testing.CliRunner().invoke(app, ["--version"])`.
Write Typer parameters as `Annotated[T, typer.Option(...)] = default`:
ruff's default B008 flags `param: Path = Option(Path(...))`.

## Git dependencies (an org library in another repo)

```sh
uv add git+https://github.com/OWNER/mylib --tag 0.3.41
```

```toml
dependencies = ["mylib"]
[tool.uv.sources]
mylib = { git = "https://github.com/OWNER/mylib", tag = "0.3.41" }
```

- `uv.lock` records `source = { git = "...?tag=0.3.41#<sha>" }` with
  version `0.3.0` (the source's pyproject).
- uv2nix fetches it with `builtins.fetchGit {url; rev; allRefs = true;
  submodules = true;}` (eval time, pure: the rev is locked), which
  returns `revCount`. The builder stamps git dependencies whose GitHub
  owner is in `stampOwners` (`external-systems`, `andrewthomaslee`)
  with that count, so the venv reports `0.3.41`.
- Transitive git sources are followed by uv (verified: app → liba (git)
  → libc (git, declared only in liba)).
- Private repos: git credentials, not Nix `access-tokens` (verified:
  the Nix git fetcher ignores them). Locally `gh auth setup-git`; in CI
  the org workflow points git at the `private-repos` token.
- Co-developing: `mylib = { path = "../mylib", editable = true }` for a
  while, never committed (uv2nix rejects paths outside the flake).

## Workspaces with several members

```toml
# root pyproject.toml
[tool.uv.workspace]
members = ["packages/*"]
```

- One `uv.lock` at the root. Every non-virtual member gets
  `packages.<member>` (scripts wrapped, or a venv for a library) and its
  scripts' apps; `packages.default` is the root project, else the first
  member. Members' directories join the check sources.
- Members depend on each other with
  `[tool.uv.sources] lib-a = {workspace = true;}`; keep those
  dependencies unversioned (stamped versions would not match a `>=`).
- A member with `[tool.uv] package = false` is virtual: kept in the set
  for its dependencies, never built or made editable.
- ty does not read the editable `.pth` files: list members outside
  `./src` in `[tool.ty.environment] root` (references/toolchain.md).
- The devenv shell makes every member editable from its `src/`; members
  without `src/` keep their full source (rebuilt on edits).

## A third-party Python app vendored in pkgs

Vendor the uv project next to the package file:
`pkgs/NAME/{package.nix,pyproject.toml,uv.lock,src/}`. For a third-party
app, vendor a thin wrapper project instead: `uv init --bare` (a
`pyproject.toml` with no build system, which uv locks as a virtual
project), `uv add "app==1.2.3"`, and pass the app itself as `package`
(`pythonSet.app`): `mkApplication` links only the named package's files,
and the wrapper has none. Set `meta.mainProgram` by hand then:
pyproject.nix sets it only for a local project with exactly one
`[project.scripts]` entry.

`pkgs/hello-uv/package.nix` (built as an overlay against the org
nixpkgs):

```nix
# hello-uv: a uv project vendored next to this file (pyproject.toml,
# uv.lock, src/), built with uv2nix against the consumer's nixpkgs.
{
  lib,
  callPackage,
  callPackages,
  python313,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}: let
  workspace = uv2nix.lib.workspace.loadWorkspace {workspaceRoot = ./.;};

  pythonSet =
    (callPackage pyproject-nix.build.packages {python = python313;}).overrideScope
    (lib.composeManyExtensions [
      pyproject-build-systems.overlays.wheel
      (workspace.mkPyprojectOverlay {sourcePreference = "wheel";})
    ]);

  inherit (callPackages pyproject-nix.build.util {}) mkApplication;
in
  (mkApplication {
    venv = pythonSet.mkVirtualEnv "hello-uv-env" workspace.deps.default;
    package = pythonSet.hello-uv;
  }).overrideAttrs (old: {
    meta = (old.meta or {}) // {description = "uv2nix demo app";};
  })
```

Wire it where overlays close over inputs. In pkgs that is
`flake-parts/overlays.nix` (the `overlays/*.nix` files are input-free),
pattern only, not built in pkgs yet:

```nix
pythonApps = final: _prev: {
  hello-uv = final.callPackage ../pkgs/hello-uv/package.nix {
    inherit (inputs) uv2nix pyproject-nix pyproject-build-systems;
  };
};
```

Add it to `flake.overlays.default`'s list, export it, and list it in
`flake-parts/packages.nix`. Inside pkgs the three are its own inputs
(`inputs.uv2nix` etc.); overlays are lazy, so consumers that never read
the package never fetch them.

## Shipping

OCI image (pattern; `dockerTools` from nixpkgs):

```nix
packages.hello-uv-image = pkgs.dockerTools.buildLayeredImage {
  name = "hello-uv";
  contents = [config.packages.hello-uv];
  config.Cmd = [(lib.getExe config.packages.hello-uv)];
};
```

(`config` from the `perSystem` arguments.) For many images or skopeo
pushes, see the `kubenix` skill.

NixOS service: `ExecStart = lib.getExe pkgs.hello-uv;` with the package
from the repo's overlay; the venv is self-contained, so no
`PYTHONPATH`/`environment` setup.

Wheels or sdists for PyPI: `pythonSet.hello-uv.override {pyprojectHook
= pythonSet.pyprojectDistHook;}` puts the wheel in `$out` (api.md,
"Distributions").
