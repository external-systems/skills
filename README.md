# skills

Agent skills for the external-systems fleet: the `SKILL.md` tree, the
external skill sources, and the composed skills dir every AI coding agent
symlinks (opencode `~/.config/opencode/skills`, pi `~/.agents/skills`,
kimi-code `~/.kimi-code/skills`, claude-code `~/.claude/skills`, and
`/opt/skills` in the code-agent sandbox image).

## Layout

```
flake.nix               # inputs (nixpkgs + flake-parts follow external-systems/pkgs), partitions
flake-module.nix        # lib.* and packages.* (what consumers evaluate)
lib/mk-skills.nix       # mkSkills: compose skill dirs into one linkFarm
lib/check-skill-metadata.py  # SKILL.md frontmatter validator
dev/flake.nix           # dev-only inputs, locked in dev/flake.lock
dev/flake-module.nix    # dev partition: pkgs flakeModules.dev, docs, gates, apps
devenv.yaml devenv.nix  # the dev shell (devenv CLI, org shell from pkgs)
documentation/          # docs site and slide deck
skills/<name>/SKILL.md  # this repo's skills
```

Checks, apps, the formatter and docs live in the `dev` flake-parts
partition, so a consumer reading `lib` or `packages` never evaluates them
or fetches their inputs. The repo follows the org flake standard (the
`nix-style` skill).

## Develop

Needs Nix and devenv.

```sh
devenv allow     # auto-activation (after `devenv hook`)
fmt              # treefmt: org formatters and linters
check-skills     # frontmatter validator, no nix
check            # nix flake check: every gate
docs-build       # static docs to ./result-docs; open index.html from disk
devenv up        # live docs :8981 and slides :8982
```

## Outputs

| Output | What it is |
|---|---|
| `packages.<system>.base` (`default`) | The `core` group: the small shared base every user gets |
| `packages.<system>.full` | All of `skills/` + the former fleet-wide host set |
| `packages.<system>.sandbox` | All of `skills/` + the set baked at `/opt/skills` in the code-agent image |
| `packages.<system>.skills-runtime` | Tools and modules the `full` set's scripts call |
| `lib.customSkills` | Path to this repo's `skills/` |
| `lib.sources.<name>` | Raw external skill sources (`anthropic`, `cloudflare`, `payloadcms`, `supabase`, `fluxcd`, `terraform`, `google`, `mattpocock`, `openshell`) |
| `lib.ownGroups` | This repo's skills by group: `core`, `fleet`, `kubernetes`, `networking`, `infra`, `sandbox` |
| `lib.selections.<name>` | Ready-made `externalSkills` lists: one per own group, `own-all`, and one per source (`anthropic`, `anthropic-all`, `cloudflare`, `payloadcms`, `supabase`, `fluxcd`, `terraform`, `google`, `mattpocock`, `openshell`) |
| `lib.externalSkills.{base,full,sandbox}` | Presets built from the selections |
| `lib.mkSkills` | `{pkgs, customSkills ? null, externalSkills ? []}` → linkFarm; drop-in for the AGENTS flake's `lib.mkSkills` |
| `lib.mkSkillsTree` | `{pkgs, preset ? "base", extraSources ? []}` → preset + extra sources |
| `lib.mkSkillsRuntime` | Same arguments plus `office ? true` → buildEnv of what that composition's scripts call; `passthru.env.NODE_PATH` |
| `apps.<system>.package-skills` | `nix run .#package-skills -- OUT_DIR`: one ZIP per skill (validates first) |
| `checks.<system>.*` | `treefmt`, `lock-sync`, `documentation`, `slides`, `skill-frontmatter`, `own-skills-grouped`, `skills-runtime-coverage`, the preset trees, `skills-runtime`, `package-skills` |

Collision rules: custom skills (`skills/`) always win; among externals,
earlier entries win. `selectSkills` drops unknown names silently, so
verify the installed set after changing a selection.

## Picking skills per user

Every source lives here as an input; consumers never add `skills-*`
inputs of their own. Each home-manager user gets the `base` preset (the
`core` group: baton-pass, clan-core, devenv, flakeparts, import-tree,
mkdocs-reveal, nix-style, skills-repo) and picks extras in their profile (the agents
module lives in external-systems/modules). List own groups before
external sources so own skills keep winning name collisions:

```nix
# netsa's profile
homeSpec.agents.skills.extraSources = with inputs.skills.lib.selections;
  fleet ++ kubernetes ++ networking ++ infra ++ anthropic ++ fluxcd;
```

The agents module builds both the tree and the runtime from the same
composition, so each user's tools follow their skills:

```nix
skillsDir = inputs.skills.lib.mkSkillsTree {inherit pkgs; inherit (cfg.skills) preset extraSources;};
runtime = inputs.skills.lib.mkSkillsRuntime {inherit pkgs; inherit (cfg.skills) preset extraSources;};
home.packages = [runtime];
home.sessionVariables = runtime.env;
```

## Skill runtime

`runtime/default.nix` maps each script-shipping skill to what its scripts
call (`packages`, `python`, `node`, `office`); custom skills can ship
`skills/<name>/runtime.nix` instead. `mkSkillsRuntime` merges the entries
of the skills actually composed into one low-priority buildEnv (python3
env, nodejs with the `runtime/npm` modules on `NODE_PATH`, LibreOffice
unless `office = false`, which saves roughly 2.5 GiB).
`checks.skills-runtime-coverage` fails when a skill in the `full` tree
ships scripts with no entry (`{}` marks one that needs nothing).

## Skill convention

One directory per skill, each containing a `SKILL.md` with YAML
frontmatter:

```
skills/
  my-skill/
    SKILL.md        # required: name + description frontmatter
    references/     # optional: details loaded on demand (progressive
    ...             #   disclosure keeps always-on context small)
```

```markdown
---
name: my-skill
description: "When this skill should be used (drives agent triggering)."
---
```

**Always double-quote the `description`** (escaping any embedded `\` and `"`).
pi and kimi-code parse the frontmatter with JS YAML libraries that reject a
`: ` (colon+space) inside an unquoted scalar — `description: foo: bar` fails
with "nested mappings are not allowed in compact mappings" (pi) /
"bad indentation of a mapping entry" (kimi) and the skill is **silently
skipped** (kimi logs `Skipping invalid skill`; pi reports a skill conflict).
`checks.skill-frontmatter` (`dev/flake-module.nix`) fails `nix flake check`
on unparseable frontmatter, so CI catches it before hosts or the sandbox
image pick the skill up. Names, descriptions, and titles must also avoid
XML-like angle-bracket markup; the shared validator rejects it, and the
`package-skills` app refuses to package invalid skills.

The `description` is the only trigger mechanism — write it as a
when-to-use sentence naming the phrases a user would say. Deep
"how things work" material lives in the skill body (loaded on demand
via the skill mechanism itself); keep `SKILL.md` structured with a
clear first paragraph and skim-friendly sections.

## Adding a skill — no Nix changes

1. Create `skills/<kebab-case-name>/SKILL.md` with frontmatter
   (`name`, `description`).
2. Optional: supporting files (or a `references/` subdir) inside the
   skill dir for progressive disclosure.
3. Add its name to one `ownGroups` entry in `flake-module.nix`
   (`checks.own-skills-grouped` fails otherwise), then `git add` it.
   If the skill ships scripts,
   add a `runtime.nix` (or a `runtime/default.nix` entry). Consumers pick it up on their
   next `nix flake update skills` and deploy.

## Adding skills from an external source

1. Add the source repo as a flake input in `flake.nix` (usually
   `flake = false`, named `skills-<name>`) and expose it in
   `lib.sources` (`flake-module.nix`).
2. Add a `selections.<name>` list. Each entry is `{src = ...;}` with
   optional `skillsDir` (default `"skills"`) and `selectSkills`
   (cherry-pick by name). Use it in a preset if it should be shared.
3. Add `runtime/default.nix` entries for any of its skills that ship
   scripts.

## House rules

- Update this README: the Current skills list below is the human-facing
  index of this tree.
- `git add` every new file before any `nix build` / `nix flake check` —
  Nix evaluates the flake from the git tree; untracked files do not exist.
- Run `fmt`, then `check` (`nix flake check`).
- Public repo: no secrets in any file (skills, README included).

## Current skills

Workflow / behavior skills:

- `baton-pass` — session handoff: saves the full state of an in-progress
  task to `.baton-pass/` (timestamped markdown file + `LATEST.md`
  pointer, auto-gitignored) so a different agent or model can resume
  where the session stopped, or resume from an existing handoff.
  Language- and repo-agnostic.

- `skills-repo` — how this repo, external-systems/modules and
  external-systems/home ship skills: writing an own skill, importing an
  external source, per-user picks, runtime entries, and the PR flow.

Repo knowledge skills (deep "how things work" docs, loaded on demand by
their description):

- `nix-style` — Nix code style, the treefmt tool loop and the org flake
  standard (pkgs flake modules, dev partition, devenv CLI shell, docs and
  slides) (user preferences).
- `flakeparts` — flake-parts module system mechanics, inputs, the
  lint gate, integrations.
- `import-tree` — flake-parts auto-import via import-tree: mechanics,
  tree layout, agent rules.
- `determinate` — Determinate Systems + FlakeHub: docs map, publishing,
  cache/private flakes, semver, `fh` CLI + `fh apply`.
- `home-manager` — home-manager with flakes + flake-parts, the
  homeSpec.* namespace, worked profile example.
- `clan-core` — fleet management: inventory, clanServices, vars
  generators, clan CLI, machine update flows, clanService VM tests.
- `clanservices` — authoring clan.service modules in the official
  clan-core style.
- `declarative-runtime` — NixOS service runtime state through paired
  OpenTofu providers: using and authoring pairings, readiness, secret files,
  clan vars integration, debugging, and scenario design.
- `terranix` — Terraform JSON generation from Nix modules: flakes and
  flake-parts, OpenTofu, external HCL modules, cloud providers, path-style S3
  backends, lifecycle maintenance, and debugging.
- `devenv` — devenv 2.x dev environments: CLI reference, borg hybrid
  pattern, devcontainer, containers/OCI/K8s.
- `vm-tests` — hermetic NixOS VM tests: structure, sm/md/lg tiers,
  running, agent loop.
- `lib` — this repo's customLib + the AGENTS flake lib (`mkSkills`
  skill composition).
- `disko` — declarative disk partitioning: devices tree, LUKS + clan
  vars keys, redundancy recipes.
- `cilium` — Cilium 1.20.x: BGP control plane CRDs, LB IPAM, network
  policy, troubleshooting playbook.
- `frr` — FRRouting (FRR) BGP on NixOS: `services.frr` module
  mechanics, BGP config (unnumbered/RFC 8950, route-maps, ECMP, BFD,
  graceful restart), EVPN-VXLAN overlays (L2 stretch, L3 EVPN/IRB,
  anycast gateways, VTEPs on Linux hosts), run/debug playbook
  (`show bgp summary`, `debug bgp`, frr-reload), resilience design
  (BFD C-bit/GR interplay, timer coherence, ECMP incl. over WireGuard,
  WireGuard transport pitfalls), and Cilium BGP control plane integration patterns
  (node-local FRR fronting, direct TOR peering, BGP auto-discovery,
  WireGuard site meshes).
- `ifstate` — IfState 2.5.1 on NixOS: declarative netlink configuration,
  package pinning, live updates without reboot, physical/virtual links,
  netns/WireGuard/VRF/VXLAN, FRR/Cilium/EVPN integration, clan-managed
  fleet patterns, and operational debugging.
- `envoy-gateway` — Envoy Gateway v1.9.x: install/upgrade, Gateway API
  v1.6 routing, gateway.envoyproxy.io CRDs and policy model, security,
  observability/egctl debugging, and running on Cilium (KPR, nftables,
  BGP v2 + LB IPAM).
- `rancher-kubernetes` — k3s/RKE2 operations: bootstrap, security,
  datastores, air gap, Cilium/Multus, NixOS/VM tests, k3d labs, and k3k.
- `openebs` — OpenEBS 4.6.x Kubernetes CSI storage: engines, per-node
  prerequisites, StorageClasses, upgrades, troubleshooting.
- `mkdocs-reveal` — add a MkDocs docs site + reveal.js slide deck to any
  flake repo as build artifacts by consuming the
  `external-systems/presenting` flake (flakeModules + lib.mkSlides, zero
  boilerplate), or scaffold greenfield from its template.
- `kubenix` — render Kubernetes manifests with the Nix module system
  (hall/kubenix): typed resources, helm chart inflation, Nix-built OCI
  images + skopeo push, CRDs/typed custom resources, secrets via
  vals/sops/clan vars, GitOps (FluxCD) handoff, air-gapped and k3s/RKE2
  deployment.
