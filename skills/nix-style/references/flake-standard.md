# Org flake standard: templates and procedures

Every flake repo under external-systems (and the owner's personal flake
repos) has the same shape. Consumers lock only what they evaluate:
formatter, linters, dev shell, docs and test-only inputs sit in a `dev`
flake-parts partition whose inputs have their own `dev/flake.lock`.

The shared pieces come from external-systems/pkgs as flake modules. They
use the importing repo's own `inputs.treefmt-nix` and `inputs.devenv`, so
pkgs adds nothing to anyone's main lock.

| Module | Gives |
|---|---|
| `inputs.pkgs.flakeModules.treefmt` | org linters: `formatter`, `checks.treefmt` |
| `inputs.pkgs.flakeModules.devenv` | `devShells.default` from `devenv.shells.default` (pure-eval root fallback, containers off) |
| `inputs.pkgs.flakeModules.dev` | both, treefmt in the shell, `checks.dev-lock-sync` |

## Layout

```
flake.nix               consumer-facing inputs + partition wiring
flake.lock
dev/flake.nix           dev-only inputs (never in flake.lock)
dev/flake.lock
dev/flake-module.nix    the dev partition
devenv/default.nix      the repo's shell (a plain devenv module)
documentation/          mkdocs.yml, docs/, slides/, module.nix
flake-parts/            consumer-facing modules (import-tree)
```

## flake.nix

```nix
{
  description = "...";

  inputs = {
    # Shared-input authority for the org: consumers that already follow
    # pkgs lock nothing new.
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
        devShells = "dev";
        formatter = "dev";
        # packages = "dev";  # only when the repo has no consumer-facing packages
      };

      partitions.dev = {
        module = ./dev/flake-module.nix;
        extraInputsFlake = ./dev;
      };
    };
}
```

`packages` rule: move it to `dev` only when every package is dev-only
(docs, slides). A repo whose consumers build its packages (pkgs, skills)
keeps `packages` at the root; its docs then build with
`nix build .#checks.<system>.documentation` and preview with
`nix run .#watch-documentation`.

pkgs itself has no `pkgs` input: it owns `nixpkgs`, `flake-parts` and
`import-tree` directly and imports its modules by path
(`../flakeModules/dev.nix`).

## dev/flake.nix

Input names must not clash with the root flake's, hence the `dev-` prefix.
Skip `treefmt-nix` here when the root already has it (clanServices does,
because clan-core and kubenix follow it).

```nix
{
  description = "Development-only inputs for <repo> (the dev partition)";

  # Locked in dev/flake.lock, never in the main flake.lock. dev-nixpkgs
  # must lock the same rev as the root nixpkgs (checks.dev-lock-sync):
  #   nix flake lock ./dev --override-input dev-nixpkgs github:NixOS/nixpkgs/<rev>
  inputs = {
    dev-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "dev-nixpkgs";
    };

    # nixpkgs NOT followed: devenv's own pin is what devenv.cachix.org
    # serves.
    devenv.url = "github:cachix/devenv?ref=v2.4.0";

    # Docs + slides (documentation/module.nix).
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
# Dev partition: formatter, checks, apps, docs and the devenv shell. A
# consumer of the repo's outputs never evaluates it.
{inputs, ...}: {
  imports = [
    inputs.pkgs.flakeModules.dev
    ../documentation/module.nix
  ];

  perSystem.devenv.shells.default.imports = [../devenv];

  # repo checks and maintainer apps go here (or in modules imported here)
}
```

## devenv/default.nix

A plain devenv module. It never references flake `inputs` or `self'`: it
evaluates inside devenv's module system. treefmt is already in the shell.

```nix
{pkgs, ...}: {
  packages = with pkgs; [
    git
    jq
  ];

  # Repo-scoped commands live here, not as flake apps.
  scripts.update-manifests.exec = ''
    nix run .#update-manifests
  '';
}
```

Rule of thumb: a command only maintainers run is a devenv `scripts` entry
or a dev-partition app. A command consumers run is a root `apps` or
`packages` output.

The devenv CLI side (`devenv.yaml`, `devenv.lock`, `devenv shell`,
auto-activation, `devenv mcp`, devcontainer) is opt-in: it adds a third
lockfile. Use it only when the repo needs those features, with a drift
check against `dev/flake.lock` as in the `devenv` skill's borg example.

## documentation/module.nix

```nix
# MkDocs site + reveal.js slides.
# Build: nix build .#documentation / .#slides
# Preview: nix run .#watch-documentation / .#serve-slides
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

Details (deck format, embedding, GitHub Pages): the `mkdocs-reveal` skill.

## Procedure: new flake repo

1. Create the layout above. `git add` every file.
2. `nix flake lock`, then `nix flake lock ./dev`, then `nix flake check`.
   The first run fails `dev-lock-sync` and prints the exact
   `nix flake lock ./dev --override-input dev-nixpkgs ...` command that
   pins the dev nixpkgs to the root's rev. Run it and check again.
3. `nix fmt`, `nix flake check`, `nix develop -c true`, `nix build .#documentation`.
4. Confirm the main lock is clean: `jq '.nodes | keys' flake.lock` lists
   no treefmt-nix, devenv, presenting or mkdocs-flake.

## Procedure: converge an existing repo

1. Root `flake.nix`: inputs follow `pkgs`; add the partitions import,
   `partitionedAttrs` and `partitions.dev`.
2. Move dev-only inputs (treefmt-nix, devenv, nix2container, mk-shell-bin,
   mkdocs-flake, presenting, nix-unit, ...) from `flake.nix` to
   `dev/flake.nix`. Keep one only if a consumer-facing output needs it.
3. Delete the hand-rolled `checks.lint` and `formatter = pkgs.alejandra`;
   import `inputs.pkgs.flakeModules.dev` instead.
4. Move the dev shell into `devenv/default.nix`. A `devShells.default =
   pkgs.mkShell {...}` becomes devenv `packages`; shellHook becomes
   `enterShell`.
5. Move docs wiring into `documentation/module.nix`, imported from the
   dev partition.
6. Lock both flakes (step 2 of the new-repo procedure), run `nix fmt`
   (expect a formatting diff the first time: commit it separately), then
   `nix flake check`.
7. In the PR body, list which inputs left the main lock.

## Bumping nixpkgs

`nix flake update pkgs` (or `nixpkgs` in pkgs itself), then the
`nix flake lock ./dev --override-input dev-nixpkgs ...` command that
`checks.dev-lock-sync` prints, in the same commit. Never run a bare
`nix flake update` in `./dev`: it moves `dev-nixpkgs` to a different rev.
