# AGENTS.md

external-systems/skills: every AI agent skill for the owner's fleet, as a
flake. It holds this repo's own skills (`skills/`), pins every external
skill source as a flake input, and exports the composed skills dir plus a
runtime of the tools the skills' scripts call. Public repo: no secrets, IP
literals or tokens in any file. To add or wire a skill, load the
`skills-repo` skill first; it has the full procedure.

## Layout
- `flake.nix`: inputs (`nixpkgs`/`flake-parts` follow `external-systems/pkgs`; `skills-*` sources are `flake = false`) and the partition setup.
- `flake-module.nix`: everything consumers evaluate. `sources` (raw inputs), `ownGroups` (this repo's skills by group), `selections` (ready-made source lists), `externalSkills` presets (`base` = the `core` group and the default, `full`, `sandbox`), `mkSkillsTree`, `mkSkillsRuntime`, `packages.*`.
- `lib/mk-skills.nix`: `mkSkills`/`skillSet`, a drop-in for the AGENTS flake's `mkSkills`. `lib/mk-skills-runtime.nix`: the runtime buildEnv. `lib/check-skill-metadata.py`: frontmatter validator.
- `runtime/default.nix`: per-skill runtime needs (`packages`, `python`, `node`, `office`). `runtime/npm/`: npm modules on `NODE_PATH`.
- `dev/flake.nix` + `dev/flake.lock`: dev-only inputs (treefmt-nix, presenting). `dev/flake-module.nix`: the `dev` flake-parts partition (pkgs `flakeModules.dev`, docs, skill gates, apps). Consumers never evaluate it.
- `devenv.yaml` + `devenv.lock` + `devenv.nix`: the dev shell (devenv CLI; the org shell comes from `pkgs/devenv`). There is no flake devShell.
- `documentation/`: the docs site (`docs/`) and slide deck (`slides/`).
- `skills/<name>/SKILL.md`: this repo's skills, with optional `references/` and `runtime.nix`.

## Consumers
- external-systems/modules (interface still settling; check its `flake-parts/homeModules/agents.nix`): `homeModules.agents` calls `mkSkillsTree` and `mkSkillsRuntime` with `homeSpec.agents.skills.{preset,extraSources}` and links the tree into pi (`~/.agents/skills`), kimi-code (`~/.kimi-code/skills`), claude-code (`~/.claude/skills`) and opencode.
- external-systems/home: per-user profiles set `preset` and `extraSources`. The code-agent image uses `preset = "sandbox"`.
- Changes reach machines only after `nix flake update skills` in the consumer and a human-run deploy.

## Tool loop
- `git add` new files before any `nix` command. Nix evaluates the git tree, so untracked files do not exist for it.
- The shell is devenv. If `DEVENV_ROOT` is unset, run commands with `devenv shell -- <cmd>`.
- For any change, run `fmt` (treefmt: alejandra, deadnix, statix, nixf-diagnose, shellcheck, sizelint). `check-skills` validates frontmatter without Nix.
- Gate: `check` (`nix flake check`). It runs `treefmt`, `lock-sync`, `documentation`, `slides`, `skill-frontmatter`, `own-skills-grouped`, `skills-runtime-coverage`, the `base`/`full`/`sandbox` trees, `skills-runtime` and `package-skills`. Markdown-only skill edits still need `skill-frontmatter` and `own-skills-grouped`, so run the full check anyway: it is cheap apart from the first `skills-runtime` build.
- Inspect a tree: `ls $(nix build --no-link --print-out-paths .#base)`.
- Add a source: add the input, then `nix flake lock`. Bump one source with `nix flake update skills-<name>`. Never bump `pkgs` casually, because it moves nixpkgs for the whole org; when you do, run `sync-locks` in the same commit.
- Docs: `nix build .#documentation`, then open `result/index.html` from disk; `devenv up` for live preview on :8981.

## Rules
- Every own skill sits in exactly one `ownGroups` group. Add `core` only when every user should have the skill.
- `SKILL.md` frontmatter: `name` equals the directory name, `description` is always double-quoted, and name, description and H1 contain no angle-bracket markup.
- A skill that ships scripts (`.py .sh .js .mjs .ts`) needs a runtime entry. Use `{}` when it needs nothing beyond coreutils.
- Keep the README's "Current skills" list and group tables in step with `flake-module.nix`.
- Work on a branch and open a PR. Never push to `main`. Agents never deploy machines (`nixos-rebuild`, `clan machines update`); report the command for the human instead.
