---
name: apply-maintenance-mode
description: 'Draft, in development. Automates the transition of a repository into "Maintenance Mode" (Renovate auto-merge, unconditional tests, deployment upgrades). Not ready to ship. Use only after a read-only pre-flight finds no Tier-1 blockers.'
---

> **Draft, in development.** Maintenance mode is still being worked out. This file lives in `DerekRoberts/dotfiles` at `config/skills/apply-maintenance-mode/`. `scripts/setup/ai.sh` copies every directory under `config/skills/` into `~/.agents/skills/`, which is what Derek's tools load. Do not copy this into the `bcgov/quickstart-openshift` template or its `AGENTS.md`. It may move there, or to a BC Gov library, once it settles. Decision record: ADR-018 in `DerekRoberts/brain`. Moved from [bcgov/agent-skills#60](https://github.com/bcgov/agent-skills/pull/60); that repo is being archived.

> **Upstream catalog check (2026-10-08).** No upstream skill covers this. Checked [skills.sh](https://www.skills.sh/), the [Microsoft Agent Skills catalog](https://microsoft.github.io/skills/), [anthropics/skills](https://github.com/anthropics/skills), and [github/awesome-copilot](https://github.com/github/awesome-copilot). The closest are [renovate-merge](https://www.skills.sh/yamadashy/skills/renovate-merge) and [pr-deps-merge](https://www.skills.sh/yamadashy/skills/pr-deps-merge), which only merge Renovate or Dependabot PRs that are already open, and [renovate](https://www.skills.sh/terminalskills/skills/renovate), a generic Renovate setup. None of them pins `bcgov/renovate-config` to a released tag, requires a BC Gov maturity audit with no Tier-1 blockers, or upgrades TEST/PROD so production promotes the same immutable artifact from `main`. That BC Gov workflow is why this stays a separate draft.

# Apply Maintenance Mode

Automate the scaffolding and configuration required to put a mature BC Gov repository into a hands-off, automated maintenance mode. This enforces zero-review auto-merges for dependencies, provided all CI tests pass.

## Use When
- The user asks to put a specific app, repo, or service into "maintenance mode" or "autopilot".
- The repository has an acceptable maturity-audit result, defined below.

## Don't Use When
- The pre-flight finds any Tier-1 blocker (defined below), or there is no automated test suite.
- Branch protection or rulesets require approving review on the merge target, and nothing (such as the `renovate-approve` app) auto-approves Renovate PRs.
- The user explicitly asks for manual deployment gates.

## Ground Rules
- **No repo changes before pre-flight passes.** Do not create branches, commits, or files in the repository, including audit output such as `MATURITY_REPORT.md`. Keep audit reports outside the checkout (for example a scratch directory) or post a summary in the tracking issue.
- **Never change repository settings.** Branch protection, rulesets, environments, secrets, and repository options (such as `allow_auto_merge`) are changed by a human. Read them with `gh api` if you can; for anything that must change, give the human numbered, click-by-click steps.
- **Hard stops are rule-based.** If any Tier-1 condition below matches, stop. Do not weigh it against other strengths of the repo.

## Tier-1 Blockers

Any one of these is a hard stop. Report each one with evidence (file, workflow, check name, PR number).

1. **Untested Renovate updates.** Renovate updates a manifest, lockfile, Dockerfile, workflow, or path (for example an app directory, a script, a crawler, a migration tool) that no *required* check builds and tests. Compare the paths Renovate PRs actually touch against the paths each required check exercises.
2. **Shared secrets across environments.** Credentials used by PR previews, TEST, and PROD are the same repository-level secret instead of per-environment secrets (GitHub Environments), so a PR or TEST workload could read or damage PROD.
3. **Checks that pass when tests skip.** A required check can report `success`, `skipped`, or `neutral` when its tests did not run (job-level `if:`, path filters, `continue-on-error`, a wrapper job that ignores skipped dependencies).
4. **No test suite.** No automated tests run in CI for the code being kept up to date.
5. **Missing or stale audit.** The `github-repo-setup` maturity audit has not been run against the current tree, or its report lists any item in that skill's Tier-1 (blocking) remediation tier.

## Pre-flight Checklist (CRITICAL)

Run every item. Write nothing to the repository while doing so.

1. **Maturity audit.** Run the `github-repo-setup` audit ([`bcgov/agent-marketplace` `skills/community/github-repo-setup`](https://github.com/bcgov/agent-marketplace/blob/main/skills/community/github-repo-setup/SKILL.md)) against the current default branch. That skill writes `MATURITY_REPORT.md` into the root of the repo it audits, so run it only against a throwaway copy outside the working checkout (for example a fresh clone in a scratch directory), never the real checkout. The report must have no Tier-1 items. Do not depend on the copy in `bcgov/agent-skills`; that repo is being archived.
2. **Test suite exists and runs in CI** (`.github/workflows/` jobs that execute the tests, not just scripts on disk).
3. **Required checks cover everything Renovate updates.** It is not enough that some required checks exist.
   - List what Renovate updates: run through `renovate.json`'s managers and recent Renovate PRs (`gh pr list --author app/renovate --state all --limit 20 --json number,files`).
   - For each manifest or path, name the required check that builds and tests it. Anything without one is Tier-1 item 1.
   - On recent Renovate PRs, every required check completed `success`, not `skipped` or `neutral`.
   - Recommended pattern, from `bcgov/quickstart-openshift`: each workflow ends with a distinctly named results job (for example `PR Results`, `Analysis Results`) that `needs:` every other job in that workflow, runs with `if: always()`, and fails when any needed job's result is `failure` or `cancelled`, or `skipped` when that job was not expected to skip. The ruleset then requires those results checks, one per workflow. A results job only gates the jobs listed in its `needs:`, so every new job must be added there; check that no job is missing. Test steps must fail normally: a step with `continue-on-error: true` leaves its job `success` even when tests fail, so the results job cannot see it. If the repo lacks this, propose it as a code PR (a human still adds the checks to the ruleset).
4. **Renovate PRs get their required review automatically.** Maintenance mode runs without humans; they step in only when something breaks or needs judgement. The standard setup is the [`renovate-approve`](https://github.com/apps/renovate-approve) GitHub App, which approves Renovate PRs and counts as the required review for them. Native auto-merge still honors required approving reviews, so check:
   - Read branch protection and rulesets on the branch Renovate targets, for example `gh api repos/{owner}/{repo}/branches/{branch}/protection` and `gh api repos/{owner}/{repo}/rulesets --paginate`.
   - If approving reviews are required, confirm recent Renovate PRs carry an approval from `renovate-approve[bot]` and that it satisfies every review rule (for example required code-owner review or "approval of the most recent push" can still block it).
   - If required reviews would block Renovate PRs and nothing auto-approves them, hard stop and give the human the steps to install `renovate-approve` (Settings step 3). Never suggest disabling required reviews for all pull requests.
5. **Environment secrets.** Secret values are write-only, so names alone cannot prove separation. List repository-level and environment-level secret names (`gh secret list`, `gh secret list --env <env>`), then map which secrets each PR, TEST, and PROD job references and which `environment:` it runs in. A credential read from repository level by more than one of those is Tier-1 item 2. Where names differ but the values might be the same credential, ask the human to confirm they are distinct; until they do, treat it as Tier-1.
6. **Local Renovate overrides.** Read `renovate.json` / `renovate.json5` (and `package.json` `renovate` blocks). Flag any local setting that weakens the preset, such as `minimumReleaseAge: "0 days"`, `automerge` on major updates, broader `automergeType`, `ignoreTests: true`, or disabled vulnerability alerts. Each must be removed in the follow-up PR or explicitly signed off by the human in the tracking issue.

- **IF ANY TIER-1 BLOCKER MATCHES, OR ITEM 4 OR 6 IS UNRESOLVED**: **HARD-STOP**. Change nothing. Report each blocker with evidence, the code PRs that would fix it, and click-by-click settings steps for the human.
- **IF ALL ITEMS PASS**: Proceed with the steps below.

## Workflow

### 1. Repository Settings (human steps)
You do not change settings. Read the current values and give the human only the steps still needed, for example:

1. Settings → General → Pull Requests → tick **Allow auto-merge**. (Check with `gh api repos/{owner}/{repo} --jq .allow_auto_merge`.)
2. Settings → Rules → Rulesets → *(ruleset for the default branch)* → **Require status checks to pass** → add each workflow's results check.
3. If pre-flight item 4 found no auto-approval, install the [`renovate-approve`](https://github.com/apps/renovate-approve) app on the repository (the app page → **Configure** → select the org → **Only select repositories** → add the repo → **Save**). Do not loosen reviews for anyone else.
4. Settings → Environments → *(each environment)* → add per-environment secrets, then delete the shared repository-level copies and rotate PROD values. Some services (databases in particular) only read a password when first initialised, so rotating may need a real credential change, not just a new secret.

### 2. Renovate Configuration
Modify or create `renovate.json` (or `renovate.json5`) at the repository root.
- Resolve the latest stable three-segment release and inherit from it, for example: `"extends": ["github>bcgov/renovate-config#<YYYY.M.Patch>"]` (current releases look like `2026.9.26`). Do not use the unversioned `main` preset for production (`github>bcgov/renovate-config` with no ref, or `#main`). The preset README marks that as testing-only and warns it may contain breaking changes.
- Renovate can still propose pin updates. Leave the pin where its pin manager can see it. Do not add a local rule that freezes the preset forever.
- The `bcgov/renovate-config` preset enables `automerge: true` for safe minor and patch updates, so do not add custom local auto-merge rules.
- Remove the weakening overrides flagged in pre-flight item 6 unless the human signed them off.
- If the repo already pins the latest release and has no weakening overrides, make no Renovate change.

### 3. CI/CD Deployment Pipeline
Analyze `.github/workflows/` and bring the deploy path to one of the target patterns. Do not assume TEST deploys on `push` to `main`; find the real trigger.

- **Triggers.** TEST may deploy on `push` to `main`, or from a `workflow_run` that follows the `main` build. For `workflow_run`, the deploy must check `github.event.workflow_run.conclusion == 'success'`, `head_branch == 'main'`, and `event == 'push'`, and deploy the artifact built for `github.event.workflow_run.head_sha`, not whatever is newest.
- **Same artifact means same digest.** Promotion must deploy the image digest that passed CI and TEST. Retagging a mutable tag (such as `latest` or `test` → `prod`) counts only if the workflow resolves and verifies the digest it is promoting. Prefer promoting by digest, for example recording and looking up digests with [`bcgov/actions` `image-tracker`](https://github.com/bcgov/actions/tree/main/image-tracker). A retag without digest verification is a finding to fix, not a pass.
- **`workflow_dispatch` that can deploy PROD.** It may stay only if it can deploy nothing but a digest that already passed TEST (it looks up and verifies that digest; it never builds). Otherwise flag it and replace it with one of the target patterns.
- **Target Pattern 1: Release-Gated**:
  - `TEST` deploys automatically from `main` (push or `workflow_run`) and records the tested digest.
  - `PROD` deploys when a GitHub Release is published (`on: release: types: [published]`), only after verifying that its tag targets a commit on `main`; promote the same digest that passed CI and `TEST`.
  - A published release can point at an arbitrary tag or commit, so the release event alone is not enough. If the tag SHA is not on `main`, or the workflow rebuilds or cannot verify the digest, do not deploy PROD.
- **Target Pattern 2: Straight-to-TEST+PROD**:
  - `TEST` and `PROD` deploy automatically and sequentially from `main`, promoting the same digest from the pipeline that passed CI. PROD follows TEST for that digest; it does not build a second one.

If the existing pipeline already meets a target pattern, leave it alone and say so.

## Rules
- **Hands off settings**: Never change repository settings, rulesets, environments, or secrets. Give the human steps.
- **Nothing written before pre-flight passes**: No branches, commits, or report files in the repo until every pre-flight item passes.
- **Pin `bcgov/renovate-config`**: Do not write verbose custom Renovate rules locally when the central preset applies, and do not float the preset on `main`.
- **Same digest to PROD**: PROD never deploys a digest that did not pass CI and TEST, and never a release tag whose SHA is off `main`.
- **Checks must actually run and cover what Renovate changes**: A test suite on disk, a skipped required check, or a required check that ignores a Renovate-updated path is not a pass.

## Examples
- The user asks: "Enable maintenance mode for this repo". You run the pre-flight without writing to the repo. All items pass, so you open a PR that pins the preset and fixes the deploy path, and list the settings steps for the human.
- First real run (2026-10-08): the repo's Renovate config updated a data crawler and utility scripts that no required check tested, database and email credentials were shared repo-level secrets across PR, TEST, and PROD, and the only required test gate was a small end-to-end suite. Tier-1 items 1 and 2 matched, so the skill stopped, changed nothing, proposed a code PR adding results-gated tests, and gave settings steps for per-environment secrets.

## Edge Cases
- **Monorepos**: map each Renovate-updated directory to a required check; one green check for one app does not cover the others.
- **Path-filtered workflows**: an event-level `paths` / `paths-ignore` filter means the workflow never starts, so its required results check never reports and the PR waits forever. Required workflows must trigger on every PR and apply path conditions at the job level, with the results job treating those skips as expected.

## References
- `bcgov/quickstart-openshift` workflows: results-job pattern (`PR Results`, `Analysis Results`).
- `bcgov/actions` `image-tracker`: digest lookup for promotion.
- `bcgov/renovate-config` releases (three-segment `YYYY.M.Patch` tags only; not `main`).
- `github-repo-setup` maturity audit: [bcgov/agent-marketplace](https://github.com/bcgov/agent-marketplace/blob/main/skills/community/github-repo-setup/SKILL.md).
