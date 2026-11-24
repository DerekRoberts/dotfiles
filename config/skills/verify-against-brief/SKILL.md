---
name: verify-against-brief
description: >-
  Before marking any PR Ready, check the change against the brief's Done-when
  lines (or the issue or ask if there is no brief). "How it was verified" must
  cite those checks, not just green CI. For high-stakes PRs (PROD, security,
  or another team's repo), run one extra break-it pass with existing scanners
  and tests.
---

> This file lives in `DerekRoberts/dotfiles` at `config/skills/verify-against-brief/`. `scripts/setup/ai.sh` copies every directory under `config/skills/` into `~/.agents/skills/` (and links them for Claude Code). If a skill loader is not available, read this file from that path or from `~/Repos/dotfiles/config/skills/verify-against-brief/SKILL.md`.

# Verify against the brief

Follow this skill before marking any PR Ready, and when writing a brief's **Done when** or a PR's **How it was verified**.

## Done-when checks

- Each **Done when** line names a check that can fail if the outcome is unmet (a test, CI job, command, or live `gh`/file assertion). A measurable wish with no failing check is not enough.
- If there is no brief, use the issue's acceptance criteria or the user's ask the same way.
- The PR's **How it was verified** line must cite those checks and their results. "CI green" alone is not enough, even when CI is required.
- If a named check fails or cannot be run, the PR is not Ready.

## High-stakes break-it pass

Required only when the PR touches PROD, security, or another team's repo (say so in **What could go wrong**, as the Core PR-summary rule already requires).

- Run one extra pass that tries to violate the brief, using scanners and tests that already exist in the repo or standard toolchain. The agent only orchestrates; it does not invent a new checker or act as the judge of the diff.
- Write the result in **What could go wrong** and **How it was verified**.
- Do not add a new bot, post PR comments, add a default CI gate, or introduce a paid service. Rules, then scanners, then humans (ADR-030 in `DerekRoberts/brain`).
