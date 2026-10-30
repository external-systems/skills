---
name: flakeparts
description: "flake-parts module system: mkFlake/perSystem mechanics, what the infra provides (self', inputs', flake, withSystem), input handling (follows, FlakeHub URLs, flake = false pins), the checks.lint gate, and integrations (clan-core, home-manager, devenv, mkdocs-flake). Load when editing flake.nix or any flake-parts module."
---

# flake-parts

How the flake-parts module system works, what its infrastructure
provides, where its docs live, and which integrations exist. Load when
writing `flake.nix` outputs, adding a flake-parts module, wiring
flakeModules, or asking "where does X get evaluated".

Docs: https://flake.parts — the canonical reference. Notable pages:
[options search](https://flake.parts/options), the
[module argument cheatsheet](https://flake.parts/cheat-sheet-module-args),
[`perSystem`](https://flake.parts/define-flake-schema-module), and
[debugging](https://flake.parts/debug) (expose `flake.debug.options` —
the home repo sets `debug = true;` in `flake.nix` — for `nixd`'s
flake-parts option provider and `nix repl` inspection).

## Mental model

A flake-part module is a NixOS-module-system module evaluated against the
flake's outputs instead of a system configuration. `mkFlake` collects
them into one evaluation:

```nix
# flake.nix
outputs = inputs:
  inputs.flake-parts.lib.mkFlake {inherit inputs;} {
    # systems declare the platforms perSystem outputs are instantiated for
    systems = ["x86_64-linux"];
    imports = [
      (inputs.import-tree ./flake-parts)   # auto-import the tree (see below)
      inputs.clan-core.flakeModules.default
      inputs.home-manager.flakeModules.home-manager
      inputs.mkdocs-flake.flakeModules.default
    ];
  };
```

What the infra hands every module:

| Argument / option | Provides |
|---|---|
| `perSystem` | opt-in per-platform submodules; import `flake-parts.lib.flakeModules.partials` machinery is internal — just use `perSystem = {pkgs, ...}: {...}` |
| `perSystem._module.args` | inject args (e.g. a repo `customLib`, pinned `pkgs`) into perSystem modules |
| `self` | the final flake outputs, referenceable anywhere |
| `self'.packages` / `self'.apps` / `self'.checks` / `self'.devShells` | per-system outputs for the current platform |
| `inputs'` | inputs filtered to flake outputs — use `inputs'.clan-core.packages...` instead of `inputs.clan-core.packages.${system}...` |
| `flake` | top-level (system-agnostic) outputs block (`nixosModules`, `homeModules`, `overlays`, ...) |
| `withSystem` | pull a perSystem scope from a top-level module |

Standard output names to use: `packages`, `devShells`, `checks`, `apps`,
`nixosConfigurations`, `homeModules`/`nixosModules`, `overlays`,
`formatter`, `templates`.

Conventions worth copying (from the home repo):

- Make the devShell buildable and cacheable so CI can warm it:
  `packages.devShell = self'.devShells.default;` then
  `nix build .#devShell`.
- Expensive, KVM-dependent, or VM-booting outputs must NOT go in `checks`
  (`nix flake check` evaluates and often builds `checks`). Expose them
  under `legacyPackages.<system>.vmTests` — `nix flake check` does not
  walk it. Writing and running them: the `vm-tests` skill.
- Do not add a `nixConfig` block requiring extra
  `trusted-public-keys`/`extra-substituters` trust from consumers. In CI,
  caching is configured by the runner-side actions, not by the flake.

## Auto-import with import-tree

Every `.nix` file under `flake-parts/` is loaded automatically — there is
no import list to update. Mechanics, `_`-prefix escape hatch, tree layout
conventions and agent rules: the `import-tree` skill. Short version:

```nix
imports = [(inputs.import-tree ./flake-parts)];
```

Files declare their own output attributes; the directory structure is
purely organizational (`flake-parts/packages/foo.nix` defines
`perSystem.packages.foo`).

## Input handling

- FlakeHub flakes by URL with semver wildcards:
  `https://flakehub.com/f/<org>/<repo>/*` (latest), `/0` or `/1.2` for a
  major or major.minor constraint — the `determinate` skill covers
  the versioning scheme.
- Deduplicate big inputs with `follows`
  (`nixpkgs.follows = "clan-core/nixpkgs";`) so one nixpkgs instance
  serves the whole graph. Surface a second channel as `pkgs.unstable`
  via an overlay, not by re-importing nixpkgs ad hoc.
- Pin binary artifacts (tarballs, wheels) as `flake = false` inputs so
  `flake.lock` carries the hash:
  `artifacthub-mcp = { url = "github:owner/repo?ref=v1.1.1"; flake = false; }`.
- One flake per versioned thing (Determinate's own advice): a CLI tool,
  a service's NixOS config, a docs site — publish each; consolidate
  later. Several flakes may live in one repo (monorepo-friendly).

## The lint gate (worked example)

Format/lint as a hard `checks.lint` derivation — fails `nix flake check`,
which CI already runs:

```nix
# flake-parts/checks.nix
{
  self,
  lib,
  ...
}: {
  perSystem = {pkgs, ...}: {
    checks.lint = pkgs.runCommand "lint" {
      nativeBuildInputs = with pkgs; [alejandra statix deadnix];
    } ''
      cd ${lib.sources.sourceFilesBySuffices self [".nix"]}
      alejandra --check .
      statix check .
      deadnix --fail .
      touch $out
    '';
  };
}
```

Filtering the source to `.nix` files keeps docs/asset changes from
invalidating the check and keeps secrets out of its closure. The
day-to-day loop using these tools: the `nix-style` skill.

## Available integrations in this repo

| Integration | How it is wired | Reference |
|---|---|---|
| clan-core | `inputs.clan-core.flakeModules.default` adds the `clan` option (fleet, clanServices, vars) | `clan-core` |
| home-manager | `inputs.home-manager.flakeModules.home-manager` evaluates `homeConfigurations` and provides options; NixOS-side HM runs via `nixosModules.home-manager` instead | `home-manager` |
| devenv | `inputs.devenv.flakeModule` embeds the devenv module system in `nix develop` | `devenv` |
| mkdocs-flake | `inputs.mkdocs-flake.flakeModules.default` gives `documentation.*` options (`documentation.mkdocs-root`) | — |

Other common flake-parts integrations worth knowing: `gitea`,
`hercules-ci`, `pre-commit`/git-hooks, `nixvim`, `nix-darwin`.
