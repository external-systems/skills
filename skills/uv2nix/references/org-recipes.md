# uv2nix recipes for org repos

Every Nix file here except the ones marked otherwise was built and run
on 2026-11-09 in a demo repo (`hello-uv`: httpx + rich, a pytest group,
`uv_build`), with `nix flake check`, `nix run` and `devenv shell`
passing. Replace `hello-uv` with the project name (the `[project] name`,
which is also the attribute in `pythonSet`).

Contents: inputs; standalone repo files; the devenv shell (pure and
impure); a package in pkgs; workspaces with several members; shipping
(OCI image, NixOS service, wheels).

## Inputs

external-systems/pkgs pins the three inputs (each following its
nixpkgs). `flake.nix` follows them, below the template's org inputs,
and locks nothing new:

```nix
inputs = {
  org-pkgs.url = "github:external-systems/pkgs";
  nixpkgs.follows = "org-pkgs/nixpkgs";
  flake-parts.follows = "org-pkgs/flake-parts";
  import-tree.follows = "org-pkgs/import-tree";

  # Python (uv2nix): the org pins from external-systems/pkgs.
  pyproject-nix.follows = "org-pkgs/pyproject-nix";
  uv2nix.follows = "org-pkgs/uv2nix";
  pyproject-build-systems.follows = "org-pkgs/pyproject-build-systems";
};
```

Then `nix flake lock` and `git add flake.lock`. `org-pkgs` stays on pkgs
`main`: to try an unmerged pkgs change, pass
`--override-input org-pkgs github:external-systems/pkgs/SHA` on the
command line, and never commit that lock. A newer uv2nix arrives as a
pkgs PR; after it merges, `nix flake update org-pkgs` + `sync-locks`.

## Standalone repo

The uv workspace is the repo root: `pyproject.toml`, `uv.lock`,
`src/hello_uv/`, `tests/`. Create it with
`uv init --package --name hello-uv .`, then `uv add` /
`uv add --dev pytest`.

### flake-parts/_python/python-set.nix

A plain function (not a module: the `_` keeps import-tree out), shared by
the flake module and devenv.

```nix
# The uv workspace at the repo root as a pyproject.nix Python set. A
# plain function, shared by flake-parts/python.nix (packages, checks)
# and devenv.nix (the editable dev venv), so both build one set.
{
  pkgs,
  lib,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}: let
  workspace = uv2nix.lib.workspace.loadWorkspace {workspaceRoot = ../..;};

  python = pkgs.python313;

  pythonSet =
    (pkgs.callPackage pyproject-nix.build.packages {inherit python;}).overrideScope
    (lib.composeManyExtensions [
      pyproject-build-systems.overlays.wheel
      (workspace.mkPyprojectOverlay {sourcePreference = "wheel";})
      (import ./overrides.nix {inherit pkgs;})
    ]);

  # Workspace members installed as pointers into $DEVENV_ROOT, expanded
  # by Python at import time: edits apply without a rebuild.
  editableSet = pythonSet.overrideScope (workspace.mkEditablePyprojectOverlay {
    root = "$DEVENV_ROOT";
  });
in {
  inherit workspace python pythonSet editableSet;
  venv = pythonSet.mkVirtualEnv "hello-uv-env" workspace.deps.default;
  devVenv = editableSet.mkVirtualEnv "hello-uv-dev-env" workspace.deps.all;
}
```

- `workspaceRoot` is an unfiltered path. Filtering it
  (`lib.cleanSource`, `filterSource`) turns every read into
  import-from-derivation and breaks editables; filter per package
  instead (overrides.md, "Source filtering").
- `python`: choose an interpreter inside the lock's `requires-python`.
  To derive it:
  `lib.head (pyproject-nix.lib.util.filterPythonInterpreters {inherit (workspace) requires-python; inherit (pkgs) pythonInterpreters;})`.
- A member built with **hatchling** (or another backend that builds
  editables through the `editables` package) fails the editable build
  with `No module named 'editables'`. Compose a fix after the editable
  overlay:

  ```nix
  editableSet = pythonSet.overrideScope (lib.composeManyExtensions [
    (workspace.mkEditablePyprojectOverlay {root = "$DEVENV_ROOT";})
    # hatchling builds editables through the `editables` package, which
    # uv.lock never lists.
    (final: prev: {
      hello-uv = prev.hello-uv.overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem {editables = [];};
      });
    })
  ]);
  ```

### flake-parts/_python/overrides.nix

```nix
# Build fixups uv.lock cannot express: native libraries for wheels,
# build systems for sdists. Plain overlay over the Python set.
{pkgs}: _final: _prev: {}
```

Grows entries like `foo = prev.foo.overrideAttrs (old: {...});`
(overrides.md). Once an entry needs `final`, rename `_final` to `final`
(deadnix flags unused names otherwise; `pkgs` unused is fine as a
formal).

### flake-parts/python.nix

```nix
# Packages and checks from the uv workspace (flake-parts/_python/).
{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    py = import ./_python/python-set.nix {
      inherit pkgs lib;
      inherit (inputs) uv2nix pyproject-nix pyproject-build-systems;
    };
    inherit (pkgs.callPackages inputs.pyproject-nix.build.util {}) mkApplication;
    testVenv = py.pythonSet.mkVirtualEnv "hello-uv-test-env" py.workspace.deps.all;

    # Only what the checks read, so docs or Nix edits do not rerun them.
    # Add each workspace member's pyproject.toml when there are several.
    checkSrc = lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions [../pyproject.toml ../uv.lock ../src ../tests];
    };
  in {
    packages = {
      # The app alone: bin/, share/ and the package, no venv cruft.
      hello-uv = mkApplication {
        inherit (py) venv;
        package = py.pythonSet.hello-uv;
      };
      hello-uv-venv = py.venv;
    };

    checks = {
      pytest = pkgs.runCommand "hello-uv-pytest" {nativeBuildInputs = [testVenv];} ''
        cd ${checkSrc}
        pytest -p no:cacheprovider tests
        touch $out
      '';
      # uv.lock still matches pyproject.toml. uv2nix builds a stale lock
      # without complaint, silently missing new dependencies.
      uv-lock = pkgs.runCommand "hello-uv-uv-lock" {nativeBuildInputs = [pkgs.uv];} ''
        cp -r ${checkSrc}/. . && chmod -R u+w .
        export HOME=$TMPDIR UV_NO_CACHE=1 UV_PYTHON_DOWNLOADS=never
        uv lock --check --offline --python ${py.python.interpreter}
        touch $out
      '';
    };

    # For inspection: nix eval .#legacyPackages.x86_64-linux.pythonSet.httpx.version
    legacyPackages.pythonSet = py.pythonSet;
  };
}
```

- `mkApplication` keeps the package's `meta`; pyproject.nix sets
  `mainProgram` when the project has exactly one `[project.scripts]`
  entry, so `nix run .#hello-uv` works. With several scripts, set it in
  an `overrideAttrs`.
  Expose the venv too when users need `python` with the deps.
- `uv lock --check --offline` runs in the sandbox with no network or
  cache: an up-to-date lock passes, a stale one fails. It is the only
  guard against the silent stale-lock build.
- pytest runs from the store copy against the installed package (not
  editable), so it tests what ships. `-p no:cacheprovider` because the
  source is read-only.
- Checks are built by `nix flake check` (org CI `ci / flake-check`), so
  keep them offline and hermetic.

## The devenv shell

### Pure: the uv2nix editable venv (verified)

`devenv.yaml`: the template's inputs plus the three org pins:

```yaml
inputs:
  org-pkgs:
    url: github:external-systems/pkgs
  nixpkgs:
    follows: org-pkgs/nixpkgs
  pyproject-nix:
    follows: org-pkgs/pyproject-nix
  uv2nix:
    follows: org-pkgs/uv2nix
  pyproject-build-systems:
    follows: org-pkgs/pyproject-build-systems
imports:
  - org-pkgs/devenv
```

`devenv.nix`:

```nix
# The editable uv2nix venv: hello-uv and every dependency group on PATH,
# workspace sources live from $DEVENV_ROOT. uv edits the lock only.
{
  pkgs,
  lib,
  inputs,
  ...
}: let
  py = import ./flake-parts/_python/python-set.nix {
    inherit pkgs lib;
    inherit (inputs) uv2nix pyproject-nix pyproject-build-systems;
  };
in {
  packages = [py.devVenv pkgs.uv];

  env = {
    UV_NO_SYNC = "1";
    UV_PYTHON = py.python.interpreter;
    UV_PYTHON_DOWNLOADS = "never";
  };

  # nixpkgs Python setup hooks leak PYTHONPATH; it beats the venv.
  enterShell = "unset PYTHONPATH";
}
```

- `$DEVENV_ROOT` is set by devenv; the `.pth` files keep the literal
  `$DEVENV_ROOT/src` and Python expands it at import time. A store path
  as root is refused at eval.
- Leave `languages.python` off: it would add its own interpreter and
  venv in front of this one.
- Both locks resolve the three inputs through `org-pkgs`, so
  `sync-locks` (which re-pins devenv.yaml's `org-pkgs` to flake.lock's
  rev) keeps uv2nix identical in the shell and the build.
- Meson-python, Cython or other compiled editables: add
  `inputs.pyproject-nix.packages.${pkgs.stdenv.system}.build-editable`
  to `packages` and run `build-editable` in `enterShell` (rebuilds the
  in-tree `.so` files).

### Impure: devenv runs `uv sync` (not built in the demo)

For a repo that ships nothing through Nix, or where the dev shell may
differ from the build. Options from devenv 2.x `languages.python`:

```nix
{pkgs, ...}: {
  languages.python = {
    enable = true;
    package = pkgs.python313;
    uv = {
      enable = true;
      sync = {
        enable = true;
        allGroups = true;
      };
    };
  };
}
```

uv then owns `.venv` (gitignored) and downloads wheels at shell entry.
Wheels with native code may need `languages.python.manylinux.enable` or
`libraries`. Use `uv run` freely in this mode only.

devenv also has `config.languages.python.import ./path {}`, a
one-line uv2nix build (wheel preference, `deps.default`, no overrides
hook, `pyproject-build-systems.overlays.default`). It is fine for a
throwaway output; the flake recipe above is the org pattern because it
takes overrides and exposes the set.

## A Python package in pkgs (or any multi-package repo)

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

## Workspaces with several members

```toml
# root pyproject.toml
[tool.uv.workspace]
members = ["packages/*"]
```

- One `uv.lock` at the root; `loadWorkspace {workspaceRoot = ../..;}`
  finds every member. A root without `[project]` is a virtual root and
  is not itself a package.
- `workspace.deps.*` covers every member. For one app's venv name it:
  `pythonSet.mkVirtualEnv "api-env" {api = [];}`, then
  `mkApplication {venv; package = pythonSet.api;}`.
- Members depend on each other with
  `[tool.uv.sources] lib-a = {workspace = true;}`; uv2nix builds the
  local member.
- A member with `[tool.uv] package = false` is virtual: kept in the set
  for its dependencies, never built or made editable.
- Add each member's `pyproject.toml` and sources to `checkSrc`.

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
