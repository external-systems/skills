---
name: org-repos
description: "Map of the owner's external-systems GitHub org: which repo owns what (home, pkgs, modules, skills, secrets, not-secrets, clanServices, presenting), which flake consumes which, where clones live on disk (~/external-systems/REPO), and which repo a change belongs in. Load when asked how the repos fit together, where a package, module, skill, IP address or clan service should go, which repo to edit or open a PR in, how to test a change across repos, or in what order to bump flake inputs after a change."
---

# org-repos

The owner's Nix setup is split across several flakes in the
**external-systems** GitHub org. Each repo has one job, and
**external-systems/home** sits at the bottom of the chain: it deploys the
clan machines and consumes everything else. Use this map to put a change
in the right repo and to bump inputs in the right order.

## Where the clones are

Every org repo is cloned into the user's home directory under
`~/external-systems/`, named exactly like the GitHub repo:

```
~/external-systems/home          ~/external-systems/modules
~/external-systems/pkgs          ~/external-systems/skills
~/external-systems/secrets       ~/external-systems/not-secrets
~/external-systems/clanServices  ~/external-systems/presenting
```

Note the capital S in `clanServices`. Look there before cloning anything.
If a repo is missing, clone it to the same place:
`git clone https://github.com/external-systems/<repo> ~/external-systems/<repo>`
(`<repo>` here is a placeholder). In a cloud session the clones may sit
somewhere else, so check the working directory first.

## Who consumes whom

```
                     external-systems/pkgs  (input name: org-pkgs)
          nixpkgs + flake-parts + import-tree, overlays, packages,
          flakeModules.dev, the devenv shell, the repo template
      _________________________|______________________________
     |            |               |              |            |
 presenting    skills        not-secrets    clanServices   (every repo's
 docs+slides   agent skills  schema +       clan services   dev partition
     |            |          placeholders   (input: pkgs)   and devenv)
     |            v               |              :
     |         modules            v              :
     |         NixOS + hm      secrets           :  planned
     |         modules         real values       :
     |            |               |              :
     |            v               v              v
     |         ===========  external-systems/home  ===========
     |              clan machines, inventory, users, deploys
     |
     +--> every repo's dev partition (packages.documentation, slides)
```

Solid lines are flake inputs. A repo never imports something below it in
the chain: pkgs knows nothing about machines, modules knows nothing about
users or IPs, and only home names machines.

## What each repo owns

| Repo | Owns | Never holds |
|---|---|---|
| **home** | The clan: `inventory.nix`, `machines/<name>/`, users and their home-manager profiles, home-only clan services (`clanServices/` dir: machine-type, tags, remote-builder), `sops/` and `vars/`. Deploys run from here. Public. | Packages, overlays, reusable modules, skills, IP literals |
| **pkgs** | The shared-input authority: the single nixpkgs, flake-parts and import-tree every repo follows. Packages and `overlays.{default,kubernetes,ifstate,tools}` (Kubernetes distros, IfState, Cilium manifests and airgap images, workstation and agent tools), the code-agent sandbox image, `flakeModules.dev` (treefmt, `lock-sync`, docs as checks), the org devenv shell (`org-pkgs/devenv`) and `nix flake init -t github:external-systems/pkgs`. | Inventory, clan vars, fleet policy |
| **modules** | Reusable NixOS (`nixosModules.*`, options under `hostSpec.*`) and home-manager (`homeModules.*`, options under `homeSpec.*`) modules. Every module is off until enabled. `homeModules.agents` installs the skills tree. | Machines, users, packages, IPs or account ids |
| **skills** | Every agent skill: own skills in `skills/`, external sources as `skills-*` inputs, presets, `mkSkillsTree`, `mkSkillsRuntime`, and the skill checks and apps (`package-skills`, `skills-drift`). Public. | Secrets, IPs, hostnames |
| **not-secrets** | The values schema, `lib`, `flakeModules.{values,checks}` and public placeholder values (RFC 5737/3849/7042/2606 ranges only), so `nix flake show` and public evaluation always work. | Any real value (`checks.placeholders-only`) |
| **secrets** | Private. Only `values/`: the real addresses, interfaces, MACs, deploy targets, storage box ids. Imports not-secrets for the schema and guards. | Credentials (keys, tokens, passwords go in clan vars) |
| **clanServices** | Standalone custom clan services: `k3s`, `rke2`, `netif` (IfState host links), `routed-fabric`, `wireguard-mesh`. `SPEC.md` is its contract. Uses pkgs for runtimes and airgap artifacts, and re-exports its overlays. | Machines, real values |
| **presenting** | The MkDocs + reveal.js builder: `flakeModules.default`/`.slides`, `lib.mkSlides`, and a repo template. Its own site is published to GitHub Pages by CI. | Build output in git |

## How the links work

- **pkgs is `org-pkgs`.** Every repo declares
  `org-pkgs.url = "github:external-systems/pkgs"` and follows its
  `nixpkgs`, `flake-parts` and `import-tree`. Never name the input `pkgs`
  (that is the nixpkgs package set); clanServices is the one legacy
  exception and calls it `pkgs`. One nixpkgs for the whole org: never add a
  second nixpkgs input or `pkgs.unstable`.
- **Every repo has a `flake.nix` and a `flake.lock`**, plus a `dev`
  flake-parts partition (`dev/flake.nix` with its own `dev/flake.lock`)
  that holds checks, formatter and docs. Consumers never evaluate or lock
  dev inputs. The shell is the devenv CLI importing `org-pkgs/devenv`
  (`fmt`, `check`, `sync-locks`, `docs-build`). See the `nix-style` skill
  for the standard.
- **presenting** is consumed in each repo's `dev/flake.nix` (input
  `presenting`) to build `documentation/` into `packages.documentation`
  with the deck at `/slides/`. It is a dev input, never a runtime one. See
  the `mkdocs-reveal` skill.
- **skills reaches machines through modules.** modules has a `skills`
  input; `homeModules.agents` calls `inputs.skills.lib.mkSkillsTree` with
  each user's `homeSpec.agents.skills.{preset,extraSources}`. pkgs' dev
  partition also pulls modules (and so skills) to build the code-agent
  image. See the `skills-repo` skill.
- **secrets and not-secrets expose the same outputs** (`values`, `lib`,
  `schemaVersion`). not-secrets owns the schema; secrets only fills it, and
  `checks.shape-parity` in secrets fails when the two shapes differ. A
  consumer reads `inputs.secrets.values.hosts.<machine>...` and never
  writes an address, interface or deploy target as a literal. home pins
  the private repo directly as its `secrets` input (clan can't pass
  `--override-input`), so evaluating home's machines needs a GitHub token
  that can read external-systems/secrets; the devenv shell sets it from
  `.env`. Public consumers pin not-secrets under the same input name.
- **clanServices** is a standalone flake that consumers add with
  `clanServices.inputs.clan-core.follows = "clan-core"` and reference from
  the inventory with `module.input = "clanServices"`. home does not consume
  it yet: home machines use a temporary `hostSpec.networking.shim` until
  `netif` takes over, and the Kubernetes machines that will use `k3s`/`rke2`
  still live in andrewthomaslee/borg, a personal repo that predates the
  split and will move into home.

## Migration state

The split was in flight when this skill was written. home's `main` may
still be the old monolith (its own skills, overlays, packages and
`agents` input); the target layout above is home PR #2 ("Migrate home
onto the org flakes"). Check home's `flake.nix` before relying on either
shape, and fix this skill in the same PR if the map has moved.

## Where a change goes

| The change | Repo |
|---|---|
| A new package, overlay, container image, pinned binary or chart | pkgs |
| A NixOS or home-manager module, or a new `hostSpec`/`homeSpec` option | modules |
| A skill, a skill source, a preset or a skill check | skills |
| A new value field or section (schema) | not-secrets first, then secrets |
| A real IP, MAC, interface name, domain or storage box id | secrets (plus a matching placeholder in not-secrets) |
| A clan service for more than one fleet (Kubernetes, networking) | clanServices |
| A machine, a user profile, an inventory instance, which skills a user gets | home |
| The docs/slides builder itself | presenting |

## Changing several repos

Work from the top of the chain down, one PR per repo, and bump each
consumer after its dependency merges:

1. pkgs (if touched). Bumping `org-pkgs` anywhere moves nixpkgs, so run
   `sync-locks` in the same commit to keep `flake.lock`, `dev/flake.lock`
   and `devenv.lock` on one nixpkgs (`checks.lock-sync`).
2. not-secrets, then secrets (`nix flake update not-secrets` there).
3. skills, then modules (`nix flake update skills`).
4. home: `nix flake update modules secrets` (and `org-pkgs` if it moved).

To try an unmerged change before its PR lands, point the consumer at the
local clone for one command only:

```sh
cd ~/external-systems/home
nix flake check --override-input modules path:$HOME/external-systems/modules
```

Never commit an override (`nix flake lock --override-input`): it records a
local path, or the private secrets revision, in a public `flake.lock`.

## Rules

- Each repo has its own `AGENTS.md`; read it before editing there.
- `git add` new files before any `nix` command in any repo.
- Work on a branch and open a PR in the repo that owns the change. Never
  push to `main`.
- Agents never deploy (`clan machines update`, `nixos-rebuild`); report the
  command for the owner to run from `~/external-systems/home`.
- Public repos (all but secrets) carry no IP literals, credentials or
  account ids.
