external-systems ground rules (every repo of the external-systems GitHub org; clones in ~/external-systems/<repo>):
- Before working in an org repo, load the external-systems skill and read the repo's AGENTS.md.
- Clones stay on main: `git switch main && git pull --ff-only` at the start and end of a session. Never commit in a clone.
- Every change gets its own worktree and branch from origin/main, so several sessions can work in one repo at once: `git -C ~/external-systems/<repo> fetch` then `git -C ~/external-systems/<repo> worktree add ~/external-systems/.worktrees/<repo>/<branch> -b <branch> origin/main`. Work, commit, push and open the PR from there.
- At session start, remove worktrees whose PR merged or closed (`gh pr view <branch> --json state`): `git worktree remove <path>`, `git branch -D <branch>`, `git worktree prune`.
- Never push to main, approve or bypass a ruleset, or merge unless the owner allows it for that repo in the session. Never deploy (`clan machines update`, `nixos-rebuild`) or run `clan vars generate` on main: give the owner the command.
- Before pushing: `git add -A`, `fmt`, `check`. Say in the PR what ran and its result.
- Secrets come from 1Password through varlock (`.env.schema`, `varlock run -- <cmd>`), never from a `.env` file. Never print or write a secret, and no tokens, IP addresses or account ids in a public repo, commit or PR.
