# The Astral toolchain, editors and nixd

How uv, ruff and ty are wired in org Python repos, and how VS Code,
VSCodium and nixd see them. Verified 2026-11-14 with the org nixpkgs
(uv 0.13.5, ruff 0.17.2, ty 0.0.91), ruff-vscode 2026.96, ty-vscode
2026.100, nixd 2.9.3 and devenv 2.4. Sources worth reading when this runs
out: astral-sh/ty `docs/`, astral-sh/ruff `crates/ty_*` and
`crates/ruff_linter`, astral-sh/ruff-vscode and ty-vscode `src/common/server.ts`.

## One version of each tool

uv, ruff and ty come from the org nixpkgs, through
`org-pkgs/devenv/python` (shell, `.devenv/profile/bin`), treefmt and the
checks. Bumps arrive with `nix flake update org-pkgs`. The editor
extensions bundle their own (newer) binaries; `ruff.path`/`ty.path` point
them at the profile so editor and CI agree. Never add ruff, ty or
pyrefly to a uv dependency group: the extensions then find the PyPI copy
in the venv first.

## uv

The shell sets:

| Variable | Why |
|---|---|
| `UV_NO_SYNC=1` | uv edits `uv.lock` only |
| `UV_PROJECT_ENVIRONMENT=<Nix dev venv>` | `uv run` uses the Nix venv instead of creating `.venv`; `uv sync` fails on the read-only store, loudly |
| `UV_PYTHON=<interpreter>`, `UV_PYTHON_PREFERENCE=only-system`, `UV_PYTHON_DOWNLOADS=never` | uv never downloads a Python |

- `uv lock --check` (= `--locked`) is the CI gate (`checks.python-uv-lock`,
  offline, works with git dependencies).
- uv_build has no dynamic version: keep a static `X.Y.0` and let Nix
  stamp (org-recipes.md, Versioning internals).
- uv2nix ignores `required-version`, uv auth and build constraints; it
  needs an explicit dependency selection for `tool.uv.conflicts`.

## ruff

- Runs from treefmt: `ruff-check` (`check --fix`, safe fixes only) then
  `ruff-format`, on `*.py`/`*.pyi`. Unfixable findings fail `fmt` and
  `checks.treefmt`.
- **Astral's default rule set** (ruff 0.16+, about 400 stable rules:
  pyflakes, the error-level pycodestyle rules, isort, pyupgrade, bugbear,
  simplify, pylint subsets, ruff's own). Never `select` (it replaces the
  curated set); add with `extend-select`, drop with `ignore` and a
  comment why. The target is `requires-python`.
- Findings worth knowing: `PLW1510` (pass `check=` to `subprocess.run`),
  `TRY201` (bare `raise`), `BLE001` (catch the real exception; keep a
  deliberate fallback with `# noqa: BLE001` and a reason), `B008`
  (Typer: use `Annotated[T, Option(...)] = default`), `RUF012`
  (`ClassVar` for mutable class attributes).
- Config sharing: `extend` takes local paths only; the org relies on the
  defaults instead of a shared file.
- A shell `ruff format .` also formats Python blocks in Markdown (0.16+);
  treefmt does not. Use `fmt`.

## ty

- `ty check --python <venv>`; exit 0 clean, 1 on any diagnostic of
  warning level or more, 2 config error. `checks.python-ty` adds
  `--error-on-warning` (`python.ty.args`). Output formats include
  `concise`, `github`, `junit`.
- Config: `[tool.ty]` in `pyproject.toml` (a `ty.toml` next to it wins).
  No `extends`. Rules: `[tool.ty.rules] some-rule = "ignore"|"warn"|"error"`,
  per glob in `[[tool.ty.overrides]]`.
- **Environment discovery:** `--python`, then `environment.python`, then
  the editor's selected interpreter, then `VIRTUAL_ENV`, `.venv`, PATH.
  The devenv profile has a `pyvenv.cfg`, so `.devenv/profile` works as
  a venv. Never put `environment.python` in `pyproject.toml`: where the
  profile is missing (CI, the Nix sandbox) ty exits 2.
- **Editable installs:** ty reads only plain path lines in `.pth` files.
  pyproject.nix writes editable `.pth` files as `import sys; ...` lines,
  so ty ignores them. First-party code still resolves through ty's own
  roots (the project root, `./src`). Workspace members elsewhere:

  ```toml
  [tool.ty.environment]
  root = ["./src", "./packages/api/src", "./packages/lib-a/src"]
  ```

- ty is beta (0.0.x): any version may add diagnostics. A ty bump comes
  with the org-pkgs bump; fix or tune findings in that PR.
- In the Nix sandbox ty needs no HOME or cache and runs offline.

## VS Code and VSCodium

Both read the repo's `.vscode/` (from the pkgs template). Every
extension below is on Open VSX (VSCodium) and the Marketplace.

```json
{
  "recommendations": ["jnoortheen.nix-ide", "astral-sh.ty", "charliermarsh.ruff",
                      "ms-python.python", "ms-python.debugpy"],
  "unwantedRecommendations": ["ms-python.vscode-pylance"]
}
```

```jsonc
"python.defaultInterpreterPath": "${workspaceFolder}/.devenv/profile/bin/python",
"python.languageServer": "None",          // ty is the language server
"python.terminal.activateEnvironment": false,
"python.testing.pytestEnabled": true,
"python.testing.unittestEnabled": false,
"ty.path": ["${workspaceFolder}/.devenv/profile/bin/ty"],
"ty.diagnosticMode": "workspace",
"ruff.path": ["${workspaceFolder}/.devenv/profile/bin/ruff"],
"[python]": {
  "editor.defaultFormatter": "charliermarsh.ruff",
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {"source.fixAll": "explicit", "source.organizeImports": "explicit"}
}
```

- **Interpreter:** ms-python uses a stored per-workspace pick first, then
  `python.defaultInterpreterPath`. A fresh clone gets the profile; a
  manual pick overrides it for good (clear it with "Python: Clear
  Workspace Interpreter Setting").
- `.devenv/profile` exists after the first `devenv shell`; until then
  the extensions fall back to their bundled binaries.
- **ty-vscode** binary order: `ty.path`, then bundled (`useBundled`), the
  selected interpreter's scripts dir, PATH, bundled. It passes the
  ms-python interpreter to the server; without ms-python it uses ty's
  own discovery. It sets `python.languageServer` to `None` by default.
- **ruff-vscode** binary order: `ruff.path`, bundled (`useBundled`), the
  interpreter's `bin/ruff`, PATH, bundled. `ruff.nativeServer` is gone
  (ruff-lsp removed in 0.17); never set it.
- ty provides completion with auto-import, hover, signature help, inlay
  hints, go-to, references, rename, symbols, semantic tokens and
  workspace diagnostics. No code lens.
- Debugging uses `ms-python.debugpy` with the selected interpreter.

## nixd

The template's nixd settings evaluate nixpkgs **with the org overlay**,
so hover and completion know org packages:

```jsonc
"nix.serverSettings": {"nixd": {"nixpkgs": {"expr":
  "let f = builtins.getFlake (builtins.toString ./.); in import f.inputs.nixpkgs { overlays = [ f.inputs.org-pkgs.overlays.default ]; }"
}}}
```

(pkgs itself uses `f.overlays.default`.) Cost: about +0.06 s and
+22 MB per evaluation; overlay names are static, so third-party inputs
are fetched only when a package is opened.

- Hover shows `name` (with the version), `meta.description` and the
  homepage; completion shows `version`, or `?` when the derivation has
  none. `flakeModules.python` packages always set `pname`/`version`/`meta`.
- The `python.*` perSystem options show through the
  `flake-parts-perSystem` options provider
  (`(builtins.getFlake ...).currentSystem.options`, needs `debug = true`).
