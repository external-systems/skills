# Org flake standard: templates and procedures

Every flake repo under external-systems (and the owner's personal flake
repos) has the same shape. A developer needs Nix (sandbox on, the default)
and devenv, nothing else. The devenv CLI is the only dev shell; the flake is
the build and consumer interface. Consumers lock only what they evaluate:
formatter, linters, docs and test-only inputs sit in a `dev` flake-parts
partition whose inputs have their own `dev/flake.lock`. Every repo ships a
docs site and a slide deck.

The canonical source is `nix flake init -t github:external-systems/pkgs`
(pkgs `templates/default`). Prefer it over copying the snippets below; the
snippets explain what the template contains.

## What pkgs provides

| Piece | Gives |
|---|---|
| `inputs.org-pkgs.flakeModules.treefmt` | org linters: `formatter`, `checks.treefmt` |
| `inputs.org-pkgs.flakeModules.dev` (also `.default`) | treefmt, `checks.lock-sync`, `apps.sync-locks`, `documentation`/`slides` as checks and as `legacyPackages` |
| `org-pkgs/devenv` (devenv.yaml `imports`) | the org shell: `fmt`, `check`, `sync-locks`, `docs-build`, `docs`, `slides` scripts; `devenv up` serves docs :8981 and slides :8982; `devenv test` gates |
| `templates.default` | the whole layout below |

The flake modules use the importing repo's own `inputs.treefmt-nix` and
`inputs.presenting` (declared in its `dev/flake.nix`), so pkgs adds nothing
to anyone's main lock. Never copy the treefmt program list or the org shell
into a repo.

## Layout

```
flake.nix / flake.lock      consumer outputs; inputs follow org-pkgs
flake-parts/                consumer-facing modules (import-tree)
dev/flake.nix / flake.lock  dev partition inputs (never in flake.lock)
dev/flake-module.nix        the dev partition
devenv.yaml / devenv.lock   the shell: org-pkgs input, nixpkgs follows
                            org-pkgs/nixpkgs, imports org-pkgs/devenv
devenv.nix                  this repo's languages, services, processes
documentation/              mkdocs.yml, docs/, slides/, module.nix
AGENTS.md, README.md, .gitignore (result*, .devenv*, devenv.local.nix)
.vscode/settings.json       nixd settings (below); extensions.json
                            recommends jnoortheen.nix-ide
```

## flake.nix

```nix
{
  description = "...";

  inputs = {
    org-pkgs.url = "github:external-systems/pkgs";
    nixpkgs.follows = "org-pkgs/nixpkgs";
    flake-parts.follows = "org-pkgs/flake-parts";
    import-tree.follows = "org-pkgs/import-tree";
    # consumer-facing inputs only; each one follows nixpkgs/flake-parts
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        inputs.flake-parts.flakeModules.partitions
        (inputs.import-tree ./flake-parts)
      ];

      partitionedAttrs = {
        apps = "dev";
        checks = "dev";
        formatter = "dev";
        legacyPackages = "dev"; # docs: nix build .#documentation
      };

      partitions.dev = {
        module = ./dev/flake-module.nix;
        extraInputsFlake = ./dev;
      };
    };
}
```

- No `devShells` output: the shell is devenv. Never add a flake devShell or
  `inputs.devenv.flakeModule`.
- `packages` stays at the root, so consumers never fetch dev inputs.
  `flakeModules.dev` exposes docs and slides as `legacyPackages`
  (partitioned to `dev`), so `nix build .#documentation` and
  `nix build .#slides` still work, and as checks, so every
  `nix flake check` builds them. A repo whose consumers use its
  `legacyPackages` leaves that attr at the root and builds
  `.#checks.<system>.documentation` instead.
- pkgs itself has no `org-pkgs` input: it owns `nixpkgs`, `flake-parts` and
  `import-tree` directly and imports its modules by path.

## dev/flake.nix

Input names must not clash with the root flake's, hence `dev-nixpkgs`.
Skip `treefmt-nix` here when the root already has it (clanServices does,
because clan-core and kubenix follow it).

```nix
{
  description = "Development-only inputs (the dev partition)";

  inputs = {
    dev-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "dev-nixpkgs";
    };

    presenting = {
      url = "github:external-systems/presenting";
      inputs.nixpkgs.follows = "dev-nixpkgs";
    };

    # test-only inputs (nix-unit, ...) follow dev-nixpkgs too
  };

  outputs = _: {};
}
```

## dev/flake-module.nix

```nix
{inputs, ...}: {
  imports = [
    inputs.org-pkgs.flakeModules.dev
    ../documentation/module.nix
  ];
  # repo checks and maintainer apps go here (or in modules imported here)
}
```

## devenv.yaml and devenv.nix

```yaml
inputs:
  org-pkgs:
    url: github:external-systems/pkgs
  nixpkgs:
    follows: org-pkgs/nixpkgs
imports:
  - org-pkgs/devenv
```

```nix
# This repo's additions to the org shell.
_: {
  # languages.rust.enable = true;
  # services.postgres.enable = true;
  # processes.api.exec = "cargo run";
}
```

Rules:

- The pkgs flake is the input `org-pkgs` in every `flake.nix` and
  `devenv.yaml`, never `pkgs`. `pkgs` is the nixpkgs package set
  everywhere else, and devenv passes every `devenv.yaml` input to the
  devenv modules as a module argument, so an input named `pkgs` replaces
  nixpkgs' `pkgs` and fails with "attribute 'bash' missing".

- `devenv.nix` is a plain devenv module. Flake outputs are not visible
  there; anything it needs from another flake comes in as a `devenv.yaml`
  input (following `nixpkgs`).
- Repo-scoped commands are devenv `scripts` (or `tasks`); long-running
  dev services are `processes`/`services`. Consumer-facing commands are
  root flake `apps`/`packages`.
- Never edit the pkgs rev in `devenv.yaml` by hand: `sync-locks` owns it.
- Activation: `devenv hook <shell>` once per machine in the shell rc, then
  `devenv allow` once per checkout.

## documentation/module.nix

```nix
{inputs, ...}: {
  imports = [inputs.presenting.flakeModules.default];

  perSystem = {
    documentation = {
      mkdocs-root = ./.;
      strict = true;
    };

    presenting.slides = {
      dir = ./slides;
      serveDirName = "documentation/slides";
    };
  };
}
```

`documentation/mkdocs.yml` carries three org settings (the template has
them):

```yaml
dev_addr: 127.0.0.1:8981      # live preview; 8000/8001 belong to apps
use_directory_urls: false     # links work from file://
plugins:
  - search
  - offline                   # Material: search works from file://
```

The deck iframe on a docs page uses a relative path
(`src="slides/index.html"` from the site root) so it also loads from
`file://`.

Preferred docs loop: `docs-build` (or `nix build .#documentation`), then
open `result-docs/index.html` (or `result/index.html`) straight from
disk, for example `firefox result/index.html`. No server process runs.
`devenv up` (live reload on :8981, slides on :8982) is for heavy editing
sessions.

Deck format, embedding and GitHub Pages: the `mkdocs-reveal` skill.

## nixd settings

Every repo commits `.vscode/settings.json` from the template and sets
`debug = true;` in `mkFlake` (exposes `debug.options` and
`currentSystem.options`; lazy, consumers never evaluate them). nixd
evaluates `./.` from the workspace root, so one file fits every clone:

```json
{
  "nix.enableLanguageServer": true,
  "nix.serverPath": "nixd",
  "nix.serverSettings": {
    "nixd": {
      "nixpkgs": {
        "expr": "import (builtins.getFlake (builtins.toString ./.)).inputs.nixpkgs { }"
      },
      "formatting": {
        "command": ["alejandra", "--quiet"]
      },
      "options": {
        "flake-parts": {
          "expr": "(builtins.getFlake (builtins.toString ./.)).debug.options"
        },
        "flake-parts-perSystem": {
          "expr": "(builtins.getFlake (builtins.toString ./.)).currentSystem.options"
        },
        "nixos": {
          "expr": "((builtins.getFlake (builtins.toString ./.)).inputs.nixpkgs.lib.nixosSystem { modules = [ { nixpkgs.hostPlatform = builtins.currentSystem; } ]; }).options"
        }
      }
    }
  }
}
```

Override `options` where the repo has its own option namespace:

- Modules repo: `nixos` evaluates `f.nixosModules.default` plus
  `./dev/clan-stub.nix` (a module that reads `clan.core` fails the whole
  option set otherwise); `home-manager` evaluates
  `f.inputs.home-manager.lib.homeManagerConfiguration` with
  `f.homeModules.default` and plasma-manager.
- Machine repos: `f.nixosConfigurations.<name>.options`, and
  `.options.home-manager.users.type.getSubOptions []` for home-manager.

Test an expression before committing it:
`nix eval --impure --expr 'builtins.attrNames (<expr>)'` from the repo
root. `nixd` and `alejandra` are on PATH in the devenv shell; start the
editor from it (or install them per user, as `homeModules.vscode`
does). Never set `diagnostic.suppress`: nixf findings fail
`checks.treefmt`.

## Three lockfiles, one nixpkgs

`flake.lock`, `dev/flake.lock` and `devenv.lock` must resolve nixpkgs to
the same rev. `checks.lock-sync` fails when they drift and prints the
drifted locks. The fix is always `sync-locks` (devenv script, or
`nix run .#sync-locks`): it re-locks `dev-nixpkgs` with
`--override-input`, pins the pkgs rev in `devenv.yaml`, and runs
`devenv update org-pkgs`.

Bump flow: `nix flake update org-pkgs`, then `sync-locks`, in one commit.
Never run a bare `nix flake update` in `./dev` or a bare `devenv update`
to move nixpkgs.

## Procedure: new repo

1. `nix flake init -t github:external-systems/pkgs` in an empty
   directory; replace every `CHANGE ME`.
2. `git init && git add -A` (Nix only sees tracked files).
3. `nix flake lock && nix flake lock ./dev && devenv update`, then
   `nix run .#sync-locks`.
4. `devenv allow`, then `fmt`, `check`, `devenv test`, `docs-build`.
5. Open the repo in VS Code from the shell and check that nixd hints
   (hover a flake-parts option) work.
6. Confirm the main lock is clean: `jq '.nodes | keys' flake.lock` lists
   no treefmt-nix, devenv, presenting or mkdocs-flake.

## Procedure: converge an existing repo

1. Root `flake.nix`: inputs follow `org-pkgs`; add the partitions import,
   `partitionedAttrs` and `partitions.dev`.
2. Move dev-only inputs (treefmt-nix, devenv, nix2container,
   mk-shell-bin, mkdocs-flake, presenting, nix-unit, ...) from `flake.nix`
   to `dev/flake.nix`, or drop them (devenv: the CLI replaces it). Keep
   one only if a consumer-facing output needs it.
3. Delete the hand-rolled `checks.lint`, `formatter = pkgs.alejandra`,
   and every flake devShell (`devShells.default`, `devenv.shells.*`,
   `inputs.devenv.flakeModule`); import `inputs.org-pkgs.flakeModules.dev`.
4. Move the shell into `devenv.yaml` + `devenv.nix`: `mkShell` packages
   become devenv `packages`, `shellHook` becomes `enterShell`, helper
   scripts become `scripts`. Drop what `org-pkgs/devenv` already provides.
5. Add `documentation/` (copy the template's, or move existing docs
   there) and import its module from the dev partition.
6. Lock all three (`nix flake lock ./dev`, `devenv update`), run
   `sync-locks`, then `fmt` (expect a formatting diff the first time:
   commit it separately) and `check`.
7. Rename the input `pkgs` to `org-pkgs` (url, every follows path,
   `inputs.org-pkgs.*` references) and run `nix flake lock`; downstream
   flakes that override it (`<repo>.inputs.pkgs.follows`) must switch to
   `<repo>.inputs.org-pkgs.follows`.
8. Copy the template's `.vscode/` and add `debug = true;` to `mkFlake`;
   replace absolute `/home/...` paths in an existing
   `.vscode/settings.json` with `builtins.toString ./.` (see
   [nixd settings](#nixd-settings)).
9. In the PR body, list which inputs left the main lock.
