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
| `inputs.pkgs.flakeModules.treefmt` | org linters: `formatter`, `checks.treefmt` |
| `inputs.pkgs.flakeModules.dev` | treefmt, `checks.lock-sync`, `apps.sync-locks`, `documentation`/`slides` as checks |
| `pkgs/devenv` (devenv.yaml `imports`) | the org shell: `fmt`, `check`, `sync-locks`, `docs`, `slides` scripts; `devenv up` serves docs :8000 and slides :8001; `devenv test` gates |
| `templates.default` | the whole layout below |

The flake modules use the importing repo's own `inputs.treefmt-nix` and
`inputs.presenting` (declared in its `dev/flake.nix`), so pkgs adds nothing
to anyone's main lock. Never copy the treefmt program list or the org shell
into a repo.

## Layout

```
flake.nix / flake.lock      consumer outputs; inputs follow pkgs
flake-parts/                consumer-facing modules (import-tree)
dev/flake.nix / flake.lock  dev partition inputs (never in flake.lock)
dev/flake-module.nix        the dev partition
devenv.yaml / devenv.lock   the shell: pkgs input, nixpkgs follows
                            pkgs/nixpkgs, imports pkgs/devenv
devenv.nix                  this repo's languages, services, processes
documentation/              mkdocs.yml, docs/, slides/, module.nix
AGENTS.md, README.md, .gitignore (result*, .devenv*, devenv.local.nix)
```

## flake.nix

```nix
{
  description = "...";

  inputs = {
    pkgs.url = "github:external-systems/pkgs";
    nixpkgs.follows = "pkgs/nixpkgs";
    flake-parts.follows = "pkgs/flake-parts";
    import-tree.follows = "pkgs/import-tree";
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
- `packages` stays at the root, so consumers never fetch dev inputs. Docs
  and slides build as `checks.<system>.documentation` / `.slides` (every
  `nix flake check`) and preview through `devenv up`.
- pkgs itself has no `pkgs` input: it owns `nixpkgs`, `flake-parts` and
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
    inputs.pkgs.flakeModules.dev
    ../documentation/module.nix
  ];
  # repo checks and maintainer apps go here (or in modules imported here)
}
```

## devenv.yaml and devenv.nix

```yaml
inputs:
  pkgs:
    url: github:external-systems/pkgs
  nixpkgs:
    follows: pkgs/nixpkgs
imports:
  - pkgs/devenv
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

Deck format, embedding and GitHub Pages: the `mkdocs-reveal` skill.

## Three lockfiles, one nixpkgs

`flake.lock`, `dev/flake.lock` and `devenv.lock` must resolve nixpkgs to
the same rev. `checks.lock-sync` fails when they drift and prints the
drifted locks. The fix is always `sync-locks` (devenv script, or
`nix run .#sync-locks`): it re-locks `dev-nixpkgs` with
`--override-input`, pins the pkgs rev in `devenv.yaml`, and runs
`devenv update pkgs`.

Bump flow: `nix flake update pkgs`, then `sync-locks`, in one commit.
Never run a bare `nix flake update` in `./dev` or a bare `devenv update`
to move nixpkgs.

## Procedure: new repo

1. `nix flake init -t github:external-systems/pkgs` in an empty
   directory; replace every `CHANGE ME`.
2. `git init && git add -A` (Nix only sees tracked files).
3. `nix flake lock && nix flake lock ./dev && devenv update`, then
   `nix run .#sync-locks`.
4. `devenv allow`, then `fmt`, `check`, `devenv test`, `devenv up`.
5. Confirm the main lock is clean: `jq '.nodes | keys' flake.lock` lists
   no treefmt-nix, devenv, presenting or mkdocs-flake.

## Procedure: converge an existing repo

1. Root `flake.nix`: inputs follow `pkgs`; add the partitions import,
   `partitionedAttrs` and `partitions.dev`.
2. Move dev-only inputs (treefmt-nix, devenv, nix2container,
   mk-shell-bin, mkdocs-flake, presenting, nix-unit, ...) from `flake.nix`
   to `dev/flake.nix`, or drop them (devenv: the CLI replaces it). Keep
   one only if a consumer-facing output needs it.
3. Delete the hand-rolled `checks.lint`, `formatter = pkgs.alejandra`,
   and every flake devShell (`devShells.default`, `devenv.shells.*`,
   `inputs.devenv.flakeModule`); import `inputs.pkgs.flakeModules.dev`.
4. Move the shell into `devenv.yaml` + `devenv.nix`: `mkShell` packages
   become devenv `packages`, `shellHook` becomes `enterShell`, helper
   scripts become `scripts`. Drop what `pkgs/devenv` already provides.
5. Add `documentation/` (copy the template's, or move existing docs
   there) and import its module from the dev partition.
6. Lock all three (`nix flake lock ./dev`, `devenv update`), run
   `sync-locks`, then `fmt` (expect a formatting diff the first time:
   commit it separately) and `check`.
7. In the PR body, list which inputs left the main lock.
