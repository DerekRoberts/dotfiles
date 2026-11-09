---
name: handle-my-tasks
description: >-
  Use when the user says "handle my tasks", "work the board", "work my queue"
  or similar. Picks items from bcgov Project 16 in board order and has Sonnet
  worker subagents build them as PRs, while this session (Opus) plans, checks
  and reports. Add "dry run" to only list what it would pick.
---

> Installed by `scripts/setup/ai.sh`. This skill holds the procedure only; the rules live in `~/Repos/brain` and are read live each run, never copied here.

## Run

1. **Read the rules first.** Read `~/Repos/brain/config/instructions.md` (Bot Lanes: pick order, claiming, Active, Waiting), `~/Repos/brain/repo-rules.md` (role per repo) and `~/Repos/brain/bots/project-queue.md`. If any is missing, stop and say so.
2. **List the board.** `gh project item-list 16 --owner bcgov --limit 200 --format json`. Candidates are `Next` top-down, then `Backlog`; nothing else. Drop archived repos, repos not in `repo-rules.md`, and work outside the repo's role.
3. **Claim check, live.** For each candidate, `gh pr list --repo <repo> --state open --search "<number>"` and check for a branch naming it. Skip any with an open PR or branch, unless the existing-work rule in Bot Lanes says to continue it.
4. **Cap.** Take at most 2 items per run unless the user names more. Skip any item without a clear done state; the user, not you, supplies a missing brief. If the user said "dry run", stop here: list each pick, or skip, with the reason.
5. **Delegate.** Spawn one worker per item with the Agent tool: `model: "sonnet"`, `isolation: "worktree"`, in parallel. Each prompt must stand alone (workers do not see this chat): issue link and body, repo role and scope, the done state, the path `~/Repos/dotfiles/config/instructions.md` and `~/Repos/brain/config/instructions.md` to follow, and the required return: PR link plus the three-line summary (What changes / What could go wrong / How it was verified). Do not read repos or run tests in this session.
6. **Check each result live.** `gh pr view` and `gh pr checks` against the issue's original ask, not the worker's report. Send fixes back to the worker; never report a PR ready from the worker's word.
7. **Card.** When a PR meets the Core ready rule, make sure the card is in `Active` (move it with `gh project item-edit` if automation has not).
8. **Report.** Answer first: what you picked, what you skipped and why. Then per PR: full link and the three lines. End with the human-only steps (merges, anything blocked).
