---
name: git-workflow
description: Complete git, branch hygiene, commit standards, and PR automation workflow instructions. Use when performing git operations, managing branches, committing code, inspecting/opening/updating pull requests, or executing gh CLI commands.
---

# Git Workflow & Branch Hygiene

## Use When
- Executing git operations (branching, staging, committing, pushing, merging).
- Creating or managing feature branches and inspecting branch status.
- Interacting with GitHub PRs, PR comments, or using the `gh` CLI.
- Closing issues via commits/PRs.

## Workflow & Process

### 1. Branch Hygiene & Setup
- **Zero-Trust Branching:** Before making any file changes or commits, run `git status` and verify current branch context.
- **Always Base on Main:** Every new task or feature MUST be implemented on a clean branch checked out directly from `origin/main` (e.g., `git fetch origin && git checkout -b feat/<name> origin/main`).
- **Never Piggyback:** NEVER make changes or commits on top of pre-existing local feature branches unless explicitly requested to edit that specific branch.
- **Branching Sequence:**
  1. **Branch:** Create locally: `git fetch origin && git checkout -b feat/<name> origin/main`
  2. **Commit:** Create local commits as work progresses using Conventional Commits.
  3. **Update:** ALWAYS fetch and merge `origin/main` before new edits or pushing.

### 2. PR Automation & Feedback
- **PR Creation & Updates:** Unless in coach/review mode, when work is complete, check for an existing PR using `unset GITHUB_TOKEN && gh pr view`. If a PR already exists, push commits with `git push` and update metadata with `unset GITHUB_TOKEN && gh pr edit` if needed. Otherwise, push with `git push -u origin HEAD` and create a new PR with `unset GITHUB_TOKEN && gh pr create --fill --body "<description>"`.
- **PR Inline Comments:** ALWAYS fetch inline review comments via `unset GITHUB_TOKEN && gh api repos/:owner/:repo/pulls/:num/comments` (NEVER rely solely on `gh pr view`).
- **Closing Issues:** Use `Closes #<num>` ONLY if an issue is explicitly provided in the active task. NEVER guess issue numbers.

### 3. Credential Handling
- If GitHub CLI (`gh`) fails with `401 Bad credentials`, the shell may have a stale `GITHUB_TOKEN`. **ALWAYS** run `unset GITHUB_TOKEN` before `gh` so it uses local keychain credentials.
