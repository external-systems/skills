# Shipping skills

```
external-systems/skills      skills/<name>/ + skills-* inputs
  ownGroups, selections      -> lists of {src; skillsDir; selectSkills}
  externalSkills presets     base (= core group), full, sandbox
        |
external-systems/modules     homeModules.agents
  homeSpec.agents.skills.{preset, extraSources}
        |
external-systems/home        per-user profiles pick their skills
```

1. Write `skills/<name>/SKILL.md` (frontmatter `name` = directory name,
   double-quoted `description`).
2. Add the name to exactly one `ownGroups` group in `flake-module.nix`.
3. Scripts need a runtime entry (`runtime/default.nix` or
   `skills/<name>/runtime.nix`).
4. `check-skills`, `fmt`, `check`, then open a PR.

Changes reach machines after `nix flake update skills` in the consumer and
a human-run deploy. The `skills-repo` skill has the full procedure.

## claude.ai account skills

Uploaded account skills are copies of this repo. `nix run .#skills-drift`
(in a cloud session, which syncs the account's skills to
`~/.claude/skills/synced`) lists the repo skills that are missing or stale
there; `nix run .#package-skills -- out` builds the zips to upload, each
stamped with `metadata.source-rev` and `metadata.content-hash`, plus
`out/manifest.json`. Pass `--skip NAME` for skills kept off the account.
