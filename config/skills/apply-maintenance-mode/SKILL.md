---
name: apply-maintenance-mode
description: 'Draft, in development. Automates the transition of a repository into "Maintenance Mode" (Renovate auto-merge, unconditional tests, deployment upgrades). Not ready to ship. Use only after a repository has passed the github-repo-setup maturity audit with no Tier-1 blockers.'
---

> **Draft, in development.** Maintenance mode is still being worked out. This file lives in `DerekRoberts/dotfiles` at `config/skills/apply-maintenance-mode/`. `scripts/setup/ai.sh` copies every directory under `config/skills/` into `~/.agents/skills/`, which is what Derek's tools load. Do not copy this into the `bcgov/quickstart-openshift` template or its `AGENTS.md`. It may move there, or to a BC Gov library, once it settles. Decision record: ADR-018 in `DerekRoberts/brain`. Moved from [bcgov/agent-skills#60](https://github.com/bcgov/agent-skills/pull/60); that repo is being archived.

> **Upstream catalog check (2026-10-08).** No upstream skill covers this. Checked [skills.sh](https://www.skills.sh/), the [Microsoft Agent Skills catalog](https://microsoft.github.io/skills/), [anthropics/skills](https://github.com/anthropics/skills), and [github/awesome-copilot](https://github.com/github/awesome-copilot). The closest are [renovate-merge](https://www.skills.sh/yamadashy/skills/renovate-merge) and [pr-deps-merge](https://www.skills.sh/yamadashy/skills/pr-deps-merge), which only merge Renovate or Dependabot PRs that are already open, and [renovate](https://www.skills.sh/terminalskills/skills/renovate), a generic Renovate setup. None of them pins `bcgov/renovate-config` to a released tag, requires a BC Gov maturity audit with no Tier-1 blockers, or upgrades TEST/PROD so production promotes the same immutable artifact from `main`. That BC Gov workflow is why this stays a separate draft.

# Apply Maintenance Mode

Automate the scaffolding and configuration required to put a mature BC Gov repository into a hands-off, automated maintenance mode. This enforces zero-review auto-merges for dependencies, provided all CI tests pass.

## Use When
- The user asks to put a specific app, repo, or service into "maintenance mode" or "autopilot".
- The repository has an acceptable maturity-audit result, defined below.

## Don't Use When
- The maturity audit has any Tier-1 blocker, or there is no automated test suite.
- Required CI checks can be skipped and still report success.
- Branch protection or rulesets require human approving review on the merge target, and there is no explicitly approved repository policy that exempts Renovate.
- The user explicitly asks for manual deployment gates.

## Pre-flight Checklist (CRITICAL)

An acceptable maturity-audit result is all of the following. Anything less is not hands-off. Merely finding a test suite is not enough, including at the branch-protection and deploy steps below.

1. The `github-repo-setup` maturity audit has been run against the repository state being transitioned, and its `MATURITY_REPORT.md` has **no Tier-1 blockers** (that skill's blocking remediation tier). If the report is stale (it does not cover the current tree, or the repo has changed since it was written), rerun the audit and confirm the new report has no Tier-1 blockers. A historical report is not an acceptable result. The skill is [`bcgov/agent-marketplace` `skills/community/github-repo-setup`](https://github.com/bcgov/agent-marketplace/blob/main/skills/community/github-repo-setup/SKILL.md). Do not depend on the copy in `bcgov/agent-skills`; that repo is being archived.
2. An automated CI test suite exists (`.github/workflows/` test workflows, or test scripts in `package.json` that those workflows actually run).
3. Every Renovate PR actually runs **all** required checks. Confirm this on recent Renovate pull requests, not just on the workflow file:
   - Each required status check completed with `success`, not `skipped` and not `neutral`.
   - No job-level `if:` (or equivalent) lets a required test skip and still count as a pass. A wrapper job that succeeds when its tests were skipped does not qualify.
   - Branch protection requires those checks before merge. Auto-merge must be unable to land a Renovate PR whose required checks did not run.
4. **Approving-review requirements** do not leave Renovate PRs waiting forever on the branch Renovate targets (usually `main`). Native auto-merge still honors required approving reviews; passing status checks alone is not zero-review maintenance mode. Inspect branch protection and repository rulesets, for example `gh api repos/{owner}/{repo}/branches/{branch}/protection` and `gh api repos/{owner}/{repo}/rulesets --paginate`. If protection or an active ruleset requires approving review(s) and Renovate is not covered by an **explicitly approved** repository policy (documented exemption, ruleset bypass for `renovate[bot]`, or equivalent the user has signed off on), **HARD-STOP**. Do not disable or loosen required reviews for all pull requests. If an exemption is needed, give the user exact settings to apply; only mutate `/protection` or `/rulesets` when the user's instructions and local guardrails allow it.

- **IF THE AUDIT IS MISSING, STALE, HAS A TIER-1 BLOCKER, THERE IS NO TEST SUITE, REQUIRED CHECKS CAN SKIP AND STILL PASS, OR REQUIRED APPROVING REVIEWS BLOCK RENOVATE WITHOUT AN APPROVED EXEMPTION**: **HARD-STOP**. Tell the user. Do not change the repo. An automated test suite that actually runs, on a repo with no Tier-1 blockers, is a hard prerequisite for safe auto-merge. Point them at building the tests or running the `github-repo-setup` audit (marketplace path above) before trying again.
- **IF ALL FOUR HOLD**: Proceed with the steps below.

## Workflow

### 1. Repository API Configuration (GitHub Settings)
Use the `gh` CLI to enable native auto-merge and validate merge requirements on the repository:
- Enable Auto-Merge: `gh api -X PATCH repos/{owner}/{repo} -F allow_auto_merge=true`
- **Inspect approving-review rules** on the default branch (branch protection and repository rulesets; pre-flight item 4). Required approving reviews block native auto-merge even when CI is green. Either confirm Renovate is exempt per an explicitly approved repository policy, or hard-stop and tell the user what must change. Never silently remove or weaken required reviews for all pull requests.
- Ensure branch protections require the test suite status checks to pass before merging. Those checks must be the jobs that run the tests (pre-flight item 3). A required check that can be skipped and still report success does not qualify. Re-check recent Renovate PRs: every required check completed `success`, not `skipped`.

### 2. Renovate Configuration
Modify or create `renovate.json` (or `renovate.json5`) at the repository root.
- Resolve the latest stable three-segment release and inherit from it, for example: `"extends": ["github>bcgov/renovate-config#<YYYY.M.Patch>"]` (current releases look like `2026.9.26`). Do not use the unversioned `main` preset for production (`github>bcgov/renovate-config` with no ref, or `#main`). The preset README marks that as testing-only and warns it may contain breaking changes.
- Renovate can still propose pin updates. Leave the pin where its pin manager can see it. Do not add a local rule that freezes the preset forever.
- The `bcgov/renovate-config` preset enables `automerge: true` for safe minor and patch updates, so do not add custom local auto-merge rules.

### 3. CI/CD Deployment Pipeline Upgrades
Analyze `.github/workflows/` and standardize the deployment pipeline. Teams are explicitly moving away from `workflow_dispatch` gates.

- **Legacy Anti-Pattern (`workflow_dispatch`)**: If you detect a `workflow_dispatch` gated PROD deployment, mark it as legacy and **upgrade it to Release-Gated**.
- **Target Pattern 1: Release-Gated**:
  - `TEST` deploys automatically on push to `main` and records the tested immutable artifact.
  - `PROD` deploys when a GitHub Release is published (`on: release: types: [published]`), only after verifying that its tag targets a commit on `main`; promote the same artifact that passed CI and `TEST`.
  - A published release can point at an arbitrary tag or commit, so the release event alone is not enough. If the tag SHA is not on `main`, or the workflow rebuilds, retags, or picks a different digest, do not deploy PROD.
- **Target Pattern 2: Straight-to-TEST+PROD**:
  - `TEST` and `PROD` deploy automatically and sequentially on push to `main`, promoting that same immutable artifact from the pipeline that passed CI. PROD follows TEST for that artifact; it does not build a second one.

Migrate the pipeline to the appropriate target pattern based on the repo's existing behavior or explicit user instruction.

## Rules
- **Kill `workflow_dispatch`**: Under no circumstances should you generate or preserve a `workflow_dispatch` trigger for a production deployment. It is an inconsistent legacy pattern.
- **Pin `bcgov/renovate-config`**: Do not write verbose custom Renovate rules locally when the central preset applies, and do not float the preset on `main`.
- **Same artifact to PROD**: PROD never deploys a revision that did not pass CI and TEST, and never a release tag whose SHA is off `main`.
- **Checks must actually run**: Do not treat a test suite that exists on disk, or a required check that skipped, as a pass.

## Examples
- The user asks: "Enable maintenance mode for this repo". You run the pre-flight (no Tier-1 blockers, tests that cannot skip, Renovate PRs actually running those checks, and no approving-review blockers without an approved Renovate exemption), then pin the preset to a `YYYY.M.Patch` release and apply the deploy pattern. If any pre-flight item fails, you stop.

## Edge Cases
- If the repository has a complex mono-repo setup, ensure branch protections cover all critical path tests, and that none of those jobs can skip and still report success.

## References
- `gh` CLI documentation for setting up repository features.
- `bcgov/renovate-config` releases (three-segment `YYYY.M.Patch` tags only; not `main`).
- `github-repo-setup` maturity audit: [bcgov/agent-marketplace](https://github.com/bcgov/agent-marketplace/blob/main/skills/community/github-repo-setup/SKILL.md). Tier-1 items in its report are blockers.
