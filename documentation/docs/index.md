# external-systems skills

Every AI agent skill for the external-systems fleet, as a flake: this
repo's own skills (`skills/<name>/SKILL.md`), every external skill source
pinned as a flake input, and the composed skills directory plus a runtime
of the tools the skills' scripts call.

| Output | What it is |
|---|---|
| `lib.mkSkillsTree` | compose a preset plus extra sources into one skills dir |
| `lib.mkSkillsRuntime` | the tools those skills' scripts need |
| `lib.selections.*` | ready-made source lists users pick from |
| `packages.base` / `full` / `sandbox` | the three presets, prebuilt |

The repository README lists every current skill.

<iframe src="slides/index.html" title="Slide deck"
  style="width: 100%; aspect-ratio: 16 / 9; border: 0;"
  allowfullscreen></iframe>
