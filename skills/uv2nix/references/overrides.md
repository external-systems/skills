# Overriding packages

uv.lock knows versions, hashes and Python dependencies. It does not know
native libraries or (for sdists) build systems, and uv2nix ships no
override collection. Every fix goes in the overrides overlay
(`flake-parts/_python/overrides.nix` in the org layout), composed
**after** the lock overlay:

```nix
{pkgs}: final: prev: {
  foo = prev.foo.overrideAttrs (old: {
    # ...
  });
}
```

Rules that apply to every recipe:

- Append, never replace: `(old.buildInputs or []) ++ [...]`,
  `old.nativeBuildInputs ++ ...`. Replacing drops the hooks uv2nix
  added.
- Fix in `pyproject.toml` first when uv can express it
  (`extra-build-dependencies`, `no-binary-package`, `config-settings`):
  one source of truth for uv and Nix.
- Overriding an attribute absent for some platform breaks eval there
  (`attribute 'foo' missing`): guard with
  `lib.optionalAttrs (prev ? foo) {...}`.
- Copy a recipe from `github.com/TyberiusPrime/uv2nix_hammer_overrides`
  (a community collection, per package and version) rather than taking
  it as an input: it is large and unreviewed.

## Wheels: native libraries

uv2nix runs `autoPatchelfHook` on Linux wheels and adds the manylinux
libraries named by the wheel tag (glibc, libstdc++, zlib and friends).
Anything else a wheel links to must be added:

```nix
numba = prev.numba.overrideAttrs (old: {
  buildInputs = (old.buildInputs or []) ++ [pkgs.tbb_2021_11];
});
```

Find the library from the error
(`auto-patchelf could not satisfy dependency libGL.so.1 wanted by ...`),
then the nixpkgs package that provides it (`nix-locate`, or the `nixos`
MCP tool). Libraries loaded with `dlopen` at runtime (not linked) pass
the build and fail at import: add them the same way, or set
`LD_LIBRARY_PATH` in a wrapper. Silence a truly optional one with
`autoPatchelfIgnoreMissingDeps = ["libcuda.so.1"];`.

## sdists: build systems

Building from an sdist runs its PEP 517 backend, which uv.lock does not
record. The error names the module
(`ModuleNotFoundError: No module named 'flit_core'`). Add it, as a
spec of `name = [extras]`:

```nix
pyzmq = prev.pyzmq.overrideAttrs (old: {
  buildInputs = (old.buildInputs or []) ++ [pkgs.zeromq];
  dontUseCmakeConfigure = true;
  nativeBuildInputs =
    old.nativeBuildInputs
    ++ final.resolveBuildSystem {
      cmake = [];
      ninja = [];
      packaging = [];
      pathspec = [];
      scikit-build-core = [];
      cython = [];
    };
});
```

`resolveBuildSystem` resolves from the set, so the backend must exist
there: `pyproject-build-systems` carries about 70 common ones
(setuptools, hatchling + plugins, flit-core, poetry-core, pdm-backend,
maturin, meson-python, scikit-build-core, cython, uv-build, ...; list in
its `pyproject.toml`). A backend outside it: add it to your uv project
(a dependency group) so it is locked, or open a PR there.

Or in `pyproject.toml`, read by both uv and uv2nix:

```toml
[tool.uv.extra-build-dependencies]
pyzmq = ["cmake", "ninja", "scikit-build-core"]
```

Many packages: a table plus `mapAttrs`, as upstream's
`dev/build-system-overrides.nix`:

```nix
{pkgs}: final: prev: let
  buildSystems = {
    idna.flit-core = [];
    urllib3 = {
      hatchling = [];
      hatch-vcs = [];
    };
  };
in
  builtins.mapAttrs (name: spec:
    prev.${name}.overrideAttrs (old: {
      nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem spec;
    }))
  buildSystems
```

First ask whether the sdist is needed: with `sourcePreference = "wheel"`
an sdist is used only when the lock has no compatible wheel. Choose a
version with wheels for your Python (`uv lock --upgrade-package foo`),
or bump the interpreter.

## Patching a dependency

Patches apply to source, so force the sdist and add its build system:

```nix
arpeggio =
  (prev.arpeggio.override {sourcePreference = "sdist";}).overrideAttrs
  (old: {
    patches = (old.patches or []) ++ [./arpeggio.patch];
    nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem {setuptools = [];};
  });
```

For a wheel, edit installed files in `postInstall` instead. Patching a
library you publish forces the same patch on your users: prefer a fork
pinned by git source in `pyproject.toml`.

## Packages from nixpkgs

For a package not on PyPI (or too hard to build) that nixpkgs builds,
with the same Python version as the set:

```nix
# overrides.nix, now also taking lib and pyproject-nix: update its
# import in python-set.nix to pass them.
{
  pkgs,
  lib,
  pyproject-nix,
}: final: prev: let
  hacks = pkgs.callPackage pyproject-nix.build.hacks {};
in {
  tkinter = hacks.nixpkgsPrebuilt {from = final.python.pkgs.tkinter;};
}
```

and list it in the venv spec (`{app = []; tkinter = [];}`), because it
is not in the lock. With `prev = prev.torch` the locked dependency
metadata is kept; filter what nixpkgs already links:

```nix
torch = hacks.nixpkgsPrebuilt {
  from = pkgs.python313Packages.torchWithoutCuda;
  prev = prev.torch.overrideAttrs (old: {
    passthru =
      old.passthru
      // {dependencies = lib.filterAttrs (n: _: !lib.hasPrefix "nvidia" n) old.passthru.dependencies;};
  });
};
```

Upstream templates `hello-tkinter` show the full wiring.

## Rust extensions from sdist

Wheels exist for nearly every maturin/setuptools-rust package; prefer
them. When an sdist is required:

```nix
cryptography =
  (hacks.importCargoLock {
    prev = prev.cryptography;
    cargoRoot = "src/rust";
  }).overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem {
      maturin = [];
      setuptools = [];
      cffi = [];
      pycparser = [];
    };
    buildInputs = (old.buildInputs or []) ++ [pkgs.openssl];
  });
```

## Private indexes

```toml
[[tool.uv.index]]
name = "corp"
url = "https://pypi.example.com/simple"
explicit = true

[tool.uv.sources]
corp-lib = {index = "corp"}
```

Fetches run in the sandbox, so credentials come from a netrc made
available to it, never from Nix source:

```nix
corp-lib = prev.corp-lib.overrideAttrs (old: {
  src = old.src.overrideAttrs (_: {
    curlOpts = "--netrc-file /etc/nix/netrc";
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  });
});
```

The builder needs `extra-sandbox-paths = /etc/nix/netrc` in `nix.conf`
(machine config: the owner's job, through clan vars for the file). CI
and the remote builder need it too, so prefer vendoring the wheel or a
git source when the index is not essential.

## Local and git sources

`[tool.uv.sources]` `path`, `git` (+ `subdirectory`, `tag`) and `url`
sources all work. Git sources are fetched with submodules at eval. A
`path` dependency outside the workspace is not a member: it is absent
from `workspace.deps` and cannot be made editable.

## Source filtering

`workspaceRoot` stays an unfiltered path (filtering it causes IFD and
breaks editables). Filter one member's `src` to stop rebuilds on
unrelated edits:

```nix
hello-uv = prev.hello-uv.overrideAttrs (old: {
  src = lib.fileset.toSource {
    root = old.src;
    fileset = lib.fileset.unions [(old.src + "/pyproject.toml") (old.src + "/src")];
  };
});
```

For the editable set, the build needs only `pyproject.toml` and the
package's `__init__.py` (editables rebuild only on metadata changes).

## Cross compilation

Fixups for build tools must reach the build-platform set as well:

```nix
pythonSet.overrideScope (lib.composeExtensions
  (_final: prev: {
    pythonPkgsBuildHost = prev.pythonPkgsBuildHost.overrideScope overrides;
  })
  overrides)
```

Native build tools come from `final.pkgs.buildPackages` (for example
`final.pkgs.buildPackages.cmake`). Natively the two sets are one, so the
plain overlay suffices.

## Platform quirks

- Linux marker `platform_release` is guessed from `linuxHeaders`; pin
  it: `mkPyprojectOverlay {sourcePreference = "wheel"; environ.platform_release = "6.1.0";}`.
- macOS SDK version for wheel tags and markers: pass
  `stdenv = pkgs.stdenv.override {targetPlatform = pkgs.stdenv.targetPlatform // {darwinSdkVersion = "15.1";};}`
  to `build.packages`. (The org builds Linux only.)

## Conflicting extras or groups

When `[tool.uv] conflicts` declares mutually exclusive extras or groups,
`deps.all` is invalid for the overlay: tell it the branch.

```nix
workspace.mkPyprojectOverlay {
  sourcePreference = "wheel";
  dependencies = {hello-uv = ["cpu"];};
}
```

Build one set per branch for CPU and GPU variants, and use the same
spec for `mkVirtualEnv`.
