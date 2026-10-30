# Baton Pass handoff — full template and worked example

Loaded on demand from [SKILL.md](../SKILL.md). The compact template there
has the same structure; this page explains what each section is for and
shows a worked example, so a handoff survives a model switch with nothing
lost.

## Writing rules

- Write for an agent with zero context. Assume it cannot see this
  conversation, cannot see any plan that lived only in your head, and may
  not even be the same product you are.
- Past tense for completed work, present tense for current state, future
  for next steps — never blur them.
- Concrete over abstract: "`ruff check .` exits 1: 2 findings in
  src/cli.py" beats "linting is broken".
- Include the negative space: files examined and rejected, commands that
  failed, approaches ruled out. This is what saves the receiver from
  re-walking your path.
- If a section has nothing to say, write `none` — never delete the
  section. Receivers rely on every handoff having the same sections in the
  same order.

## Section guidance

### Header block

`By` records the writing agent/model (use the name you know for yourself;
write "unknown" if none). `Repo` records the root path, branch, and HEAD
sha so the receiver can spot if it is somewhere else. `Working tree`
previews uncommitted state; the details live in Files touched.

### Objective

The user's ask as close to their words as possible, plus clarifications
agreed later. Do not summarize it into something narrower than they
actually asked for.

### Status snapshot

One line, the highest-value line in the file: if the receiver reads only
this, it must know what it is walking into.

### Plan & progress

Reuse the plan if one already exists (todo list, plan file). Mark steps:

- `[x]` done — add a one-phrase note of outcome
- `[~]` in progress — state where it stands, then `exact next action:`
  followed by the concrete action. This is the single most valuable line
  in the file.
- `[ ]` pending — one line each

### Work log

Chronological bullets, one per meaningful action, each with its *why*. A
receiver can skip this section to save context, but needs it whenever it
questions why a step's outcome is what it is.

### Files touched

`path — created|modified|deleted — why — state`. State includes
committed/uncommitted and complete/partial. Include files examined and
rejected, with why.

### Verification

Every significant command run and its result (exit code, pass/fail,
failure text). Then one line: how the receiver should verify the current
state before acting. If a command failed and the cause is known, record
both the failure and the diagnosis.

### Decisions & gotchas

Constraints ("must stay under three packages"), the chosen approach with
the rejected alternative and why, user preferences learned this session
("prefers squash merges"), and traps ("do not run the formatter without an
explicit path"). If truly none, write `none`.

### Open questions

Things asked of the user but not yet answered, ambiguities deferred, and
anything you would have asked before continuing. `none` if none.

### Next steps

An ordered list starting with the exact immediate action. Steps must be
executable, not aspirational — "run `pytest tests/test_cache.py -k
flaky` and fix the assertion on line 42", not "keep improving the tests".

## Worked example

Scenario: a user asked an agent to add a lint gate to a Python project's
CI. Mid-task the user says "baton pass, I'll continue in a different
agent". This is what it writes:

```markdown
# Baton Pass — add lint gate to CI

> Receiving agent: read this file fully, then continue the task. Do not
> redo completed steps. Verify before trusting.

- Recorded: 2026-09-21T14:30:05+01:00
- By: glm-5.3-flash (opencode)
- Repo: /home/netsa/work/demo-cli · branch `main` · HEAD 8b4f1c2
- Working tree: 3 uncommitted files — see Files touched

## Objective
"Add ruff and mypy to CI so the build breaks on lint failures, not just
tests." Clarified later: the gate must run on every push, not only PRs.

## Status snapshot
Workflow file written and locally validated; repo lint config not yet
touched; nothing pushed.

## Plan & progress
- [x] read .github/workflows/ci.yml — single "test" job, PR-only trigger
- [~] write .github/workflows/lint.yml — written, needs push trigger added
- [ ] add lint config (setup.cfg) — not started
- [ ] run gate locally and fix findings
- [ ] report results to user

## Work log
- read .github/workflows/ci.yml: one test job, triggered on pull_request only
- chose a separate lint.yml over extending ci.yml: user wants push triggers
- considered putting mypy in the same job; deferred until config exists
- wrote lint.yml with ruff + mypy jobs, validated locally with actionlint

## Files touched
- .github/workflows/lint.yml — created — new lint gate — uncommitted, needs trigger line
- setup.cfg — will be modified next — unstarted
- .github/workflows/ci.yml — read only, no changes (reuse its action-pinning style)

## Verification
- `actionlint .github/workflows/lint.yml` → pass
- not verified: whether the pinned action SHAs still resolve on GitHub

## Decisions & gotchas
- Separate workflow file, not a ci.yml extension — user wants push triggers
- Rejected pre-commit hooks: user asked for a CI gate, not local hooks
- This repo pins GitHub actions by full SHA, not tag — follow that in lint.yml
- setup.cfg, not ruff.toml: repo already uses setup.cfg conventions

## Open questions
- Should the lint gate also run on PRs, or push only? (asked, no answer yet)

## Next steps
1. Add `push:` trigger alongside `pull_request:` in lint.yml
2. Add [tool.ruff] and [mypy] sections to setup.cfg (line-length 100)
3. Run `ruff check .` and `mypy src/` locally; fix findings
4. Answer-or-default the PR-trigger question, then hand results to user
```
