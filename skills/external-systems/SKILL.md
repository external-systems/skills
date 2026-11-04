---
name: external-systems
description: "The owner's external-systems GitHub org: which core repo owns what (pkgs, skills, modules, not-secrets, secrets, home, clanServices), where clones live, which repo a change belongs in, and how every repo is built and changed: the one org-pkgs input and flakeModules.default, the devenv shell, nixd settings, lock sync, AGENTS.md, badges, the org CI (ci.yml calling pkgs org-ci.yml, Pages, releases), the branch ruleset, commits and pull requests, and the merge order across repos. Load before working in any org repo: creating or converging one, editing flake.nix wiring, devenv.yaml, .vscode, CI, rulesets or Pages, deciding where a package, module, skill, value or clan service goes, or opening, describing or sequencing PRs."
---

# external-systems — the org's repos

The owner's Nix setup is split across flakes in the **external-systems**
GitHub org. Each repo has one job, every repo has the same shape and CI,
and every change goes through a PR. Code style is the `nix-style` skill;
the docs site, deck and org look are the `org-docs` skill. Repo-specific
facts live in each repo's `AGENTS.md`: read it before editing there.

## The repos

Clones live in `~/external-systems/<repo>`, named exactly like the
GitHub repo (capital S in `clanServices`); look there before cloning. In
a cloud session check the working directory first.

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
| **pkgs** | The single nixpkgs, flake-parts and import-tree every repo follows. Packages and `overlays.{default,kubernetes,ifstate,tools}`, the code-agent image, `flakeModules.default` (also `.treefmt`, `.docs`), the org devenv shell (`org-pkgs/devenv`), the repo template, `org-ci.yml`. | Inventory, clan vars, fleet policy |
| **skills** | Every agent skill (`skills/`), external sources as `skills-*` inputs, presets, `mkSkillsTree`, `mkSkillsRuntime`, the skill checks and apps. See the `skills-repo` skill. | Secrets, IPs, hostnames |
| **modules** | Reusable NixOS (`nixosModules.*`, `hostSpec.*`) and home-manager (`homeModules.*`, `homeSpec.*`) modules, all off until enabled. `homeModules.agents` installs the skills tree. | Machines, users, packages, IPs, account ids |
| **not-secrets** | The values schema, `lib`, `flakeModules.{values,checks}`, public placeholder values (RFC 5737/3849/7042/2606 ranges only). | Any real value (`checks.placeholders-only`) |
| **secrets** | Private. Only `values/`: real addresses, interfaces, MACs, deploy targets, storage box ids. Same outputs as not-secrets; `checks.shape-parity`. | Credentials (those are clan vars) |
| **home** | The clan: `inventory.nix`, `machines/`, users and their home-manager profiles, home-only clan services, `sops/`, `vars/`. Deploys run from here. | Packages, overlays, reusable modules, skills, IP literals |
| **clanServices** | Standalone clan services (`k3s`, `rke2`, `netif`, `routed-fabric`, `wireguard-mesh`); `SPEC.md` is its contract. Not consumed by home yet; the Kubernetes machines still live in andrewthomaslee/borg. | Machines, real values |

Every other repo in the org is **standalone**: a project of its own
that follows the same standard and consumes pkgs, and that nothing
consumes. Its `AGENTS.md` says what it is.

How the links work:

- **Values:** a consumer reads `inputs.secrets.values.hosts.<machine>...`
  and never writes an address, interface or deploy target as a literal.
  home pins the private secrets repo (evaluating machines needs a token
  that can read it; the devenv shell sets it from `.env`). Public
  consumers pin not-secrets under the same input name.
- **Skills reach machines through modules:** `homeModules.agents` calls
  `inputs.skills.lib.mkSkillsTree` with each user's
  `homeSpec.agents.skills.{preset,extraSources}`.
- **clanServices** is added with `clanServices.inputs.clan-core.follows
  = "clan-core"` and referenced as `module.input = "clanServices"`.

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

## Every repo

Templates for every file, CI and ruleset details and the new-repo
procedure: [references/flake-standard.md](references/flake-standard.md).
Load it before creating a repo or changing a repo's wiring,
`devenv.yaml`, `.vscode/`, `documentation/`, CI, ruleset or Pages. New
repos start from `nix flake init -t github:external-systems/pkgs`.

- **A flake with docs and a deck.** `nix build .#<attr>` is the build
  interface; `documentation/docs/*.md` is the site,
  `documentation/slides/slides.md` the deck (`org-docs`).
- **One org input.** `org-pkgs.url = "github:external-systems/pkgs"`;
  `nixpkgs`, `flake-parts` and `import-tree` follow `org-pkgs/*`, and
  every other input follows those where it can. Never name it `pkgs`
  (the nixpkgs package set; clanServices is the legacy exception). One
  nixpkgs for the org: no second nixpkgs, no `pkgs.unstable`.
- **Imports `inputs.org-pkgs.flakeModules.default`**: treefmt (formatter,
  `checks.treefmt`), docs and slides as checks, `checks.lock-sync`,
  `apps.sync-locks`. Never copy them into a repo; a missing feature is a
  pkgs PR.
- **No dev partition**, no `dev/flake.nix`: every dev tool comes from
  org-pkgs. Repo checks and apps are ordinary modules (`flake-parts/`,
  `tests/flake-module.nix`). Only pkgs keeps one (its code-agent image
  needs modules). A heavy test-only input needs the owner's yes.
- **The devenv CLI shell.** `devenv.yaml` takes `org-pkgs`, follows
  `org-pkgs/nixpkgs`, imports `org-pkgs/devenv` (scripts `fmt`, `check`,
  `sync-locks`, `docs-build`, `docs`, `slides`; `devenv up` serves docs
  on :8981, slides on :8982). `devenv.nix` adds the repo's own tools. No
  flake `devShells`.
- **`.vscode/settings.json`** points nixd at the workspace flake
  (`builtins.getFlake (builtins.toString ./.)`), with `debug = true;` in
  `mkFlake`.
- **One nixpkgs in `flake.lock` and `devenv.lock`.** After
  `nix flake update org-pkgs`, run `sync-locks` in the same commit; never
  move nixpkgs with a bare `devenv update`.
- **The badge row** (ci, release, docs, license, built with Nix) under
  the title of `README.md` and `documentation/docs/index.md`, as in the
  template, minus badges the repo has no source for. Private repos get
  none: shields.io cannot see them.
- **`AGENTS.md`** (what the repo is, Layout, Build and check or Tool
  loop, Rules) and `CLAUDE.md` containing `@AGENTS.md`, kept in step
  with the code in the same PR.
- **No build output committed**: `result*`, `_site/`, `site/`,
  `documentation/site/`, `.devenv*` are gitignored; CI is the only
  publisher; no `gh-pages`.
- **Public unless it holds secrets.** No secret, IP, account,
  subscription or tenant id in any public file, commit or PR.

A repo that does not match is converged in its own PR; offer it rather
than doing it unasked.

## CI and ruleset

- **One CI:** `.github/workflows/ci.yml`, copied exactly from the pkgs
  template, calls pkgs `org-ci.yml`. One job, id `ci`, so the required
  check is **`ci / flake-check`** everywhere. Per repo only the `with:`
  keys change: `major`, `minor`, `private-repos`.
- `flake-check` runs `nix flake check` on PRs, the merge queue and
  `main`. On `main`, `deploy` publishes `.#documentation` to Pages
  (`<repo>.external.systems`) and `release` tags
  `<major>.<minor>.<git rev-list --count HEAD>`.
- **Change CI only in pkgs.** Never add steps, jobs or workflows in a
  repo; never `pull_request_target`. Pages: Settings → Pages → Source:
  GitHub Actions, once.
- **Ruleset** `.github/rulesets/default.json` (from the template): PRs
  only, squash only, linear history, signed commits, no force-push or
  deletion, `ci / flake-check` required on an up-to-date branch. GitHub
  does not read the file: apply it with `gh api` (the reference). GitHub
  Free: no org rulesets, no rulesets or Pages on private repos.

## Changing a repo

- **Never push to `main`.** Every change is a branch and a PR in the
  repo that owns it. One concern per PR, one PR per repo.
- **Before pushing:** `git add -A` (Nix only sees tracked files),
  `fmt`, `check`, and build what you touched.
- **Commits:** imperative subject naming the change, body says why. The
  PR is squash-merged and its title becomes the commit on `main`: make
  it a good one.
- **PR description:** What (file by file where it helps), Why, Checks
  (commands and results; what could not run, so CI covers it), plus what
  the reviewer must know: behaviour or URL changes, lock-size changes,
  merge order, monthly cost for infrastructure.
- **Agents never merge, approve, bypass or deploy** (`clan machines
  update`, `nixos-rebuild`): report the command for the owner.
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

## Migration state

On the standard, or converging in an open PR: pkgs, skills, modules,
not-secrets, secrets, home. Not yet: **clanServices** (input named
`pkgs`, old docs builder); leave it alone unless asked. not-secrets and
secrets have no org CI yet. Some standalone repos are not converged
either: check a repo's `flake.nix` before assuming the standard. Update this section in the PR that moves
a repo; delete it when every repo is converged.
