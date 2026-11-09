# Debugging uv2nix

Messages marked **(seen)** were reproduced on 2026-11-09 in the demo
repo; the rest are quoted from the source that raises them.

## Method

1. Read the first real error. Eval errors (`error:` with no build log)
   are lock, Python-version or Nix problems; build errors (`foo> ...`
   lines) are one package's derivation.
2. Name the package. `nix build .#NAME -L` streams logs; for a failed
   dependency, `nix log /nix/store/HASH-foo-1.2.3.drv`.
3. Ask what uv2nix chose:
   `nix eval .#legacyPackages.x86_64-linux.pythonSet.foo.passthru.format`
   (`"wheel"` or `"pyproject"` = sdist) and `.src.url`.
4. Reproduce the one package: `nix build .#legacyPackages.x86_64-linux.pythonSet.foo -L`.
5. Fix in `overrides.nix` (or `pyproject.toml`), `git add`, rebuild.
   Then `nix flake check`.

## Evaluation errors

| Message | Cause | Fix |
|---|---|---|
| `error: assertion '(all (spec: ((pep440).comparators."${(spec).op}" pythonVersion (spec).version)) (uvLock).requires-python)' failed` at `lib/overlays.nix` **(seen)** | Set's interpreter is outside the lock's `requires-python` | Use a matching `pkgs.python3xx`, or lower `requires-python` and `uv lock`. Patch-level mismatch only: `pythonVersion = "3.13.0"` |
| `uv init` writes `requires-python = ">=3.14"` (or uv says `incompatible with the project's Python requirement`) **(seen)** | uv picked a non-Nix Python from PATH | In the devenv shell `UV_PYTHON` points at the set's interpreter; outside it pass `--python $(nix eval --raw .#...python.interpreter)` or `--python 3.13` |
| `error: No sourcePreference was passed, and could not be automatically inferred from workspace config` **(seen)** | `mkPyprojectOverlay {}` | `sourcePreference = "wheel"` |
| `error: Editable root was passed as a Nix store path.` **(seen)** | `mkEditablePyprojectOverlay` without `root` in a flake (the root defaults to the store copy) | `root = "$DEVENV_ROOT"` (devenv) or `"$REPO_ROOT"` with that var exported |
| `Path 'uv.lock' in the repository "..." is not tracked by Git.` **(seen)** | New lock or member not added | `git add -A` |
| `error: attribute 'nosuch' missing` from `mkVirtualEnv` or `pythonSet.nosuch` **(seen)** | Name not in the resolved set: typo, not normalised (use `charset-normalizer`, lowercase, dashes), excluded by markers on this platform/Python, or not in uv.lock | `grep -A3 'name = "nosuch"' uv.lock`; check markers; `uv add` it |
| `No compatible wheel, nor sdist found for package 'foo' X` | Lock has only wheels, none for this Python/platform (aarch64, musl, new CPython) | Other Python; another version (`uv lock --upgrade-package foo`); `nixpkgsPrebuilt` |
| `Package source for 'foo' was derived as wheel, but tool.uv.no-binary is set to true` (and the 3 siblings) | `no-build`/`no-binary` settings contradict what the lock offers | Make the `[tool.uv]` lists consistent |
| `There is an overlap between packages specified as no-build and no-binary-package` | Same package in both lists | Remove from one |
| `Got conflicting values for tool.uv.no-build` | Members disagree | Same value in every member |
| `Both tool.uv.no-build and tool.uv.no-binary are set to true` | Unbuildable | Drop one |
| `infinite recursion` around `python` | Override reads `final.python` to build `python` itself, or an overlay depends on `final` for attribute names | Reference `prev` for the thing being overridden; keep names static |
| Eval slow, or `import-from-derivation` warnings | `workspaceRoot` filtered or produced by a derivation | Plain path (`../..`, `./.`) |

## Build errors

| Message | Cause | Fix |
|---|---|---|
| `foo> ModuleNotFoundError: No module named 'flit_core'` then `hint: This error likely indicates that 'foo' depends on 'flit_core', but doesn't declare it as a build dependency` **(seen)** | sdist build without its backend | `resolveBuildSystem {flit-core = [];}` (overrides.md), `tool.uv.extra-build-dependencies`, or use its wheel |
| `hello-uv> ModuleNotFoundError: No module named 'editables'` building the dev venv **(seen)** | hatchling member built editable | Add `editables` to that member in the editable set (org-recipes.md) or switch it to `uv_build` |
| `auto-patchelf could not satisfy dependency libX.so.N wanted by ...` | Wheel links a library outside the manylinux set | `buildInputs = [pkgs.X]`; truly optional: `autoPatchelfIgnoreMissingDeps` |
| `Two or more packages are trying to provide the same file with different contents` | Two packages ship one path (namespace leftovers, vendored tools) | `(mkVirtualEnv ...).overrideAttrs (_: {venvIgnoreCollisions = ["path"];})`, or `venvSkip` |
| `error: Failed to build ... cause: The build backend returned an error` with compiler output (`gcc`, `cmake`, `pkg-config` not found, `.h` missing) | Native build needs tools/headers | `nativeBuildInputs` (`pkgs.pkg-config`, `pkgs.cmake`), `buildInputs` (`pkgs.openssl`, ...); `dontUseCmakeConfigure = true` when the backend drives cmake |
| Rust/Cargo wants network | sdist Rust extension | Prefer the wheel; else `hacks.importCargoLock` |
| `curl: (22) ... 401` fetching | Private index without sandbox credentials | overrides.md, "Private indexes" |
| Build output references `/build/` or a store path in a wheel dist build | `pyprojectDistHook` reference scan | Find what embeds the path (RPATH, generated config) and strip it |

## Runtime problems

| Symptom | Cause | Fix |
|---|---|---|
| A new dependency is missing (`ModuleNotFoundError` at runtime), build was green **(seen)** | pyproject.toml changed, uv.lock not regenerated: uv2nix built the old lock without error | `uv lock`, `git add uv.lock`; the `uv-lock` check fails in this state |
| `ImportError: libGL.so.1` (or similar) only at import | Library loaded by `dlopen`, invisible to autoPatchelf | `buildInputs` on that package, or `LD_LIBRARY_PATH` wrapper |
| Wrong package versions or modules from elsewhere in the shell | `PYTHONPATH` leaked from nixpkgs Python packages in the shell | `unset PYTHONPATH` in `enterShell`; keep nixpkgs `python3.withPackages` out of the same shell |
| `uv run` creates `.venv`, installs again | uv-managed env in a uv2nix shell | `UV_NO_SYNC=1`; run scripts directly |
| Code edits not visible in the dev shell | Member not editable (virtual, `path` source, not in `members`), or `$DEVENV_ROOT` unset | Check `python -c 'import foo; print(foo.__file__)'` points into the repo |
| Edits to `pyproject.toml` (new script, new module dir) not visible | Editable build caches metadata | Re-enter the shell (rebuilds the member) |
| `nix run .#app` says no `mainProgram` / runs the wrong binary | Several `[project.scripts]` or a wrapper project | Set `meta.mainProgram` in an `overrideAttrs` |
| Tests pass in the shell, fail in `checks` | Check uses installed code from the store: missing package data (`[tool.uv-build] ...` includes), files read relative to CWD, writes to read-only source | Fix packaging; `cd` to a writable copy in the check |

## Reading uv2nix itself

Clone and grep the message: `git clone --depth 1
https://github.com/pyproject-nix/uv2nix` (eval logic in
`lib/build.nix`, `lib/overlays.nix`, `lib/workspace.nix`) and
`pyproject-nix/pyproject.nix` (`build/hooks/` for the build-time
scripts, `build/hooks/make-venv/make_venv.py` for venv assembly). The
upstream tests (`uv2nix/lib/test_*.nix`, `dev/checks.nix`) show working
usage of every feature.
