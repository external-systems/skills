---
name: external-systems
description: "The external-systems GitHub org and its standards: which repo owns what and where a change goes, flake and devenv wiring, CI, rulesets, worktrees, PRs and merge order, plus references for secrets (varlock and 1Password), NixOS VM tests, the euc-hel-0 remote builder, docs and slides, and agent skills. Load at the start of any work in an org repo or ~/external-systems, and whenever secrets, .env files, VM tests, remote builds, docs, slides or skills come up."
---

# external-systems — the org's repos

The owner's Nix setup is split across flakes in the **external-systems**
GitHub org. Each repo has one job, every repo has the same shape and CI,
and every change goes through a PR. The ground rules (clones on main,
worktrees, no deploys) are in your system prompt; if they are missing,
read `rules/ground-rules.md` in external-systems/skills
(`~/external-systems/skills`). Code style is the
`nix-style` skill. Repo-specific facts live in each repo's `AGENTS.md`:
read it before editing there.

## The repos

Clones live in `~/external-systems/<repo>`, named exactly like the
GitHub repo (capital S in `clanServices`); look there before cloning.
They stay on `main`; branches live in worktrees under
`~/external-systems/.worktrees/<repo>/<branch>`. In a cloud session
check the working directory first.

```
                    pkgs  (input name: org-pkgs)
   nixpkgs, flake-parts, import-tree, overlays, packages,
   flakeModules.default, the devenv shell, the repo template
        |               |              |            |
     skills        not-secrets    clanServices   every repo's
        |               |                        flake.nix and
        v               v                        devenv
     modules         secrets
        |               |
        v               v
  ==================  home  ==================
     clan machines, inventory, users, deploys
```

A repo never imports something below it: pkgs knows nothing about
machines, modules nothing about users or IPs, and only home names
machines.

| Repo | Owns | Never holds |
|---|---|---|
| **pkgs** | The single nixpkgs, flake-parts and import-tree every repo follows. Packages and `overlays.{default,kubernetes,ifstate,tools}`, `flakeModules.default` (also `.treefmt`, `.docs`, `.vmTests`, `.python`), the org devenv shell (`org-pkgs/devenv`, `org-pkgs/devenv/python`), the repo template, `org-ci.yml`. | Inventory, clan vars, fleet policy |
| **skills** | Every agent skill (`skills/`), external sources as `skills-*` inputs, presets, `mkSkillsTree`, `mkSkillsRuntime`, the skill checks and apps. See [references/skills-repo.md](references/skills-repo.md). | Secrets, IPs, hostnames |
| **modules** | Reusable NixOS (`nixosModules.*`, `hostSpec.*`) and home-manager (`homeModules.*`, `homeSpec.*`) modules, all off until enabled. `homeModules.agents` installs the skills tree. | Machines, users, packages, IPs, account ids |
| **not-secrets** | The values schema, `lib`, `flakeModules.{values,checks}`, public placeholder values (RFC 5737/3849/7042/2606 ranges only). | Any real value (`checks.placeholders-only`) |
| **secrets** | Private. Only `values/`: real addresses, interfaces, MACs, deploy targets, storage box ids. Same outputs as not-secrets; `checks.shape-parity`. | Credentials (those are clan vars) |
| **home** | The clan: `inventory.nix`, `machines/`, users and their home-manager profiles, home-only clan services, `sops/`, `vars/`. Deploys run from here. | Packages, overlays, reusable modules, skills, IP literals |
| **clanServices** | Standalone clan services (`k3s`, `rke2`, `netif`, `routed-fabric`, `wireguard-mesh`); `SPEC.md` is its contract. home consumes `remote-builder`; the Kubernetes machines still live in andrewthomaslee/borg. | Machines, real values |

Every other repo in the org is **standalone**: a project of its own
that follows the same standard and consumes pkgs, and that nothing
consumes. Its `AGENTS.md` says what it is.

How the links work:

- **Values:** a consumer reads `inputs.secrets.values.hosts.<machine>...`
  and never writes an address, interface or deploy target as a literal.
  home pins the private secrets repo (evaluating machines needs a token
  that can read it; the devenv shell sets it from `GH_TOKEN` or `gh auth token`). Public
  consumers pin not-secrets under the same input name.
- **Skills reach machines through modules:** `homeModules.agents` calls
  `inputs.skills.lib.mkSkillsTree` with each user's
  `homeSpec.agents.skills.{preset,extraSources}`.

## Where a change goes

| The change | Repo |
|---|---|
| A package, overlay, container image, pinned binary or chart | pkgs |
| Formatting, docs/slides build, devenv shell, CI, the repo template | pkgs |
| A NixOS or home-manager module, a `hostSpec`/`homeSpec` option | modules |
| A skill, a skill source, a preset or a skill check | skills |
| A new value field or section (schema) | not-secrets, then secrets |
| A real IP, MAC, interface, domain or storage box id | secrets (plus a placeholder in not-secrets) |
| A clan service for more than one fleet | clanServices |
| A machine, a user profile, an inventory instance, a user's skills | home |

## Org standards

Read the linked file or skill when a task touches the standard.

| Standard | The rule | Detail |
|---|---|---|
| Repo shape | One `org-pkgs` input, `flakeModules.default`, devenv shell, git hooks, org CI, ruleset, docs, `AGENTS.md` | [references/flake-standard.md](references/flake-standard.md) |
| Secrets | Tooling secrets live in 1Password and load through varlock (`.env.schema` committed, no `.env` values); machine secrets are clan vars | [references/secrets.md](references/secrets.md) |
| Git and PRs | Clones on `main`, one worktree per branch, squash PRs, upstream merges first | the ground rules, "Changing a repo" and "Merge order" below |
| Nix code | treefmt (alejandra, deadnix, statix, nixf-diagnose), nesting and quoting rules, `fmt` then `check` | the `nix-style` skill |
| Docs and slides | Plain Markdown in `documentation/`, built by `flakeModules.docs`, published to Pages by CI | [references/org-docs.md](references/org-docs.md) |
| VM tests | `vm-tests/*.nix`, never in `checks` or CI, run with `vm-test` on KVM or `--remote` | [references/vm-tests.md](references/vm-tests.md), [references/vm-tests-recipes.md](references/vm-tests-recipes.md) |
| Builds | euc-hel-0 takes builds automatically; never weaken its SSH | [references/remote-builder.md](references/remote-builder.md) |
| Python | uv workspace, `flakeModules.python`, ruff and ty | the `uv2nix` skill |
| Agent skills | Every skill in external-systems/skills, picked per user in home | [references/skills-repo.md](references/skills-repo.md) |
| Clan fleet | Machines, inventory and vars only in home; vars generated on a branch | home's `AGENTS.md`, the `clan-core` skill |

A new org standard is one row here plus `references/<topic>.md`; a
whole technology with its own trigger words is its own skill instead.
This file stays a router: `checks.router-size` keeps it under 10,000
characters.

## Changing a repo

- **Never push to `main`.** Every change is a branch in its own
  worktree (the ground rules) and a PR in the repo that owns it. One concern per PR, one PR per repo.
- **Before pushing:** `git add -A` (Nix only sees tracked files),
  `fmt`, `check`, and build what you touched. `check` is
  `nix run .#flake-check`: it fails on dangerous evaluation warnings
  (`evalWarnings.deny`: ignored, removed or insecure config) and lists the
  rest, which may wait.
- **GitHub from the shell:** read repo settings with
  `gh api repos/external-systems/<repo> --jq '<fields>'` (`gh repo view
  --json` lacks settings such as `allow_auto_merge`). On the private
  `secrets` repo the token cannot read a PR's `statusCheckRollup`; read
  CI with `gh run list -b <branch> --json status,conclusion`.
- **Private inputs outside devenv** (home evaluating `secrets`): Nix gets
  a 404 without a token. The devenv shell sets it from `GH_TOKEN` or
  `gh auth token`; for one
  command, `NIX_CONFIG="access-tokens = github.com=$(gh auth token)"`.
- **Commits:** imperative subject naming the change, body says why. The
  PR is squash-merged and its title becomes the commit on `main`: make
  it a good one.
- **PR description:** What (file by file where it helps), Why, Checks
  (commands and results; what could not run, so CI covers it), plus what
  the reviewer must know: behaviour or URL changes, lock-size changes,
  merge order, monthly cost for infrastructure.
- **Agents never merge, approve, bypass or deploy** (`clan machines
  update`, `nixos-rebuild`): report the command for the owner. The one
  exception: the owner explicitly allows merging (or auto-merge) for a
  named repo in the session; it never covers deploys.
- **A repo with its own gates** (infrastructure plans and applies) says
  so in its `AGENTS.md`; those gates come on top of these rules.

## Merge order across repos

Upstream first; each consumer bumps its input in its own PR after the
upstream merges. Say the order in every PR of a cross-repo change.

1. **pkgs.** Consumers run `nix flake update org-pkgs`, then `sync-locks`
   in the same commit.
2. **not-secrets, then secrets** (`nix flake update not-secrets`).
3. **skills, then modules** (`nix flake update skills`).
4. **home last:** `nix flake update modules secrets` (and `org-pkgs`).

clanServices and the standalone repos consume pkgs only. To test before the
upstream merges:

- **Locally**, one command only:
  `nix flake check --override-input modules path:$HOME/external-systems/modules`.
- **In the consumer PR's CI**, lock the upstream PR's head commit
  (`nix flake lock --override-input org-pkgs github:external-systems/pkgs/<sha>`),
  say so in the PR, and re-lock to `main` once it merges.

Never commit a `path:` lock.
