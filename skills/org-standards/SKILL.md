---
name: org-standards
description: "How every external-systems repo is structured and run: the one org-pkgs input and flakeModules.dev, no dev partition, the devenv shell, nixd settings, docs and a deck in every repo, lock sync, AGENTS.md, the org CI (ci.yml calling pkgs org-ci.yml, flake-check, Pages, releases), the default branch ruleset, and how branches, commits and pull requests work, including merge order across repos. Use when creating or converging a repo, touching flake.nix wiring, devenv.yaml, .vscode, CI, rulesets or Pages, or opening, describing or sequencing a PR in an org repo."
---

# org-standards — how an org repo is built and changed

Every repo in external-systems has the same shape, runs the same CI and
changes the same way. Two other skills cover the pieces this one points
to: `nix-style` (how Nix code is written) and `org-docs` (the docs site,
the deck and the org style). Which repo owns what is the `org-repos`
skill. Repo-specific facts live in each repo's `AGENTS.md`.

Templates for every file, the CI and ruleset details, and the new-repo
and converge procedures are in
[references/flake-standard.md](references/flake-standard.md). Load it
before creating a repo or changing a repo's wiring, `devenv.yaml`,
`.vscode/`, `documentation/` layout, CI, ruleset or Pages.

## Every repo

- **Is a flake with docs and a deck.** `nix build .#<attr>` is the build
  interface; `documentation/docs/*.md` is the site and
  `documentation/slides/slides.md` the deck (the `org-docs` skill).
- **Has one org input.** `org-pkgs.url = "github:external-systems/pkgs"`,
  with `nixpkgs`, `flake-parts` and `import-tree` following `org-pkgs/*`,
  and every other input following those where it can. The input is never
  named `pkgs`: that name is the nixpkgs package set.
- **Imports `inputs.org-pkgs.flakeModules.dev`** in `flake.nix`: treefmt
  (formatter, `checks.treefmt`), docs and slides (`flakeModules.docs`,
  built as checks), `checks.lock-sync` and `apps.sync-locks`. They are
  bound to pkgs' own inputs, so the repo declares none. Never copy the
  treefmt program list, the docs module or the org shell into a repo; a
  missing feature is a pkgs PR.
- **Has no dev partition** and no `dev/flake.nix` or `dev/flake.lock`:
  every dev tool comes from org-pkgs, which every repo already locks.
  Repo checks and maintainer apps are ordinary modules (`flake-parts/`,
  or `tests/flake-module.nix` with fixtures). Only pkgs keeps a partition
  (its code-agent image needs modules, which depends on pkgs). A repo
  that needs a heavy test-only input asks first.
- **Uses the devenv CLI shell.** `devenv.yaml` takes `org-pkgs`, follows
  `org-pkgs/nixpkgs` and imports `org-pkgs/devenv` (scripts `fmt`,
  `check`, `sync-locks`, `docs-build`, `docs`, `slides`; `devenv up`
  serves docs on :8981 and slides on :8982). `devenv.nix` adds the
  repo's languages, services and processes. No flake `devShells`.
- **Commits `.vscode/settings.json`** pointing nixd at the workspace
  flake (`builtins.getFlake (builtins.toString ./.)`) with `debug =
  true;` in `mkFlake`.
- **Keeps one nixpkgs across `flake.lock` and `devenv.lock`.** After
  `nix flake update org-pkgs`, run `sync-locks` in the same commit; never
  move nixpkgs with a bare `devenv update`.
- **Has `AGENTS.md`** (sections: what the repo is, Layout, Build and
  check or Tool loop, Rules) and a `CLAUDE.md` that is `@AGENTS.md`.
  Keep both in step with the code in the same PR.
- **Never commits build output**: `result*`, `_site/`, `site/`,
  `documentation/site/`, `.devenv*` are gitignored; CI is the only
  publisher; no `gh-pages` branch.
- **Is public unless it holds secrets.** No secret, IP address,
  account, subscription or tenant id in any file, commit or PR; those
  come from external-systems/secrets or not-secrets, or from the
  provisioning layer.

New repos start from `nix flake init -t github:external-systems/pkgs`.
A repo that does not match yet gets converged in its own PR (the
reference's converge procedure); offer it rather than doing it unasked.

## CI

One CI for every repo: pkgs `.github/workflows/org-ci.yml`, called from
`.github/workflows/ci.yml` copied exactly from the pkgs template.

- One job, id `ci`, so the required check is **`ci / flake-check`**
  everywhere. Per repo, only the `with:` keys change: `major`, `minor`,
  and `private-repos` for a repo that reads private inputs.
- `flake-check` runs `nix flake check` on PRs, the merge queue and
  `main`. On `main` it also builds `.#documentation`; `deploy` publishes
  it to GitHub Pages (`<repo>.external.systems`) and `release` tags
  `<major>.<minor>.<git rev-list --count HEAD>`.
- **Change CI only in pkgs**, as a PR to `org-ci.yml`. Never add steps,
  jobs or workflows in a repo, never use `pull_request_target`.
- Pages: once per repo, Settings → Pages → Source: GitHub Actions.

## Ruleset

`.github/rulesets/default.json`, copied from the pkgs template, guards
the default branch: PRs only (0 approvals), squash merges only, linear
history, signed commits, no force-push or deletion, and
`ci / flake-check` required on an up-to-date branch. Org admins can
bypass through a PR only. GitHub does not read the file; apply it with
`gh api` after the CI PR merges (the reference has the commands). The
org is on GitHub Free: no org-level rulesets, no rulesets or Pages on
private repos.

## Branches, commits and pull requests

- **Never push to `main`.** Every change is a branch and a PR; the
  ruleset enforces it.
- **One concern per PR, one PR per repo.** A change that spans repos is
  one PR in each, merged in dependency order (below).
- **Before pushing**: `git add -A`, `fmt`, `check` (or `nix fmt`,
  `nix flake check`), and build what you touched. Paste what you ran in
  the PR.
- **Commits**: imperative subject naming the change; the body says why.
  The PR is squash-merged, so its title becomes the one commit on
  `main`: make it a good one. GitHub signs that squash commit, which is
  what the ruleset's signed-commits rule checks on `main`.
- **PR description**: What (the change, file by file where it helps),
  Why, and Checks (commands run and their result; what could not run and
  why, so CI covers it). Add what the reviewer must know: behaviour or
  URL changes, lock-size changes when inputs move, merge order, the
  monthly cost change for infrastructure.
- **Merging** needs a green `ci / flake-check` on a branch up to date
  with `main`. Agents never merge, approve or bypass; the owner merges.
- **Infrastructure repos** (azure-infra) add their own gates: CI posts
  the plan, the owner sees it before any merge, applies run behind an
  environment approval. Read that repo's `AGENTS.md`.

### Merge order across repos

Inputs flow pkgs → skills → modules → secrets/not-secrets → home (and
clanServices, azure-infra). When a change spans them:

1. Merge the upstream PR first (usually pkgs).
2. In each consumer, `nix flake update <input>` (`org-pkgs` plus
   `sync-locks`), in that consumer's PR.
3. If a consumer PR must be tested before the upstream merges, lock the
   upstream PR's head commit
   (`nix flake lock --override-input org-pkgs github:external-systems/pkgs/<sha>`),
   say so in the PR, and re-lock to `main` after the upstream merges.

not-secrets merges before secrets; skills before modules; modules and
secrets before home.
