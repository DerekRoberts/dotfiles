---
name: take-over-app
description: 'Takes over an orphaned app repo, stabilizes its CI, and moves it into maintenance mode. Use when the user asks to take over, adopt or stabilize an app, or to put an app into maintenance mode end to end.'
---

> This file lives in `DerekRoberts/dotfiles` at `config/skills/take-over-app/`. `scripts/setup/ai.sh` copies every directory under `config/skills/` into `~/.agents/skills/`. The Renovate and pre-flight details for the final step are in `apply-maintenance-mode`.

# Take Over an App

Adopt an app that no longer has a day-to-day team, make its CI trustworthy, check it with the product owner (PO), then declare maintenance mode.

## Use When
- The user asks to take over, adopt or stabilize an app or repo.
- An app is heading into maintenance mode and its CI, gates or pins need cleanup first.

## Ground Rules
- **No version changes outside version PRs.** Runtime, base image and dependency versions stay as they are in cleanup PRs. Flag mismatches to the user instead of fixing them.
- **PROD only with approval.** Never deploy, promote or write to PROD without the user's explicit approval.
- **Settings are the user's.** Rulesets, environments and secrets are changed by the user; give exact steps.
- **No feature work.** Keep PRs small, one concern each.

## Workflow

### 1. Take over the repo
- Read the README, workflows, open issues and PRs. Open a tracking issue with a checklist of the steps below.

### 2. Clean up CI and Sonar
- Remove dead workflows, jobs and config. Keep what works.
- Sonar: keep the working path (for example SonarCloud automatic analysis). Remove stray project keys, unused `sonar-project.properties` and redundant scanner args. Say in the PR what remains and why.
- Lint workflows (for example `actionlint`).

### 3. Adopt standard results gates
- Use `bcgov/actions/workflow-results` with `needs` listing the jobs it gates. Do not set `title:`; leave the action's default header (`Workflow Results`). Required check names come from the job `name:` (`PR Results`, `Validate Results`, `Analysis Results`), not from `title:`.
- Standard job names: `PR Results`, `Validate Results`, `Analysis Results`. Add results jobs; don't rename existing jobs.
- The user sets the rulesets to require exactly those three checks.

### 4. Pin actions
- Pin every action by release-commit SHA with a version comment: `uses: owner/action@<sha> # vX.Y.Z`.
- Renovate bumps the pins.

### 5. QA with the PO
- Build the UAT checklist, PO test plan and approximation tests with `derive-uat-checklist`. Run checks in TEST only.
- File neutral issues for anything the PO must decide.

### 6. Declare maintenance mode
- Finish with `apply-maintenance-mode`. Close the tracking issue once UAT passes.
