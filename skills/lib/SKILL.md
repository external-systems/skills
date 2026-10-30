---
name: lib
description: "Custom libs: this repo's customLib (lib/default.nix — relativeToRoot, the mkLib root-binding factory, the four injection channels: perSystem _module.args, nixosModules _module.args, home-manager extraSpecialArgs, clan specialArgs — and the specialArgs-vs-_module.args circularity gotcha in nixosModules/networking.nix) and the AGENTS flake lib (inputs.agents.lib — mkSkills for composing/cherry-picking skill dirs into ~/.config/opencode/skills via selectSkills, loadAgents, agentsJson, skills-runtime package). Load when using customLib/relativeToRoot, wiring skills via inputs.agents.lib.mkSkills, editing lib/default.nix, or consuming inputs.home.lib from another flake."
---

# Custom Libs — home customLib + AGENTS lib

Two libs matter here:

1. **This repo's `customLib`** — nixpkgs `lib` extended with the repo's
   own helpers (`lib/default.nix`), injected into every module eval.
2. **The `agents` flake lib** (`inputs.agents.lib`, from
   `git+https://code.m3ta.dev/m3tam3re/AGENTS`) — skill composition
   (`mkSkills`) and agent-definition loading, used to build
   `~/.config/opencode/skills`.

Load when: using `customLib`/`relativeToRoot`, wiring skills via
`inputs.agents.lib.mkSkills`, editing `lib/default.nix`, or consuming
`inputs.home.lib` from another flake.

---

## Part 1 — this repo's customLib

### Definition

```nix
# flake-parts/default.nix
customLib = lib.extend (_self: _super: import ../lib {inherit lib;});
```

`lib.extend` returns a **superset of nixpkgs' lib** with the repo's
helpers merged in at the **top level** — so `customLib` is both nixpkgs
lib and the repo lib:

```nix
# lib/default.nix
{lib}: {
  # Pre-bound to THIS repo's root (../. relative to lib/):
  relativeToRoot = lib.path.append ../.;

  # Factory for other flakes: bind to any root.
  mkLib = root: {relativeToRoot = lib.path.append root;};
}
```

### Consumer idiom

```nix
{customLib, ...}: let
  inherit (customLib) relativeToRoot;   # flat — no `.custom` hop
in
  relativeToRoot "machines/${hostName}/facter.json"
```

`relativeToRoot "overlays"` yields a clean path value
(`/nix/store/…-source/overlays`), safe to interpolate or `import`. The
`../.` in `lib/default.nix` is relative to `lib/` itself, so the helper
works from any file in the tree.

### Injection channels (four separate evals)

| Channel | Wiring | Consumers |
|---|---|---|
| flake-parts modules | `perSystem._module.args` (`flake-parts/default.nix`) | module arg `customLib` |
| NixOS modules | `flake.nixosModules.default` → `_module.args` | module arg |
| Home-manager | `home-manager.extraSpecialArgs` (set once, centrally) | module arg — also reaches non-clan HM consumers (KubeVirt VMs, test VMs) |
| Clan | `clan.specialArgs` + explicit arg to `inventory.nix` | specialArg |

### Critical gotcha: `_module.args` vs `specialArgs`

Module args from `_module.args` are resolved lazily **through
`config`**, which is circular while config is still being evaluated.
Anything consumed during *import resolution* or early machine eval must
come via `specialArgs` (eager, available before config) instead.

Concrete failure (documented in `flake-parts/nixosModules/networking.nix`):
a NixOS module tried `customLib.relativeToRoot` for a file read at eval
time → clan machine evals died with `attribute 'customLib' missing`.
Fix there: read via a raw path literal (`./../../machines.json`), not
the lib helper. Home modules are unaffected — `extraSpecialArgs` is a
separate, eager channel.

Rule of thumb: **option values** may use `customLib` helpers; **imports
/ module-structure-level path reads in NixOS modules** may not (use a
relative path literal).

### Exportable lib (`flake.lib`)

Other flakes can consume this repo's lib without importing its modules:

```nix
# other flake's flake.nix:
inputs.home.url = "git+https://...";  # or github:andrewthomaslee/home
# usage:
(inputs.home.lib.mkLib ./.).relativeToRoot "src"   # bind to THEIR root
inputs.home.lib.relativeToRoot                      # bound to home's root (rarely useful externally)
```

Exported as `flake.lib = import ../lib {inherit lib;};` in
`flake-parts/default.nix`. System-independent — no `.${system}`, same
as `inputs.agents.lib`.

### Why not fold customLib into `lib` directly?

nixpkgs' module system explicitly forbids overriding the `lib` module
arg via `_module.args` (documented in `lib/modules.nix`). Shadowing it
via `specialArgs` works only on some channels (HM, clan) — flake-parts
`perSystem` cannot join, and top-level extensions risk silently
overriding future nixpkgs functions for third-party modules. Keep the
`customLib` name.

---

## Part 2 — the AGENTS flake lib

**Source:** `flake.nix` of `m3tam3re/AGENTS` (plain flake, no
flake-parts; lib exported system-less). Pinned in this repo's
`flake.lock` (branch `master`, `inputs.nixpkgs.follows =
"nixpkgs-unstable"` — no extra nixpkgs copy).

### `lib.mkSkills` — compose/cherry-pick skills

Builds `pkgs.linkFarm "opencode-skills"` — one symlink per skill dir —
from a custom skills dir plus external skill sources.

```nix
lib.mkSkills {
  pkgs,                    # required: nixpkgs package set
  customSkills ? null,     # path to a dir of skill subdirs (optional)
  externalSkills ? [],     # list of sources (optional, default [])
}
```

Each `externalSkills` entry:

| field | meaning | default |
|---|---|---|
| `src` | repo root (flake input or local path) | required |
| `skillsDir` | subdirectory containing skill dirs | `"skills"` |
| `selectSkills` | skill names to keep (cherry-pick) | all skills |

Mechanics:

1. `builtins.readDir "${src}/${skillsDir}"` → keep **directories only**
   (files like a root README are ignored; a skill = a directory).
2. `selectSkills` present → filter to those names. **Unknown names are
   silently dropped** — no error, so typos in select lists fail quiet.
3. Collisions: **custom skills always win**; among externals, **earlier
   list entries win** (later duplicates dropped).

### Worked example (this repo)

`flake-parts/homeModules/agents.nix` builds the tree once and symlinks
it into every enabled agent's skills dir:

```nix
# flake-parts/homeModules/agents.nix
skillsDir = inputs.agents.lib.mkSkills {
  inherit pkgs;
  customSkills = relativeToRoot "skills";
  externalSkills = [
    {src = inputs.skills-anthropic;}
    {src = inputs.skills-payloadcms;}
    # davidondrej/skills nests skills one level deeper
    # (skills/<category>/<name>) — one entry per category with a deeper
    # skillsDir; leaf names are unique across categories.
    {src = inputs.skills-davidondrej; skillsDir = "skills/agent-orchestration"; selectSkills = ["git-worktree" "goal-loop" "handoff" "herdr" "fable-review" "fable-safe-prompt" "gpt-review" "total-review"];}
    {src = inputs.skills-davidondrej; skillsDir = "skills/ops-and-setup"; selectSkills = ["create-readonly-db-role" "openrouter" "prompt-for-others" "risky-changes" "setup-help"];}
    {src = inputs.skills-davidondrej; skillsDir = "skills/research-and-web"; selectSkills = ["domain-checker" "who-is-this"];}
    {src = inputs.skills-davidondrej; skillsDir = "skills/skill-authoring"; selectSkills = ["effective-agent-skills"];}
    {src = inputs.skills-davidondrej; skillsDir = "skills/thinking-and-docs";} # whole category
  ];
};
# then per enabled agent (homeSpec.agents.<agent>.enabled):
xdg.configFile."opencode/skills".source = skillsDir;  # opencode
home.file.".agents/skills".source = skillsDir;        # pi
home.file.".kimi-code/skills".source = skillsDir;      # kimi-code
home.file.".claude/skills".source = skillsDir;         # claude-code
```

Cherry-pick patterns:

```nix
externalSkills = [
  # only two skills from a big repo
  {src = inputs.skills-anthropic; selectSkills = ["pdf" "xlsx"];}
  # non-standard repo layout
  {src = inputs.foo; skillsDir = "agent-skills";}
  # nested layout (category dirs): one entry per category, skillsDir
  # pointed at the category dir; omit selectSkills to take it all
  {src = inputs.skills-davidondrej; skillsDir = "skills/thinking-and-docs";}
  # local path instead of a flake input
  {src = ./some/skills; selectSkills = ["one"];}
  # the AGENTS repo's own skills (default layout)
  {src = inputs.agents; selectSkills = ["systematic-debugging"];}
];
```

Caveats:

- `builtins.readDir` runs at eval time — paths must exist in the git
  tree (git-add new skill dirs before `nix build`).
- No `SKILL.md` validation despite the upstream comment — any directory
  counts.
- The result is a linkFarm of **symlinks**; expand if real dirs are
  needed.
- `customSkills` is all-or-nothing (no per-skill selection) — put
  selective customs in a subdirectory and pass it as an external entry
  instead.

### Other lib members (all system-less)

- **`lib.loadAgents`** — attrset keyed by agent slug, read from the
  AGENTS repo's own `agents/` dir: `agent.toml` fields + `systemPrompt`
  (contents of `system-prompt.md`). Access:
  `inputs.agents.lib.loadAgents.<slug>.description`.
- **`lib.agentsJson`** — same agents rendered into opencode
  `settings.agent` shape (display-name keys, `model` hardcoded to
  `zai-coding-plan/glm-5`, `prompt = "{file:./prompts/<slug>.txt}"`,
  permission rules parsed from `"pattern:action"` strings). Usage:
  `programs.opencode.settings.agent = inputs.agents.lib.agentsJson;`
  The `{file:...}` prompt refs assume AGENTS' `prompts/` is shipped
  into the opencode config dir alongside.
- **`packages.<system>.skills-runtime`** — buildEnv with the Python env
  (pyyaml, openpyxl, numpy, pypdf, pillow, pdf2image, playwright),
  poppler-utils, jq, playwright browsers. Runtime deps for scripted
  skills (pdf, xlsx, excalidraw, skill-creator). Add via
  `home.packages` or a devShell.

### Gotchas

- The flake input URL has no `?ref=` — tracks AGENTS' default branch;
  updates come via `nix flake lock --update-input agents` (content
  immutable per locked rev).
- Access is `inputs.agents.lib.<fn>` — **no** `.${system}`
  (unlike `packages.skills-runtime`, which needs it).
