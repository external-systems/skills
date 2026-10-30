---
name: nix-style
description: "Nix code style, tool loop and the org flake standard (user preferences): attribute nesting/quoting/inherit rules, module-system and repo-root-path conventions, treefmt (alejandra, deadnix, statix, nixf-diagnose, shellcheck, sizelint) via external-systems/pkgs flakeModules, the devenv CLI shell (devenv.yaml importing org-pkgs/devenv), the dev flake-parts partition holding checks, formatter and MkDocs/reveal.js docs with its own dev/flake.lock, lock sync, the pkgs repo template, and the flake-repo agent contract. Use when writing or editing any .nix file, creating a new flake repo, or adding a formatter, linter, dev shell or docs to one."
---

# nix-style — Nix code style and tool loop

How to write and change Nix code in flake repos: the style guide, the
mandatory verification tool loop, and the working rules. These are user
preferences — apply them in any repo the owner works in, not just this
one. Repo-specific facts live in each repo's `AGENTS.md`.

## Non-negotiables (flake repos)

- Flakes only. `nix build .#<attr>` is *the* build interface. No
  `nix-build`, no `shell.nix`/`default.nix` entry points, no channels, no
  `<nixpkgs>` / `NIX_PATH` lookups.
- `flake.lock` is committed. Update it with `nix flake update <input>` or
  `nix flake update <name>`; never hand-edit the lock file.
- Nix evaluates the flake from the git tree. `git add` every new file
  (`.nix`, test files, skills, assets) before `nix build` /
  `nix flake check` — untracked files do not exist to Nix.
- No secrets in Nix source or the store (it is world-readable). Secrets
  come from a provisioning layer (sops-nix, clan vars, CI OIDC, GitHub
  Actions secrets), never from expressions — clan vars are documented in
  the `clan-core` skill.
- Every flake repo follows the org flake standard: inputs follow
  external-systems/pkgs, and checks, formatter, devShells and apps live
  in a `dev` flake-parts partition with its own `dev/flake.nix` and
  `dev/flake.lock`, so treefmt-nix, devenv and docs inputs never reach
  the main `flake.lock`. See [Org flake standard](#org-flake-standard).
- Never reach for `--impure`, `--no-sandbox`, `sandbox = false`, or
  `builtins.readFile /etc/...` to make something build. Impurity hides
  bugs, breaks FlakeHub Cache reproducibility, and fails on CI. If
  something needs the outside world, make it an input (a flake input, a
  store path, a test fixture) instead.

## Org flake standard

One shape for every flake repo, new or old. A developer needs Nix and
devenv, nothing else. Start new repos with
`nix flake init -t github:external-systems/pkgs`. Templates for every
file, the lock-sync rules and the new-repo and converge procedures are
in [references/flake-standard.md](references/flake-standard.md); load it
before creating a flake repo or touching a repo's partition wiring,
`dev/`, `devenv.yaml`/`devenv.nix` or `documentation/`.

- **Inputs**: `org-pkgs.url = "github:external-systems/pkgs"`, with
  `nixpkgs`, `flake-parts` and `import-tree` following `org-pkgs/*`.
  The input is never named `pkgs` (in `flake.nix` or `devenv.yaml`):
  `pkgs` always means the nixpkgs package set. Every
  other input follows them where it can.
- **Partition**: `partitionedAttrs` sends `apps`, `checks` and
  `formatter` to `dev`; `partitions.dev = {module =
  ./dev/flake-module.nix; extraInputsFlake = ./dev;}`. `packages` stay at
  the root.
- **Dev inputs** (`dev/flake.nix`, locked in `dev/flake.lock`):
  `dev-nixpkgs`, `treefmt-nix`, `presenting`, and any test-only inputs.
- **Shared flake module**: the dev partition imports
  `inputs.org-pkgs.flakeModules.dev` (org linters via treefmt,
  `checks.lock-sync`, `apps.sync-locks`, docs and slides as checks).
  Never copy the treefmt program list into a repo.
- **Dev shell = devenv CLI only**: `devenv.yaml` takes `org-pkgs`
  (devenv would let an input named `pkgs` shadow nixpkgs' `pkgs`),
  follows `org-pkgs/nixpkgs`, and imports `org-pkgs/devenv`
  (the org shell: `fmt`,
  `check`, `sync-locks`, `docs-build`, `docs`, `slides`; `devenv up`
  serves docs on :8981 and slides on :8982). `devenv.nix` adds the repo's languages, services and
  processes. No flake `devShells`, no `inputs.devenv.flakeModule`.
- **Docs and slides in every repo**: `documentation/module.nix` imports
  `inputs.presenting.flakeModules.default` (the `mkdocs-reveal` skill),
  from the dev partition only. `nix build .#documentation` builds the
  static site (via `legacyPackages`, partitioned to `dev`); open
  `result/index.html` from disk.
- **One nixpkgs across three locks**: `flake.lock`, `dev/flake.lock`,
  `devenv.lock`. After `nix flake update org-pkgs`, run `sync-locks` in the
  same commit.

A repo that does not match yet still gets the style rules below; offer to
converge it rather than doing it unasked.

## Style guide

### Attribute nesting

Nest attribute sets; one path segment per level, and never repeat a prefix
across sibling lines. Keys with a single member stay flat dotted; keys
with two or more members are written once and nested:

```nix
# good: single members flat, multi-member keys nested once
{
  homeSpec = {
    programs = {
      firefox.enabled = true;
      spotify.enabled = true;
    };
    shell.bash.enabled = true;
  };
}

mcp = {
  nix.enable = true;             # single member: flat
  github = {                     # three members: nested once
    enable = true;
    auth = "pat";
    patFile = "/path/to/pat";
  };
};
```

```nix
# bad: quoted identifiers, repeated prefixes (quoted or not), mixed styles
{
  homeSpec."programs".firefox.enabled = true;
  homeSpec."programs".spotify.enabled = true;
  homeSpec.shell.bash.enabled = true;
}

mcp = {
  "nix".enable = true;
  "github".enable = true;
  "github".auth = "pat";
  "github".patFile = "/path/to/pat";
};
```

statix's `repeated_keys` lint only fires on 3+ adjacent repeats; this rule
is stricter — 2+ assignments of the same prefix in one attrset are a
violation, adjacency irrelevant. Enforce it while writing, not by waiting
for the linter.

### Attribute keys and quoting

Attribute keys are identifiers, and Nix identifiers legally contain
hyphens (`cloudflare-docs`, `opencode-mem`) and trailing apostrophes
(`self'`). Identifier keys are therefore **never quoted**:

```nix
# good
mcp = {
  cloudflare.enable = true;
  cloudflare-docs.enable = true;
};
```

```nix
# bad: unnecessary quotes
mcp = {
  cloudflare.enable = true;
  "cloudflare-docs".enable = true;
};
```

Quote a key only when it is not an identifier: it contains `/` or `.`
(`xdg.configFile."opencode/skills"`, `etc."vm-mcp-probe.py"`) or starts
with a digit. When a quoted key has multiple members, quote it once at its
own nesting level, never per sibling line. camelCase is preferred for new
multi-word keys but not enforced — keep existing names, never rename for
style.

### Boolean toggles

For boolean toggles you control (new options, new modules), prefer
`setting.enabled = true` over `setting.enable = true` where possible.
Not strictly enforced: standard NixOS and home-manager options are named
`enable` (`mkEnableOption` generates `enable`), and existing options are
never renamed for this — apply it where the naming is yours to choose.

### inherit

One `inherit (source) ...` statement per source per attrset. Never split
members of the same source across two `inherit` statements:

```nix
# good
services.ollama = {
  inherit (cfg) package port loadModels;
};

# bad: duplicated source
services.ollama = {
  inherit (cfg) package;
  inherit (cfg) port loadModels;
};
```

statix's `manual_inherit_from` lint converts `x = cfg.x;` into `inherit
(cfg) x;` but does not merge duplicates — consolidate by hand.

### Repo-root paths

Reference repo-root paths through a single repo-provided helper, never
through fragile `../../` chains in module code, and never by defining a
local `relativeToRoot = lib.path.append ../../.` clone. If the repo has no
such helper, define one once (typically as `customLib` in flake-parts) and
thread it everywhere: NixOS modules get it via `_module.args`, home-manager
modules via `home-manager.extraSpecialArgs` — set both once in the default
module, not per clan service, or consumers outside clan's module set
(packages, VM tests) lose it.

Home repo example: `customLib.custom.relativeToRoot`
(`relativeToRoot "skills"`), exposed as `customLib` via `_module.args` and
`home-manager.extraSpecialArgs`, both set in `nixosModules/default`.

One hard exception: a NixOS module whose **config value** needs a
repo-root path cannot take the helper as a module arg — args are
resolved lazily through `config._module.args`, which is circular while
`config` itself is being evaluated (clan machine evals die with
`attribute '<helper>' missing`). There, read the file with a direct path
literal and comment why:

```nix
# home repo example: machines.json lives at the repo root; a module arg
# here would be circular (config._module.args lookup while config
# is evaluating)
machinesJson = builtins.fromJSON (builtins.readFile ./../../machines.json);
```

Home-manager modules are unaffected — `extraSpecialArgs` is a separate
eval channel, so the helper is always safe there.

### Module system

- Options: `lib.mkEnableOption` for booleans; `lib.mkOption` always with
  `type`, `default`, and a `description` (write it for the next reader).
- Option namespaces: use one namespace per concern (`hostSpec.*`/`homeSpec.*`
  in the home repo — or the repo's equivalent) so modules compose without
  collisions.
- Set values with `lib.mkIf`, `lib.mkDefault`, `lib.mkMerge`, and
  `lib.mkForce` (sparingly — `mkForce` is a smell in library code). Use
  `lib.optionals`/`lib.optional` instead of `++ (if c then [...] else [])`.
- `assertions = [ { assertion = ...; message = "user-facing: ..."; } ]` for
  mutual exclusions and config invariants — an error message a user can act
  on beats a weird eval failure.

### Language mechanics

- `inherit` from enclosing scopes (`{inherit inputs self pkgs;}`); the
  formatter aligns it, let it.
- `with pkgs;` only inside a small list literal where it reads better
  (`(with pkgs.unstable; [ ... ])`); never `with` around a whole module
  body or over `lib`.
- Comments explain *why*, not *what* — especially for pins, workarounds,
  and anything a future reader would be tempted to "clean up". Include
  the bug link where a workaround exists.
- One concern per file; let the repo's auto-import mechanism pick it up
  (flake-parts + import-tree style: new files are auto-loaded, there is
  no import list to update) — see the `import-tree` skill.

### Formatting

treefmt is the formatter (`nix fmt`, from `flakeModules.treefmt`). It
runs alejandra (layout), deadnix (`no-lambda-pattern-names`), statix,
nixf-diagnose, shellcheck and sizelint in one pass. alejandra owns the
layout: never hand-format Nix, never fight its choices, never merge
conflict over whitespace. After every edit:

```
nix fmt                       # format + autofix the whole tree
nix flake check               # checks.treefmt fails on any diff
```

With treefmt, a bare `nix fmt` formats the tree. In a repo not yet
converged (`formatter = pkgs.alejandra`), pass a path: `nix fmt .` — a
bare `nix fmt` there makes alejandra read empty stdin and exit 1.

### Enforcement

What CI automates (`checks.treefmt`, built by `nix flake check`):

| Tool | Catches |
|---|---|
| alejandra | formatting |
| deadnix | unused bindings (lambda pattern names are tolerated) |
| statix | anti-patterns, incl. `repeated_keys` (3+ adjacent) and `manual_inherit*` |
| nixf-diagnose | removed `builtins` primop prefixes |
| shellcheck | shell scripts |
| sizelint | oversized files |

What is convention the agent must enforce itself (CI cannot see it):

- quoting rule — no quotes on identifier keys
- 2+-member nesting (statix needs 3+ adjacent repeats)
- inherit consolidation
- `relativeToRoot` for repo-root paths
- `enabled` preference
- the org flake standard (no dev-only input in the main lock)

Fix violations in passing whenever you touch a file; write new code right
the first time. When a rule and a linter disagree, the rule wins — and if
a linter's suggestion would violate a rule (e.g. `inherit` with double
parentheses), restructure so both are satisfied.

## Tool loop (mandatory)

Run this loop before claiming any Nix work is done — in order (inside
the devenv shell, `fmt` and `check` are scripts for steps 2 and 3):

```
1. git add -A                     # nix only sees tracked files
2. nix fmt                        # treefmt: format + lint fixes
3. nix flake check --show-trace   # treefmt, lock-sync, docs, every check
4. nix build .#<thing-you-touched> -L   # real build, -L = logs
```

Filtering check output: result lines are plain UTF-8 (✅ pass, ❌ fail),
so a literal grep works — `2>&1` is required, the lines go to stderr:

```
nix flake check --show-trace 2>&1 | grep -E "^✅|^❌"   # results only
nix flake check 2>&1 | grep -cE "^✅"                   # count passes
nix flake check 2>&1 | grep -E "❌|error:" -A 5          # failures + trace
```

treefmt applies statix and deadnix fixes in place; review the diff
before committing. When `checks.treefmt` fails, run `nix fmt` and commit
the result; a failure that `nix fmt` cannot fix (shellcheck, sizelint,
nixf-diagnose) prints the finding — fix the source.

Repos not yet converged (no treefmt): run `nix fmt .`, `statix check .`,
`deadnix --fail .` (all in their devShell, or via
`nix run nixpkgs#<tool> --`), and when fixing mechanically, run
`deadnix -e .`, then `statix fix .`, then `nix fmt .`.

Paste the last failing/passing command and its exit status when
reporting results. "It should work" is not verification.

## DevShell and the agent

Flake repos gate tooling and tokens behind their devShell — the devenv
CLI shell (`devenv.yaml`) in converged repos. The agent
process (opencode) is spawned inside `nix develop` 98% of the time —
the formatter, linters, and repo tooling are already on PATH, and any
secrets/tokens the repo injects are already exported. When inside, do
NOT wrap commands in `nix develop -c "command"`: it re-evaluates the
flake, spawns a nested shell, and can double-run shellHook side effects.

How to tell you are inside:

- nix sets `IN_NIX_SHELL` itself, however the shell was entered
  (`nix develop`, direnv `use flake`, `-c`): `impure` for a default
  shell, `pure` for `--pure`. Verify with `printenv IN_NIX_SHELL`.
- Secondary signals: the repo shellHook's exported markers and the
  devShell closure on PATH (`/nix/store/...-nix-shell-env/bin`).

Invocation rule: if `IN_NIX_SHELL` is set, run tools directly
(`nix fmt .`, `statix check .`, `clan ...`). Reach for
`nix develop -c '...'` or `nix run nixpkgs#tool` only when verification
shows you are NOT inside — fresh CI checkout, bare SSH session,
non-interactive wrapper.

Secret injection (home repo example): the devShell shellHook sets
`CLAN_DIR=$REPO_ROOT` and runs `eval "$(bunx varlock load --format
shell)"`, which loads the gitignored `.env` (schema `.env.schema`) and
exports `SOPS_AGE_KEY`, `SOPS_AGE_PUBLIC_KEY`, `GITHUB_TOKEN`, and
`TF_VAR_flakehub_token` — sops, clan vars, and GitHub tooling work
without extra setup. The generic pattern: repos inject the tokens their
tooling needs (sops, clan vars, CI) into the devShell. Assume present;
verify with `printenv <NAME>` (presence, not value), never echo secret
values into output or logs, and never manually source or re-load them.

## Working in a flake repo (agent contract)

1. Read `flake.nix` and the neighbouring module *before* editing; mirror
   the local patterns (namespaces, mkMerge usage, overlay routing) instead
   of importing your own style.
2. Never guess option or package names. Look them up (the `nixos` MCP
   tool, search.nixos.org) and verify the exact attribute path — a repo
   may pin versions or scope packages under `pkgs.unstable` via an
   overlay.
3. Generated files (`flake.lock`, disko layouts, `facter.json`, clan
   `inventory.json`) are not hand-editable. Regenerate them with their
   generator, or leave them alone.
4. Prefer the smallest change that satisfies the request; do not refactor
   modules you did not need to touch.
5. Verify per the tool loop, and state which command verified the change.
   If you cannot build it (missing hardware, no KVM), say so explicitly.
