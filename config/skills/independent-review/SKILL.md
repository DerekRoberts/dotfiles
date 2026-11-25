---
name: independent-review
description: >-
  Before marking any PR Ready, have a fresh reviewer (a separate agent or
  subagent, not the one that wrote the change) read the full diff. Small
  findings are fixed in the same PR; only real scope creep is flagged.
  Findings are never posted as PR comments.
---

> This file lives in `DerekRoberts/dotfiles` at `config/skills/independent-review/`. `scripts/setup/ai.sh` copies every directory under `config/skills/` into `~/.agents/skills/` (and links them for Claude Code). If a skill loader is not available, read this file from that path or from `~/Repos/dotfiles/config/skills/independent-review/SKILL.md`.

# Independent review before Ready

Follow this skill before marking any PR Ready, after the author believes the change is complete. This is a judgment pass on the diff. It does not replace `verify-against-brief` (brief checks and, for high-stakes PRs, existing scanners and tests) or the PR Review Threads rule (handling comments already on the PR).

## Who reviews

- The reviewer must be a separate agent or subagent from the one that wrote the change. The author must not review their own diff.
- The reviewer reads the full current diff, not a summary or the author's report.

## What to check

- Correctness: the change does what the brief or ask requires, and nothing obviously broken.
- Edge cases and failure modes: likely, costly, or silent failures (see Implementation Discipline), including races, skipped paths, and already-exists cases.
- Safety: no secrets, no unsafe defaults, and no weaker Hard Stops or production safeguards.
- Fit with the stated goal: no extra scope, and no missed part of the ask.

## What to do with findings

- Small findings are fixed in the same PR. Do not open an issue or send them to triage.
- Flag only real scope creep (a change that does not belong in this PR) to the user in chat, and leave it out of the PR.
- Never post reviewer findings as PR comments, reviews, or review threads. Report them in chat (to the author agent or the user). Comments that other bots already posted on the PR are still handled by the PR Review Threads rule; this pass does not add more.
- After fixes are pushed, a reviewer separate from the author reads the full current diff again, including the fix commits. The PR is not Ready until CI is green again and every finding is either fixed and confirmed in that re-read or flagged as scope creep.
