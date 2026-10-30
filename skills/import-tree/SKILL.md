---
name: import-tree
description: "flake-parts auto-import via import-tree: provenance, mechanics (_-prefix escape hatch, .nix-only, one module-system eval), tree layout conventions, and agent rules (no import list ever). Load when adding, moving, or drafting files under flake-parts/."
---

# import-tree

How flake-parts auto-import works: every `.nix` file under `flake-parts/`
is loaded automatically — there is no import list to update, ever. The
wiring example is from the home repo (`andrewthomaslee/home`); the
mechanics are universal.

## What it is, where it comes from

`import-tree` is a single-file, zero-dependency Nix library from the
dendritic ecosystem ([denful/import-tree](https://github.com/denful/import-tree),
by Vic/@denful). It is **not** built into flake-parts, clan, or nixpkgs —
it is pinned as a dedicated flake input:

```nix
# flake.nix
import-tree.url = "github:denful/import-tree";
```

`flake.lock` carries the pinned revision; update it like any other input
(`nix flake update import-tree`).

It exists to enable the
[Dendritic pattern](https://github.com/mightyiam/dendritic): each file is
a self-contained module, each concern lives in its own file, and the
directory tree *is* the configuration. The alternative — a hand-maintained
`imports = [ ./a.nix ./b.nix ... ]` roster — drifts: every new file needs
an edit somewhere else, and forgetting one silently drops it from the
config.

## Mechanics

`inputs.import-tree ./dir` returns a single Nix module whose `imports` is
the list of every `.nix` file found recursively under `./dir`:

- `.nix` files only. Non-Nix assets (scripts, templates, JSON) are never
  imported; read them by relative path from the module that needs them
  (`builtins.readFile ./sshMotd.sh`).
- Paths containing `/_` are skipped. An underscore-prefixed file
  (`_draft.nix`) or directory (`_helpers/`) is invisible to import-tree —
  the escape hatch for helpers and works-in-progress.
- Dot-files are not special-cased: `.foo.nix` would be imported. Hide
  things with `/_`, not a leading dot.
- Lazy: the directory is read when the module is evaluated, not when the
  flake expression is constructed.
- One module-system eval: all discovered files join the same flake-parts
  module set, so they share args and merge like any modules. Normal
  module semantics apply — two files setting the same plain attribute is
  an eval conflict; use distinct attribute names or `lib.mkMerge`.

## Wiring example: the home repo (`flake.nix`)

```nix
outputs = inputs:
  inputs.flake-parts.lib.mkFlake {inherit inputs;} {
    systems = ["x86_64-linux"];
    debug = true;
    imports = [
      (inputs.import-tree ./flake-parts)
      inputs.mkdocs-flake.flakeModules.default
      inputs.clan-core.flakeModules.default
      inputs.home-manager.flakeModules.home-manager
    ];
  };
```

- `systems` and `debug` stay in `flake.nix`, not in tree files.
- External flakeModules (clan-core, home-manager, mkdocs-flake) are
  imported **explicitly** alongside the tree — they are inputs, not repo
  modules, so they do not live under `flake-parts/`.

## Tree layout conventions (`flake-parts/`)

Directory structure is purely organizational: subdirectories do **not**
map to attribute paths. Each file declares its own output attribute
inside itself; import-tree never derives names. Keep the filename in
sync with the attribute it defines. The layout below is the home repo's
(`andrewthomaslee/home`):

```nix
# flake-parts/nixosModules/docker.nix — declares its own output attr
{
  lib,
  ...
}: {
  flake.nixosModules.docker = {
    config,
    pkgs,
    ...
  }: let
    cfg = config.hostSpec.services.docker;
  in {
    options.hostSpec.services.docker.enabled = lib.mkEnableOption "docker";
    config = lib.mkIf cfg.enabled {...};
  };
}
```

Outer args (`inputs, self, lib, ...`) come from flake-parts; args of the
inner function are whatever the output is (NixOS module args, perSystem,
...).

| Path | Defines |
|---|---|
| `default.nix` | global wiring: `customLib`, perSystem `_module.args`/pkgs, `formatter`, composition of `nixosModules.default` / `homeModules.default` |
| `checks.nix` | `perSystem.checks.lint` (the CI lint gate) |
| `tests.nix` | VM-test discovery and runner wiring |
| `devShells.nix` | `perSystem.devShells` |
| `packages/<name>.nix` | `perSystem.packages.<name>` |
| `apps/<name>.nix` | `perSystem.apps.<name>` |
| `nixosModules/<name>.nix` | `flake.nixosModules.<name>` |
| `homeModules/<name>.nix` | `flake.homeModules.<name>` |

Grouping subdirectories are just folders: `nixosModules/motd/motd.nix`
still defines `flake.nixosModules.motd`; `homeModules/profiles/netsa.nix`
defines `flake.homeModules.profile-netsa` — the path contributes nothing
to the attribute name.

`default.nix` is not special: it is imported like any other file in the
tree; it just happens to hold the global wiring.

Composition filters (if a repo wants opt-in modules) live in
`default.nix`: the home repo's `nixosModules.default` /
`homeModules.default` pull in all `self.nixosModules` /
`self.homeModules` **except** attrs prefixed `profile-` (both) or
`clan-` (nixos only) — those are opt-in and wired elsewhere (user
profiles, clan services).

Machine configurations (`machines/<hostname>/`) are **not** part of this
tree — clan imports those directly; the clan flakeModule is an explicit
import in `flake.nix`.

## Agent rules

- There is no import list to update, ever. Adding a module = creating one
  file (and `git add`-ing it — untracked files do not exist to Nix).
- One concern per file; filename matches the attribute it defines
  (`packages/foo.nix` → `perSystem.packages.foo`).
- Drafting a file that must not eval yet: prefix it `/_` (`_wip.nix`).
  Every tree file is evaluated on every `nix flake check`, so a broken
  draft otherwise breaks the whole flake.
- Shared helpers that are not modules live under a `/_` prefix or outside
  the tree.
- Defining the same output attr from two files is an eval error — check
  `nix flake check --show-trace` for conflicts.

## Links

- [denful/import-tree](https://github.com/denful/import-tree) — source and
  README (quick-start for non-flake-parts usage)
- [import-tree docs](https://import-tree.oeiuwq.com) — API (`.filter`,
  `.match`, `.map`, `.addAPI`) and
  [why it exists](https://import-tree.oeiuwq.com/motivation/)
- [Dendritic pattern](https://github.com/mightyiam/dendritic) and
  ["each file is a flake-parts module"](https://discourse.nixos.org/t/pattern-each-file-is-a-flake-parts-module/61271)
