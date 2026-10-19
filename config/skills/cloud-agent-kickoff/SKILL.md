---
name: cloud-agent-kickoff
description: >-
  Use when launching or replying to a cloud agent for issue or PR work, so the
  standing wishes (iterate until CI is green, fix or resolve review threads,
  commit as the user, no tool attribution, thin conductor) go into every
  handoff without retyping.
---

> This file lives in `DerekRoberts/dotfiles` at `config/skills/cloud-agent-kickoff/`. `scripts/setup/ai.sh` copies every directory under `config/skills/` into `~/.agents/skills/`. The rules it relies on are in [`config/instructions.md`](https://github.com/DerekRoberts/dotfiles/blob/main/config/instructions.md) (Hard Stops, Git & Branch Hygiene, Bot Lanes), installed by setup at `~/.local/share/dotfiles/instructions.md`; this skill does not restate them.

# Cloud agent kickoff (standing wishes)

Use this whenever you launch a cloud agent or send a follow-up (`reply`) for issue or PR implementation. Goal: one strong handoff, so the agent owns the loop and the chat stays a thin conductor.

## Before launch
1. Read agent and user memory for scope (allowed orgs and repos), model preference, the user's git commit identity, and any repo-specific hard rules.
2. Confirm the target repo is allowed. If the cloud agent cannot reach it, stop and use the user's local agent fallback instead of forcing a cloud launch.
3. Prefer a **reply to an existing cloud agent** that already owns the PR or branch over launching a duplicate.
4. Pass a model override only when the user asked for one this turn; otherwise use their default.

## Prompt must include (copy into every launch and reply)
- **Goal**: issue or PR link, the problem, and success criteria.
- **Iterate loop**: keep working on the same branch and PR (for a failing bot PR, the new PR from `origin/main` that Bot Lanes requires) until CI is green AND still-valid review feedback is addressed. Stop only for user blockers (secrets, product decisions, repo access). Never merge.
- **Review threads**: for each open thread, verify it against current code. Still valid: make a minimal fix and push. Outdated, wrong or intentional won't-fix: resolve the thread without replying and give the one-line reason in the final summary.
- **Commit identity and no attribution**: follow the `config/instructions.md` Hard Stops. Set `git config user.name` and `user.email` to the user before the FIRST commit, add no attribution trailers or footers, and confirm `git log --format='%an <%ae>' origin/<base>..HEAD` lists only the user before handing over.
- **Scope**: only the named repos. Do not touch other orgs or repos unless the user named them.
- **PR hygiene**: branch and PR selection follow Bot Lanes. Push to the existing PR when one exists, except a bot's PR (Renovate, Dependabot, Mend), which is fixed with a new PR from `origin/main` and never pushed to. Never open a duplicate PR for the same fix.

## Attribution reality
Cloud agents default their git author to the tool's bot account at the platform layer, and desktop attribution settings don't apply to them. Setting git `user.name` and `user.email` inside the run before the first commit works, so the commit-identity line above is mandatory.

If an earlier commit already has the wrong author, the author check fails: stop and report it to the user as a blocker. Never rewrite or force-push history (Hard Stops).

## After launch
1. Tell the user once (PR or agent link). Do not babysit CI or re-investigate from chat unless they ask or you're blocked.
2. When the cloud agent finishes: if the user asked to be told, send a short ready or blocked note; otherwise stay quiet on routine completions.
3. For follow-ups, `reply` to the same agent with the same standing block plus the new delta; never send a weaker half-prompt.

## Optional one-liner to prepend
`Follow the standing cloud-agent kickoff rules (commit as the user from the first commit; iterate until CI is green and review is done; fix or resolve threads, reasons in the summary; no tool co-author or footer; same PR only, never a bot's PR).`
