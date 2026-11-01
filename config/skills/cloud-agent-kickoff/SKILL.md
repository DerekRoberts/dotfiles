---
name: cloud-agent-kickoff
description: >-
  Thin standing paste for cloud-agent launches and replies: Derek Roberts git
  identity, no tool attribution in commits, iterate until CI green and review
  threads cleared, same-PR and Bot Lanes one-liners. Full Hard Stops live in
  config/instructions.md.
---

> Installed by `scripts/setup/ai.sh` to `~/.agents/skills/`. Local agents load [`config/instructions.md`](https://github.com/DerekRoberts/dotfiles/blob/main/config/instructions.md) plus hooks; cloud agents get the paste block below only.

## Conductor (local agent)

- Prefer **reply** to an existing cloud agent that already owns the branch or PR over launching a duplicate.
- Tell the user once (agent or PR link). Do not babysit CI or re-investigate from chat unless they ask or you are blocked.

## Paste into every launch and reply

Add task-specific **Goal**, links, success criteria, and repo scope after this block. Full policy (PAT preference, DB overwrite, Artifactory, Bot Lanes detail): [`config/instructions.md` — Hard Stops & Bot Lanes](https://github.com/DerekRoberts/dotfiles/blob/main/config/instructions.md#hard-stops).

```text
Follow the standing cloud-agent kickoff rules (set git user.name/email to Derek Roberts / derek.roberts@gmail.com before the first commit; iterate until CI green + review done; fix or resolve threads, reasons in the summary; no tool co-author/footer; same PR only).

Cloud Hard Stops (never merge, PR/issue comment, review reply, force-push, tags, repo/org settings, secrets, or oc/kubectl — see config/instructions.md Hard Stops): commits and push are fine.

- Iterate on the same branch and PR until CI is green and every open review thread is fixed or resolved (no PR comments). Stop only for user blockers.
- Bot PRs (Renovate, Dependabot, Mend): new PR from origin/main; never push to the bot PR (Bot Lanes).
- Before the first commit: git config user.name "Derek Roberts" and user.email "derek.roberts@gmail.com". No Co-authored-by, Generated-with, or tool footers; verify git log --format='%B' origin/<base>..HEAD is clean before handoff.
- PR body: three plain lines — What changes / What could go wrong / How it was verified.
```

## Optional one-liner to prepend

`Follow the standing cloud-agent kickoff rules (Derek Roberts git identity from first commit; iterate until CI green + review done; no tool co-author/footer; same PR only).`
