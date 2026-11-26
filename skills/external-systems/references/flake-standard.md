# Org flake standard: templates and procedures

Every flake repo under external-systems (and the owner's personal flake
repos) has the same shape. A developer needs Nix (sandbox on, the default)
and devenv, nothing else. The devenv CLI is the only dev shell; the flake is
the build and consumer interface. A repo has one org input, `org-pkgs`:
formatting, docs and slides come from pkgs' own flake modules, so there
is no `dev/flake.nix`, no `dev/flake.lock` and no dev partition. Every
repo ships a docs site and a slide deck.

The canonical source is `nix flake init -t github:external-systems/pkgs`
(pkgs `templates/default`). Prefer it over copying the snippets below; the
snippets explain what the template contains.

## The standard at a glance

The sections after this one hold the templates and procedures.

- **A flake with docs and a deck.** `nix build .#<attr>` is the build
  interface; `documentation/docs/*.md` is the site,
  `documentation/slides/slides.md` the deck ([org-docs.md](org-docs.md)).
- **One org input.** `org-pkgs.url = "github:external-systems/pkgs"`;
  `nixpkgs`, `flake-parts` and `import-tree` follow `org-pkgs/*`, and
  every other input follows those where it can. Never name it `pkgs`
  (the nixpkgs package set). One
  nixpkgs for the org: no second nixpkgs, no `pkgs.unstable`.
- **Imports `inputs.org-pkgs.flakeModules.default`**: treefmt (formatter,
  `checks.treefmt`), docs and slides as checks, VM tests,
  `checks.lock-sync`, `apps.sync-locks`, and Python (uv2nix, ruff, ty)
  when `pyproject.toml` + `uv.lock` exist. Never copy them into a repo; a
  missing feature is a pkgs PR.
- **Python repos** add no input: a uv workspace at the root, `org-pkgs/devenv/python`
  in `devenv.yaml`, `pyproject.toml` version `<major>.<minor>.0` matching
  ci.yml (Nix stamps the commit count). Consumers take a Python repo as
  `git+https://…?ref=main` for its exact version. The `uv2nix` skill.
- **No dev partition**, no `dev/flake.nix`: every dev tool comes from
  org-pkgs. Repo checks and apps are ordinary modules (`flake-parts/`,
  `tests/flake-module.nix`). A heavy test-only input needs the owner's
  yes.
- **The devenv CLI shell.** `devenv.yaml` takes `org-pkgs`, follows
  `org-pkgs/nixpkgs` and `org-pkgs/git-hooks`, imports `org-pkgs/devenv`
  (scripts `fmt`, `check`, `sync-locks`, `docs-build`, `docs`, `slides`,
  `worktree`; `devenv up` serves docs on :8981, slides on :8982).
  `devenv.nix` adds the repo's own tools. No flake `devShells`.
- **Git hooks, always.** Every org repo has them, the same way it has
  the devenv shell: no opt-out. The org shell installs a `pre-commit` hook
  that runs `nix fmt -- --ci` (cachix/git-hooks.nix through devenv, run by
  prek). devenv reads inputs only from the repo's own `devenv.yaml`, so
  every repo has `git-hooks: {follows: org-pkgs/git-hooks}` there and
  `.pre-commit-config.yaml` in `.gitignore` (the shell writes it as a link
  into the store; without the ignore, `git add -A` commits it).
  `checks.git-hooks` (`flakeModules.default`) fails CI when either is
  missing; without the input the shell does not start. Moving a repo to
  a pkgs with hooks: `nix flake update org-pkgs`, `nix run .#sync-locks`
  (outside the shell, which cannot start yet), then the two lines and
  `devenv shell -- true`. Repo hooks go
  in `devenv.nix` (`git-hooks.hooks.<name>`, `pass_filenames = false`,
  `stages`) and stay fast; a full `check` is not a hook. Worktrees share
  the clone's hooks but each reads its own config: a worktree that never
  entered the shell cannot commit (`config file not found`), so enter it
  once (`worktree new` does). A branch from before its repo had hooks:
  rebase onto `main`. Hooks are local feedback; CI stays the gate. Never
  skip them (ground rules).
- **`.vscode/settings.json`** points nixd at the workspace flake
  (`builtins.getFlake (builtins.toString ./.)`) and nixpkgs with the org
  overlay, with `debug = true;` in `mkFlake`.
- **One nixpkgs in `flake.lock` and `devenv.lock`** (and one git-hooks).
  After `nix flake update org-pkgs`, run `sync-locks` in the same commit;
  never move nixpkgs with a bare `devenv update`.
- **The badge row** (ci, release, docs, license, built with Nix) under
  the title of `README.md` and `documentation/docs/index.md`, as in the
  template, minus badges the repo has no source for. Private repos get
  none: shields.io cannot see them.
- **`AGENTS.md`** (what the repo is, Layout, Build and check or Tool
  loop, Rules) and `CLAUDE.md` containing `@AGENTS.md`, kept in step
  with the code in the same PR.
- **No build output committed**: `result*`, `_site/`, `site/`,
  `documentation/site/`, `.devenv*`, `.pre-commit-config.yaml` are
  gitignored; CI is the only
  publisher; no `gh-pages`.
- **Public unless it holds secrets.** No secret, IP, account,
  subscription or tenant id in any public file, commit or PR. Secrets a
  repo's tooling needs come from 1Password through varlock
  ([secrets.md](secrets.md)).

A repo that does not match is converged in its own PR; offer it rather
than doing it unasked.

### CI and ruleset

- **One CI:** `.github/workflows/ci.yml`, copied exactly from the pkgs
  template, calls pkgs `org-ci.yml`. One job, id `ci`, so the required
  check is **`ci / flake-check`** everywhere. Per repo only the `with:`
  keys change: `major`, `minor`, `private-repos`, `pages`.
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
  does not read the file: apply it with `gh api` (below). GitHub
  Free: no org rulesets, no rulesets or Pages on private repos.
  `pages: false` under `with:` keeps a repo's docs unpublished
  (secrets).

## Consuming clanServices

A clan repo adds external-systems/clanServices with
`clanServices.inputs.org-pkgs.follows = "org-pkgs"` and
`clanServices.inputs.clan-core.follows = "clan-core"`, and an inventory
instance references it as `module.input = "clanServices"`.

## What pkgs provides

| Piece | Gives |
|---|---|
| `inputs.org-pkgs.flakeModules.treefmt` | org linters: `formatter`, `checks.treefmt` |
| `inputs.org-pkgs.flakeModules.docs` | MkDocs site + reveal.js deck: `packages.documentation`, `packages.slides`, `apps.watch-documentation`, `apps.serve-slides` ([org-docs.md](org-docs.md)) |
| `inputs.org-pkgs.flakeModules.python` | Python repos (`pyproject.toml` + `uv.lock` at the root, switches itself on): uv2nix packages versioned `<major>.<minor>.<commits>`, apps, `checks.python-{pytest,ty,uv-lock,version}`, ruff in treefmt, `vmTests.python-cli` (the `uv2nix` skill) |
| `inputs.org-pkgs.flakeModules.default` | treefmt + docs + vmTests + python, `checks.lock-sync`, `checks.git-hooks`, `apps.sync-locks`, `documentation`/`slides` as checks |
| `org-pkgs/devenv` (devenv.yaml `imports`) | the org shell: `fmt`, `check`, `sync-locks`, `docs-build`, `docs`, `slides` scripts; `devenv up` serves docs :8981 and slides :8982; `devenv test` gates |
| `org-pkgs/devenv/python` (devenv.yaml `imports`, Python repos) | the editable uv2nix venv, `uv`, `ruff`, `ty`, the uv settings |
| `templates.default` | the whole layout below |

The flake modules are bound to pkgs' own inputs (`treefmt-nix`,
`reveal-js`; MkDocs comes from the org nixpkgs), so a repo declares no
dev input. They add two small nodes to every `flake.lock`, fetched only
when formatting or building docs. Never copy the treefmt program list,
the docs module or the org shell into a repo.

## Layout

```
flake.nix / flake.lock      inputs follow org-pkgs; imports
                            inputs.org-pkgs.flakeModules.default
flake-parts/                the repo's modules (import-tree), including
                            docs.nix (docs.* settings) and repo checks
devenv.yaml / devenv.lock   the shell: org-pkgs input, nixpkgs and
                            git-hooks follow org-pkgs, imports
                            org-pkgs/devenv
devenv.nix                  this repo's languages, services, processes
documentation/              docs/*.md, slides/slides.md (no Nix, no
                            mkdocs.yml, no deck index.html)
.github/workflows/ci.yml    the org CI caller (see Org CI)
.github/rulesets/default.json  the org branch ruleset
AGENTS.md, README.md, .gitignore (result*, .devenv*, devenv.local.nix,
                            _site/, site/, .pre-commit-config.yaml)
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
        # treefmt, docs + slides, lock-sync: everything from pkgs.
        inputs.org-pkgs.flakeModules.default
        (inputs.import-tree ./flake-parts)
      ];
    };
}
```

- No dev partition: every dev tool comes from org-pkgs, which every
  repo already locks. pkgs alone keeps one, because its code-agent image
  needs external-systems/modules, which depends on pkgs.
- A repo that genuinely needs a dev-only input its consumers must not
  lock (a heavy test framework, say) asks first; then it adds a
  partition for that input alone, never for formatting or docs.
- No `devShells` output: the shell is devenv. Never add a flake devShell
  or `inputs.devenv.flakeModule`.
- Repo checks and maintainer apps are ordinary modules under
  `flake-parts/`.
- pkgs itself has no `org-pkgs` input: it owns `nixpkgs`, `flake-parts`,
  `import-tree`, `treefmt-nix` and `reveal-js` directly and imports its
  modules by path.

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

- `devenv.nix` is a plain devenv module. The repo's own flake outputs
  are not visible there; anything it needs from another flake comes in
  as a `devenv.yaml` input (following `nixpkgs`). Inputs are whole
  flakes: org devenv modules call `inputs.org-pkgs.lib.*`.
- Repo-scoped commands are devenv `scripts` (or `tasks`); long-running
  dev services are `processes`/`services`. Consumer-facing commands are
  root flake `apps`/`packages`.
- Never edit the pkgs rev in `devenv.yaml` by hand: `sync-locks` owns it.
- Activation: `devenv hook <shell>` once per machine in the shell rc, then
  `devenv allow` once per checkout.

## documentation/ and docs settings

`documentation/docs/*.md` is the site and `documentation/slides/slides.md`
the deck; `flakeModules.docs` finds both by convention and generates the
MkDocs config (org defaults: the org style, Material, `search` + `offline`, Mermaid,
emoji, `use_directory_urls: false`, so the build browses from `file://`) and the
deck's `index.html`. Ports are module options (docs 8981, slides 8982),
not `dev_addr`. Settings that differ go in `flake-parts/docs.nix`:

```nix
_: {
  perSystem.docs = {
    repo = "<repo>"; # site_url https://<repo>.external.systems/, repo + edit links
    settings.site_name = "external-systems <repo>";
    # settings.nav = [...];  slides.title = "...";  (org-docs.md)
  };
}
```

The deck iframe on a docs page uses a relative path
(`src="slides/index.html"` from the site root) so it also loads from
`file://`.

Preferred docs loop: `docs-build` (or `nix build .#documentation`), then
open `result-docs/index.html` (or `result/index.html`) straight from
disk, for example `firefox result/index.html`. No server process runs.
`devenv up` (live reload on :8981, slides on :8982) is for heavy editing
sessions.

The org style, deck format, embedding and GitHub Pages: [org-docs.md](org-docs.md).

## nixd settings

Every repo commits `.vscode/settings.json` from the template and sets
`debug = true;` in `mkFlake` (exposes `debug.options` and
`currentSystem.options`; lazy, consumers never evaluate them). nixd
evaluates `./.` from the workspace root, so one file fits every clone.
Top-level keys are VS Code setting IDs (`nix.serverPath`), written
dotted: see the JSON nesting exception in the `nix-style` skill. The
nixpkgs expression applies `org-pkgs.overlays.default` (pkgs itself:
`f.overlays.default`), so hover and completion show org packages with
their versions. Python repos add the python/ty/ruff settings and
extensions from the template (the `uv2nix` skill).

```json
{
  "nix.enableLanguageServer": true,
  "nix.serverPath": "nixd",
  "nix.serverSettings": {
    "nixd": {
      "nixpkgs": {
        "expr": "let f = builtins.getFlake (builtins.toString ./.); in import f.inputs.nixpkgs { overlays = [ f.inputs.org-pkgs.overlays.default ]; }"
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
  `./tests/clan-stub.nix` (a module that reads `clan.core` fails the whole
  option set otherwise); `home-manager` evaluates
  `f.inputs.home-manager.lib.homeManagerConfiguration` with
  `f.homeModules.default` and plasma-manager.
- Machine repos: `f.nixosConfigurations.<name>.options`, and
  `.options.home-manager.users.type.getSubOptions []` for home-manager.

Test an expression before committing it:
`nix eval --impure --expr 'builtins.attrNames (<expr>)'` from the repo
root. `nixd` (org shell `languages.nix.enable`, which also adds statix and deadnix) and `alejandra` are on PATH in the devenv shell; start the
editor from it (or install them per user, as `homeModules.vscode`
does). Never set `diagnostic.suppress`: nixf findings fail
`checks.treefmt`.

## Org CI

Source of truth: external-systems/pkgs `documentation/docs/ci.md` and
`.github/workflows/org-ci.yml`. Read both before changing CI anywhere.

### The caller

`.github/workflows/ci.yml`, copied exactly from pkgs
`templates/default/.github/workflows/ci.yml`:

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:
  merge_group:
  workflow_dispatch:

permissions: {}

jobs:
  ci:
    uses: external-systems/pkgs/.github/workflows/org-ci.yml@main
    permissions:
      contents: write
      actions: write
      pages: write
      id-token: write
    with:
      major: 0
      minor: 0
    secrets: inherit
```

- The job id stays `ci`, so the required check is `ci / flake-check` in
  every repo and one ruleset fits all of them.
- `major` / `minor`: w and x in the `w.x.<commits>` release (semver).
  Bump `major` for a breaking release and reset `minor` to 0. Use 0/0
  for a new repo; a repo with existing tags continues its w.x (or starts the next
  one).
- `private-repos: secrets` (comma-separated, no owner) under `with:` for
  a repo whose flake reads private inputs. The GitHub App
  `external-systems-nix-ci` (installed on the private repos only) needs
  the org variable `NIX_APP_CLIENT_ID` (its Client ID, not sensitive)
  and the org secret `NIX_APP_PRIVATE_KEY`, both visible to that repo:
  org Settings → Secrets and variables → Actions (the secret →
  Selected repositories).
- Only those `with:` keys change per repo. Anything else (a new step, a
  build, a deploy target) is a PR to pkgs `org-ci.yml`, never logic in
  the caller or an extra workflow next to it.
- Triggers are `pull_request`, never `pull_request_target`: fork PRs get
  no secrets, and untrusted authors fail `flake-check` by design.

### What it runs

| Job | When | Does |
|---|---|---|
| `ci / flake-check` | PRs, merge queue, `main` | `nix flake check` with a warm store and eval cache; on `main` also builds `.#documentation` and uploads the Pages artifact |
| `ci / deploy` | `main`, after the check | deploys the artifact to GitHub Pages |
| `ci / release` | `main`, after the check | tags and releases `<major>.<minor>.<git rev-list --count HEAD>` |

So `nix flake check` must build the docs (`flakeModules.default` adds
`documentation`/`slides` as checks), and
`.#documentation` must exist: every repo has docs.

### Ruleset

`.github/rulesets/default.json`, copied from pkgs
`templates/default/.github/rulesets/default.json`: squash only, linear
history, signed commits, no force-push or deletion, PRs with 0 approvals,
`ci / flake-check` required with strict (up to date) branches,
OrganizationAdmin bypass (`pull_request`). GitHub does not read the
file; apply it once after the CI PR merges (the check must exist first):

```bash
# new ruleset
gh api -X POST repos/external-systems/<repo>/rulesets --input .github/rulesets/default.json
# replace an existing one: find its id, then PUT
gh api repos/external-systems/<repo>/rulesets --jq '.[] | [.id, .name] | @tsv'
gh api -X PUT repos/external-systems/<repo>/rulesets/<id> --input .github/rulesets/default.json
```

If an existing ruleset already requires a check the new CI no longer
reports (e.g. `flake-check` from an old `check.yml`), replace it
*before* merging the CI PR, or the PR cannot merge.

The org is on GitHub Free: no org-level rulesets, and no Pages or
rulesets on private repos.

### Pages

Once per repo: Settings → Pages → Build and deployment → Source:
**GitHub Actions**. Custom domain `<repo>.external.systems` (CNAME to
`external-systems.github.io`).

### Never

- Commit build output: `result`, `result-*`, `_site/`, `site/`,
  `documentation/site/` are gitignored; CI is the only publisher, no
  `gh-pages` branch.
- Use `pull_request_target`.
- Write per-repo CI logic.

## Two lockfiles, one nixpkgs

`flake.lock` and `devenv.lock` must resolve nixpkgs to the same rev (pkgs also checks its `dev/flake.lock`). `checks.lock-sync` fails when they drift and prints the
drifted locks. The fix is always `sync-locks` (devenv script, or
`nix run .#sync-locks`): it pins the pkgs rev in `devenv.yaml` and runs
`devenv update org-pkgs`.

Bump flow: `nix flake update org-pkgs`, then `sync-locks`, in one commit.
Never run a bare `devenv update` to move nixpkgs.

## Procedure: new repo

1. `nix flake init -t github:external-systems/pkgs` in an empty
   directory; replace every `CHANGE ME`.
2. `git init && git add -A` (Nix only sees tracked files).
3. `nix flake lock && devenv update`, then `nix run .#sync-locks`.
4. `devenv allow`, then `fmt`, `check`, `devenv test`, `docs-build`.
   Set `major` and `minor` in `.github/workflows/ci.yml`; after the first push,
   set Pages to GitHub Actions and apply the ruleset ([Org CI](#org-ci)).
5. Open the repo in VS Code from the shell and check that nixd hints
   (hover a flake-parts option) work.
6. Confirm the lock is lean: `jq '.nodes | keys' flake.lock` lists no
   devenv, mkdocs-flake or second nixpkgs (treefmt-nix and
   reveal-js appear once, under org-pkgs).

