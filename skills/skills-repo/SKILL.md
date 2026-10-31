---
name: skills-repo
description: "How the owner's agent skills are built and shipped: the external-systems/skills flake (own skills, ownGroups, external sources, selections, presets, the skills runtime) and how external-systems/modules and external-systems/home install them per home-manager user. Load when asked to add, write, import, or enable a skill, to add skills from another GitHub repo, to give a user (netsa, matt, ...) more or fewer skills, or when an agent's skill is missing; then follow the procedure and open a PR."
---

# skills-repo

The owner keeps every agent skill in **external-systems/skills**. When
they ask for a new skill, whether you write it or it comes from someone
else's repo, the deliverable is a pull request there. A second PR in
external-systems/home is needed only when a specific user should get it.
Never edit `~/.agents/skills`, `~/.kimi-code/skills` or `~/.claude/skills`
by hand: they are read-only Nix store symlinks and get replaced on the
next deploy.

## How the pieces fit

```
external-systems/skills      skills/<name>/ + skills-* inputs
  ownGroups, selections      -> lists of {src; skillsDir; selectSkills}
  externalSkills presets     base (= core group), full, sandbox
  mkSkillsTree               preset ++ extraSources -> linkFarm dir
  mkSkillsRuntime            same args -> buildEnv of script deps
        |
external-systems/modules     homeModules.agents
  homeSpec.agents.skills.preset         default "base"
  homeSpec.agents.skills.extraSources   the user's picks
  homeSpec.agents.skills.runtime.{enable,office}
  -> links the tree into pi, kimi-code, claude-code, opencode
        |
external-systems/home        per-user profiles set preset/extraSources
```

- **Own skills** live in `skills/<name>/`. Each one belongs to exactly one
  `ownGroups` group in `flake-module.nix`: `core` (everyone), `fleet`,
  `kubernetes`, `networking`, `infra` or `sandbox`.
- **External skills** come from `skills-<name>` inputs (`flake = false`),
  exposed as `lib.sources.<name>` and as ready-made `lib.selections.<name>`
  lists.
- **Selections** are what users pick, for example
  `with inputs.skills.lib.selections; kubernetes ++ fluxcd`. Own groups go
  first so own skills win name collisions; among externals, earlier
  entries win.
- **Runtime**: `runtime/default.nix` (or `skills/<name>/runtime.nix`) lists
  what a skill's scripts call. The user's runtime is built from exactly the
  skills they get, so their tools follow their picks.

## Procedure A: write a new own skill

1. Clone external-systems/skills and create a branch.
2. Create `skills/<kebab-name>/SKILL.md`:

   ```markdown
   ---
   name: <kebab-name>
   description: "What it covers, then when to load it, naming the phrases the owner would say."
   ---

   # <kebab-name>
   ```

   - `name` must equal the directory name.
   - Always double-quote `description`. pi and kimi silently skip a skill
     with an unquoted `: ` in its description.
   - No angle-bracket markup in the name, the description or the H1.
     (The placeholders above are for this example only.)
   - The description is the only trigger. Keep the first paragraph sharp and
     move depth into `references/*.md`, which agents load on demand.
3. Add the name to one `ownGroups` group in `flake-module.nix`. Choose
   `core` only if every user should always have it.
4. If it ships scripts, add `skills/<name>/runtime.nix`:

   ```nix
   {pkgs}: {
     packages = [pkgs.jq];
     python = ps: [ps.requests];
     # node = true;    # nodejs, plus runtime/npm modules on NODE_PATH
     # office = true;  # LibreOffice
   }
   ```

   If it needs nothing beyond coreutils, the file is `{pkgs}: {}`. An npm
   module goes in `runtime/npm/package.json`; then run
   `npm install --package-lock-only` there.
5. Add it to the README's "Current skills" list.
6. Run the loop in "Verify", then commit and open the PR.

## Procedure B: add skills from an external repo

1. In `flake.nix`, add the input:

   ```nix
   skills-<name> = {
     url = "github:<owner>/<repo>";
     flake = false;
   };
   ```

2. In `flake-module.nix`, add `<name> = inputs.skills-<name>;` to
   `sources`. Then add a `selections.<name>` list:
   - Default: `[{src = sources.<name>;}]`, which reads `<repo>/skills/*`.
   - Use `skillsDir = "path/to/dir"` when the skills live elsewhere. One
     entry per category when they are nested as `skills/<category>/<skill>`.
   - Use `selectSkills = ["a" "b"]` to cherry-pick. Unknown names are
     dropped silently, so check the built tree.
3. Run `nix flake lock`, then
   `ls $(nix build --no-link --print-out-paths .#full)`, or build a test
   composition, to confirm which skill names land.
4. For every picked skill that ships scripts, read the scripts and add a
   `runtime/default.nix` entry (`packages`, `python`, `node`, `office`).
   `checks.skills-runtime-coverage` enforces this for skills in `full`.
5. Add the selection to a preset (`full` and/or `sandbox`) only if the owner
   asks for it fleet-wide. Otherwise it stays a per-user pick.
6. Verify, commit, and open the PR.

## Procedure C: give a home-manager user skills

Do this in external-systems/home, in the user's profile, after the skills
PR merges and the skills input is updated. The option names below follow
external-systems/modules' `homeModules.agents`, which was still being
split out when this skill was written. Check them against
`flake-parts/homeModules/agents.nix` in modules before you edit, and fix
this skill in the same PR if they changed.

```nix
homeSpec.agents.skills = {
  # preset = "full";  # default "base" = the core group
  extraSources = with inputs.skills.lib.selections;
    fleet ++ kubernetes ++ networking ++ cloudflare;
  # runtime.office = false;  # skips LibreOffice (about 2.5 GiB)
};
```

Each user lists their own picks, so netsa and matt can differ. Then run
`nix flake update skills` in modules and home, in the same PRs or as
follow-ups. Deployment is the owner's job: report the command
(`sudo nixos-rebuild switch --flake .#<host>` or `clan machines update`)
and never run it.

## Verify

```sh
git add -A                       # nix only sees tracked files
nix fmt                          # treefmt (inside devenv: fmt)
nix flake check                  # all gates
ls $(nix build --no-link --print-out-paths .#base)
```

Gates:
- `skill-frontmatter`: name, quoting and markup rules.
- `own-skills-grouped`: each own skill is in exactly one group.
- `skills-runtime-coverage`: skills with scripts have runtime entries.
- `treefmt`: alejandra, deadnix, statix, nixf-diagnose (every rule), shellcheck, sizelint.
- `lock-sync`: flake.lock, dev/flake.lock and devenv.lock pin one nixpkgs.
- The preset trees and `skills-runtime` build.
- `package-skills`: the claude.ai zips unpack to valid skills that
  `skills-drift` reads as in sync.

## claude.ai account skills

The repo is the source of truth; the account holds uploaded copies, and
nothing pushes them automatically. After a skill changes on `main`:

```sh
nix run .#skills-drift           # in a cloud session: missing/stale skills
nix run .#package-skills -- out  # out/<name>.zip + out/manifest.json
```

Upload the listed zips in claude.ai settings. Each packaged SKILL.md
carries `metadata.source-rev` and `metadata.content-hash` (the source tree
is never stamped), so `skills-drift` matches an upload to its repo state.
Skill files synced into a session are a read-only cache: editing them
changes nothing on the account.

## Open the PR

- Branch from `main` and open the PR against `main` in
  external-systems/skills.
- Title it "Add <name> skill" or "Add <source> skills".
- The body says what the skill is for, which group or selection it is in,
  any runtime entries, the `nix flake check` result, and which users need
  Procedure C.
- No secrets, tokens, IPs or hostnames in skills: the repo is public.
