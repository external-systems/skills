# external-systems skills

[![ci](https://img.shields.io/github/actions/workflow/status/external-systems/skills/ci.yml?branch=main&label=ci&logo=github)](https://github.com/external-systems/skills/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/external-systems/skills?label=release&color=d97757)](https://github.com/external-systems/skills/releases/latest)
[![docs](https://img.shields.io/website?url=https%3A%2F%2Fskills.external.systems%2F&label=docs&up_message=online&down_message=offline)](https://skills.external.systems/)
[![license](https://img.shields.io/github/license/external-systems/skills)](https://github.com/external-systems/skills/blob/main/LICENSE)
[![built with Nix](https://img.shields.io/badge/built_with-Nix-5277C3?logo=nixos&logoColor=white)](https://nixos.org)

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
