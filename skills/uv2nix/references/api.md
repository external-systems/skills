# uv2nix and pyproject.nix API

Read from source at uv2nix `c361746` (`lib/workspace.nix`,
`lib/overlays.nix`, `lib/build.nix`, `lib/scripts.nix`) and
pyproject.nix `d43f0e7` (`build/packages.nix`, `build/util/`,
`build/hacks/`). When an argument here disagrees with a newer clone,
the clone wins: fix this file.

## Flake outputs used

| Flake | Output | What |
|---|---|---|
| uv2nix | `lib.workspace`, `lib.scripts` | The API below. Also `lib.lock1` (uv.lock parser), `lib.overlays`, `lib.build` (internals) |
| uv2nix | `packages.SYSTEM.uv-bin` | Prebuilt uv, only for nixpkgs older than 24.11 |
| uv2nix | `templates.{hello-world,hello-tkinter,inline-metadata}` | Upstream starting points (plain flakes, not org style) |
| pyproject-nix | `build.packages` | callPackage-able base scope |
| pyproject-nix | `build.util` | `mkApplication` |
| pyproject-nix | `build.hacks` | `nixpkgsPrebuilt`, `importCargoLock`, `toNixpkgs` |
| pyproject-nix | `lib.util.filterPythonInterpreters`, `lib.pep440`, `lib.pep508` | Interpreter selection, version and marker helpers |
| pyproject-nix | `packages.SYSTEM.build-editable` | Rebuild compiled editables in the shell |
| pyproject-build-systems | `overlays.{wheel,sdist,default}` | Build backends from wheels or from sdists. `default` is `sdist` (slower, builds backends from source): name `wheel` explicitly |

## uv2nix.lib.workspace.loadWorkspace

```nix
workspace = uv2nix.lib.workspace.loadWorkspace {
  workspaceRoot = ./.;        # path (or string with context); never filtered
  config = {};                # attrset or (cfg: cfg // {...}) over loadConfig's result
  # uvLock = lib.importTOML (workspaceRoot + "/uv.lock");      default
  # pyproject = lib.importTOML (workspaceRoot + "/pyproject.toml");  default
};
```

Returns:

- `mkPyprojectOverlay {...}`: the lock as an overlay (below).
- `mkEditablePyprojectOverlay {...}`: editable members (below).
- `deps.{default,optionals,groups,all}`: specs over every workspace
  member. `default` is no extras and no groups except each member's
  `tool.uv.default-groups`. Members pulled in by a `{path = ...}` source
  are not workspace members and are absent from `deps`.
- `config`: the merged settings (below).
- `requires-python`: parsed from uv.lock.

### Settings read from pyproject.toml (`loadConfig`)

uv2nix honours these `[tool.uv]` keys, merged across members; set them
in `pyproject.toml` rather than in Nix, so uv and Nix agree:

| Key | Effect |
|---|---|
| `no-build = true` | Wheels only; becomes the default `sourcePreference` |
| `no-binary = true` | sdists only |
| `no-build-package = [..]` / `no-binary-package = [..]` | Per-package wheel or sdist (overrides `sourcePreference`) |
| `extra-build-dependencies.PKG = [..]` | Build systems added to PKG's sdist build; uv uses them too |
| `extra-build-variables.PKG = {..}` | Env vars for PKG's build derivation |
| `config-settings` / `config-settings-package.PKG` | PEP 517 `--config-setting` flags |
| `compile-bytecode = false` | Skip `.pyc` (default true) |

Precedence for one package's source: `no-build` > `no-binary` >
`no-binary-package` > `no-build-package` > `sourcePreference`. A package
in both per-package lists fails eval.

## workspace.mkPyprojectOverlay

```nix
overlay = workspace.mkPyprojectOverlay {
  sourcePreference = "wheel";      # "wheel" | "sdist"; required unless inferred
  environ = {};                    # PEP 508 overrides, e.g. {platform_release = "5.10.65";}
  dependencies = workspace.deps.all;   # spec used to pick conflict branches
  pythonVersion = null;            # e.g. "3.13.0": override version for requires-python + markers
};
```

- Resolves the lock for the set's interpreter and platform (PEP 508
  markers), producing one attribute per package that applies. Packages
  excluded by markers are absent (`attribute 'x' missing`).
- Asserts `requires-python` and `[tool.uv] environments` /
  `required-environments` against the interpreter at eval.
- Cross-compiling: also overrides `pythonPkgsBuildHost` automatically.
- Each package derivation has `passthru.{dependencies,
  optional-dependencies, dependency-groups}`; remote packages also
  `passthru.{package, format}` (`format` is `"wheel"` or `"pyproject"`,
  handy to see what was chosen:
  `nix eval .#legacyPackages.x86_64-linux.pythonSet.foo.passthru.format`).
- Remote packages accept `.override {sourcePreference = "sdist";}`.
- Sources: PyPI or another registry (fetchurl with the lock's hash), URL,
  git (`builtins.fetchGit` with submodules; needs network at eval,
  pure in flakes because the rev is locked), local path or local wheel.

## workspace.mkEditablePyprojectOverlay

```nix
workspace.mkEditablePyprojectOverlay {
  root = "$DEVENV_ROOT";   # string, absolute non-store path or env var; required in flakes
  members = ["a" "b"];     # default: every non-virtual member
}
```

Apply on top of the full set (`pythonSet.overrideScope ...`). The env
var is kept literally in the installed `.pth` and expanded by Python at
import time. Members in parent directories of the root get `..` paths.

## pyproject-nix.build.packages: the base scope

```nix
base = pkgs.callPackage pyproject-nix.build.packages {
  python = pkgs.python313;
  # stdenv = pkgs.stdenv.override {...};   platform quirks
};
```

A `makeScope` set with no Python packages. Attributes:

- `python`, `pkgs`, `stdenv`
- `mkVirtualEnv NAME SPEC`: venv derivation. Override attributes with
  `.overrideAttrs`: `venvSkip = ["LICENSE"]` (paths not linked),
  `venvIgnoreCollisions = ["lib/python3.13/site-packages/foo"]` (or
  `["*"]`; first one wins).
- `resolveBuildSystem SPEC`: list of build-system derivations, for
  `nativeBuildInputs`. An empty spec falls back to setuptools + wheel.
- `resolveVirtualEnv SPEC`: flat package list for a spec (cycles OK).
- `pythonPkgsBuildHost`, `pythonPkgsHostHost`: build/host sets; aliases
  of the set itself when not cross-compiling.
- Hooks: `pyprojectHook` (sdist build), `pyprojectWheelHook` (install a
  wheel), `pyprojectEditableHook`, `pyprojectDistHook`,
  `pyprojectMakeVenvHook`, and their parts.

## pyproject-nix.build.util.mkApplication

```nix
inherit (pkgs.callPackages pyproject-nix.build.util {}) mkApplication;
app = mkApplication {
  venv = pythonSet.mkVirtualEnv "app-env" workspace.deps.default;
  package = pythonSet.app;
  # pname, version default to package's
};
```

Symlinks only the files `package` itself installed (bin, share, man
pages, systemd units) from the venv, so no interpreter, activate
scripts or `pyvenv.cfg` at top level; scripts still run in the venv.
Inherits `meta` and `passthru` from `package`. Add shell completions
with `.overrideAttrs` + `installShellFiles` in `postInstall`.

## pyproject-nix.build.hacks

```nix
hacks = pkgs.callPackage pyproject-nix.build.hacks {};
```

- `nixpkgsPrebuilt {from = python.pkgs.foo; prev = prev.foo;}`: use a
  nixpkgs-built package in place of the locked one (`prev` optional;
  keeps the lock's dependency metadata, which you may filter in
  `passthru.dependencies`). The nixpkgs interpreter must match `python`.
- `importCargoLock {prev = prev.foo; cargoRoot = "src/rust";}`: vendor
  Cargo deps for an sdist Rust extension (uses IFD for remote sources).
- `toNixpkgs {pythonSet; packages = ["urllib3"];}`: the reverse, an
  overlay for nixpkgs `python.override {packageOverrides = ...;}`.

## Distributions (wheels and sdists)

- `pythonSet.foo.overrideAttrs (_: {outputs = ["out" "dist"];})`: normal
  install plus the wheel in `$dist`.
- `pythonSet.foo.override {pyprojectHook = pythonSet.pyprojectDistHook;}`:
  `$out` is only the wheel (not usable in a venv). Add
  `.overrideAttrs (_: {env.uvBuildType = "sdist";})` for an sdist.
- Builds fail if a Nix store path leaks into the wheel.

## PEP 723 scripts (uv2nix.lib.scripts.loadScript)

For single-file scripts with `# /// script` metadata locked by
`uv lock --script foo.py` (writes `foo.py.lock`):

```nix
script = uv2nix.lib.scripts.loadScript {script = ./scripts/foo.py;};
pythonSet = base.overrideScope (lib.composeManyExtensions [
  pyproject-build-systems.overlays.wheel
  (script.mkOverlay {sourcePreference = "wheel";})
]);
exe = pkgs.writeScript script.name (script.renderScript {
  venv = script.mkVirtualEnv {inherit pythonSet;};
});
```

`lockPath` defaults to `script + ".lock"`; `config` as for workspaces.
Upstream template: `nix flake init -t github:pyproject-nix/uv2nix#inline-metadata`.

## Old nixpkgs

The org nixpkgs is unstable and recent, so this never applies in org
repos: nixpkgs at 24.11 or older needs `uv = uv2nix.packages.SYSTEM.uv-bin`
in an overlay (the hooks need uv >= 0.5.7).
