---
name: baton-pass
description: Hand off in-progress work to another AI agent or model. Use when the user says "baton pass", asks to stop and save session progress, hand the task to a different agent/LLM, or asks to resume work recorded in a .baton-pass/ handoff. Language- and repo-agnostic — works in any project and with any receiving agent.
---

# Baton Pass

The Pokémon move Baton Pass switches the active Pokémon out mid-battle and
passes every stat change to whatever comes in. This skill does the same for
agent sessions: save the full state of the current task to disk so a
different agent — a fresh model with zero conversation context — can pick
the task up and continue from exactly where it stopped.

Two modes. **Save & stop** when the user wants to end the current session
or switch agents/models. **Resume** when starting work in a repo that has a
`.baton-pass/` handoff. The handoff format is plain markdown so any agent
can read it; never assume the receiving agent shares your tooling, memory,
or conversation history.

## Mode A — Save & stop

The moment the user asks for a baton pass, the session's job changes from
"do the work" to "record the work". Follow these steps in order:

1. **Stop doing task work immediately.** Finish only the atomic edit in
   flight (never leave a file half-edited or a command half-run), then
   stop. Do not start any new task step, do not refactor, do not commit.
2. **Find the repo root** (git root if the repo uses git, else the working
   directory) and create `.baton-pass/` there if it does not exist.
3. **Write the handoff file**
   `.baton-pass/YYYYMMDD-HHMMSS-<task-slug>.md` — timestamp at write time
   plus a short kebab-case task slug (for example
   `20260921-1430-fix-flake-lint-gate.md`). Use the compact template below;
   the full annotated template with per-section guidance and a worked
   example is in [template.md](references/template.md).
4. **Repoint `.baton-pass/LATEST.md`** — overwrite it with a single line
   pointing at the file just written:
   `→ 20260921-1430-fix-flake-lint-gate.md`. The receiving agent reads
   `LATEST.md` first and must never have to guess which handoff is current.
5. **Gitignore the folder** if the repo uses git: append `.baton-pass/` to
   `.gitignore` if it is not already there. Handoffs are ephemeral session
   state, not repo content.
6. **Report and stop.** Tell the user the handoff path and a one-line
   status summary, then stop all further work and tool calls.

## Mode B — Resume

When a repo has `.baton-pass/` and the user asks to continue (or you are a
fresh agent told work was handed off):

1. Read `.baton-pass/LATEST.md` and open the handoff file it points to,
   in full, before doing anything else.
2. Restate the objective and current state in one or two sentences so the
   user can correct any misunderstanding before you act.
3. Sanity-check the claims before trusting them: do the listed files exist
   in the stated state, does the recorded verification command still pass?
   A handoff describes a past moment; the tree may have moved since.
4. Continue the task from **Next steps** without redoing completed steps.
5. If you are later asked to baton pass again, write a fresh timestamped
   handoff (Mode A) carrying forward the previous file's context — chain,
   do not truncate history.

## Handoff file rules

- **Self-contained.** The reader has zero context: no conversation
  history, no memory, possibly a different toolset. Everything it needs
  must be in the file or reachable from paths written in the file.
- **Plain markdown.** No tool-specific formats, no agent-specific jargon.
- **No secrets.** Never copy token values, keys, or `.env` contents into a
  handoff. Reference them by name: "GITHUB_TOKEN is already exported in
  the devShell".
- **Verification over assertion.** Record which commands were run, their
  results, and how the receiver verifies the current state. "It should
  work" is not a handoff.
- **Decisions and gotchas included.** The most expensive thing to lose
  mid-handoff is *why* a choice was made — record constraints, rejected
  approaches, and user preferences learned this session.
- **Stable shape.** If a section has nothing to say, write `none` — do not
  delete the section. Receivers rely on finding the same sections in every
  handoff.

## Compact template

```markdown
# Baton Pass — <task title>

> Receiving agent: read this file fully, then continue the task. Do not
> redo completed steps. Verify before trusting.

- Recorded: <ISO-8601 date-time>
- By: <agent/model name if known, else "unknown">
- Repo: <root path> · branch `<branch>` · HEAD <sha or "no git">
- Working tree: <clean | N uncommitted files — see Files touched>

## Objective
<what the user asked for, as close to their words as possible>

## Status snapshot
<one line — e.g. "step 3 of 5 in progress, failing test understood">

## Plan & progress
- [x] <step> — <note>
- [~] <step> — current state; exact next action: <action>
- [ ] <step>

## Work log
<chronological bullets: what was done and why>

## Files touched
- <path> — <created|modified|deleted> — <why> — <state>

## Verification
- `<command>` → <result>
- <how the receiver verifies current state>

## Decisions & gotchas
<constraints, chosen approach, rejected options, user preferences, traps>

## Open questions
<unresolved items, or "none">

## Next steps
1. <the exact immediate next action>
2. <then>
```
