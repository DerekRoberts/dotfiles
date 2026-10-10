---
name: apply-maintenance-mode
description: 'Draft, in development. Automates the transition of a repository into "Maintenance Mode" (Renovate auto-merge, unconditional tests, deployment upgrades). Not ready to ship. Use only after a read-only pre-flight finds no Tier-1 blockers.'
---

> **Draft, in development.** Maintenance mode is still being worked out. This file lives in `DerekRoberts/dotfiles` at `config/skills/apply-maintenance-mode/`. `scripts/setup/ai.sh` copies every directory under `config/skills/` into `~/.agents/skills/`, which is what Derek's tools load. Do not copy this into the `bcgov/quickstart-openshift` template or its `AGENTS.md`. It may move there, or to a BC Gov library, once it settles. Decision record: ADR-018 in `DerekRoberts/brain`. Moved from [bcgov/agent-skills#60](https://github.com/bcgov/agent-skills/pull/60); that repo is being archived.

> **Upstream catalog check (2026-10-08).** No upstream skill covers this. Checked [skills.sh](https://www.skills.sh/), the [Microsoft Agent Skills catalog](https://microsoft.github.io/skills/), [anthropics/skills](https://github.com/anthropics/skills), and [github/awesome-copilot](https://github.com/github/awesome-copilot). The closest are [renovate-merge](https://www.skills.sh/yamadashy/skills/renovate-merge) and [pr-deps-merge](https://www.skills.sh/yamadashy/skills/pr-deps-merge), which only merge Renovate or Dependabot PRs that are already open, and [renovate](https://www.skills.sh/terminalskills/skills/renovate), a generic Renovate setup. None of them pins `bcgov/renovate-config` to a released tag, requires a pre-flight with no Tier-1 blockers, or upgrades TEST/PROD so production promotes the same immutable artifact from `main`. That BC Gov workflow is why this stays a separate draft.

# Apply Maintenance Mode

Automate the scaffolding and configuration required to put a mature BC Gov repository into a hands-off, automated maintenance mode. This enforces zero-review auto-merges for dependencies, provided all CI tests pass.

## Use When
- The user asks to put a specific app, repo, or service into "maintenance mode" or "autopilot".
- The read-only pre-flight below finds no Tier-1 blocker.

## Don't Use When
- The pre-flight finds any Tier-1 blocker (defined below).

Maintenance mode is about merging dependency updates without humans. It does not remove deploy approval: a human approval gate on PROD (a required reviewer on the PROD environment) is fine.

## Ground Rules
- **No repo changes before pre-flight passes.** Do not create branches, commits, or files in the repository, including audit output such as `MATURITY_REPORT.md`. Keep audit reports outside the checkout (for example a scratch directory) or post a summary in the tracking issue.
- **Never change repository settings.** Branch protection, rulesets, environments, secrets, app installs, and repository options (such as `allow_auto_merge`) are changed by a human. Read them with `gh api` if you can; for anything that must change, give the human numbered, click-by-click steps.
- **Hard stops are rule-based.** If any Tier-1 condition below matches, stop. Do not weigh it against other strengths of the repo.
- **How GitHub treats skips.** A required check that reports `skipped` counts as passing for merge. A required check that never reports at all leaves the PR waiting forever. Design gates with both in mind.

## Tier-1 Blockers

This list is authoritative. The `github-repo-setup` audit has no fixed Tier-1 list, so its findings are evidence for the items below, not blockers of their own. Any one of these is a hard stop. Report each one with evidence (file, workflow, check name, PR number, run URL).

1. **Untested Renovate updates.** Renovate updates a manifest, lockfile, Dockerfile, workflow, or path (an app directory, a script, a migration tool, unused code) that no *required* check builds and tests. Compare the paths Renovate PRs actually touch against the paths each required check exercises. See "What tested means" below.
2. **Fake gates.** A required check can pass when its tests did not run: it reports `skipped` or `neutral`, uses `continue-on-error`, or is a results job that ignores skipped or missing jobs. A results job with `needs: []` (or one that does not list the test jobs) gates nothing and is a fake gate.
3. **No test suite.** No automated tests run in CI for the code being kept up to date.
4. **Broken release pipeline.** The merge/release pipeline on the default branch has not succeeded recently: its latest completed run failed, or its last success is more than about a month old. A pipeline that has been failing for months means auto-merged updates would pile up undeployed and untested in TEST.
5. **renovate-approve can't approve.** The [`renovate-approve`](https://github.com/apps/renovate-approve) app has no current access to the repo, or a review rule blocks its approval (pre-flight item 4). The fix is a settings step for the human (Workflow step 1, item 3), not a code PR or a question.
6. **Unapproved weakening overrides.** Local Renovate settings that weaken the preset (pre-flight item 6) that the user has not approved. To get approval, ask the user in chat; record the answer in the issue.
7. **End-of-life runtime or component.** Any runtime or component the repo builds, deploys or tests on is past its end-of-life date (pre-flight item 7): a database major, a Node or Java version, a base image, and so on. This includes images Renovate can't track, such as an internal-registry `postgresql:12`. A PostgreSQL or PostGIS major behind `bcgov/quickstart-openshift`'s current one counts too, even before it is end-of-life. The fix is an upgrade PR, a not-safe change in its own PR, never bundled with other maintenance-mode changes. Pick the version `bcgov/quickstart-openshift` uses on its default branch; do not ask. A database major upgrade PR also carries the data migration.

Not blockers: secrets or credentials shared across PR, TEST, and PROD (repository-level or hardcoded), and shared internal services (for example a shared forms or email service) used by every environment. Do not recommend per-environment secrets as part of maintenance mode.

### What tested means
- **Application dependencies** (package manifests, lockfiles, base images): a required check builds that component and runs its tests on the PR.
- **GitHub Actions workflow updates** (`uses:` bumps in `.github/workflows/`): a required check runs `actionlint` (or equivalent) on the PR, and the updated workflow itself actually runs on the PR and is gated by a required results check. Workflows that only run after merge (deploy, release, schedule) are covered by `actionlint` plus Tier-1 item 4: watch the next run on the default branch.
- **Code nothing runs any more** (dead apps, scripts, old directories): the default is to add tests. Excluding it from Renovate with `ignorePaths` is a weakening override and needs the user's approval: ask the user in chat; record the answer in the issue. Deleting it is a separate code change; ask the user in chat too.

## Pre-flight Checklist (CRITICAL)

Run every item. Write nothing to the repository while doing so.

1. **Maturity audit.** Run the `github-repo-setup` audit ([`bcgov/agent-marketplace` `skills/community/github-repo-setup`](https://github.com/bcgov/agent-marketplace/blob/main/skills/community/github-repo-setup/SKILL.md)) against the current default branch. That skill writes `MATURITY_REPORT.md` into the root of the repo it audits, so run it only against a throwaway copy outside the working checkout (for example a fresh clone in a scratch directory), never the real checkout. Map its findings onto the Tier-1 list above. Do not depend on the copy in `bcgov/agent-skills`; that repo is being archived.
2. **Test suite exists and runs in CI** (`.github/workflows/` jobs that execute the tests, not just scripts on disk).
3. **Required checks cover everything Renovate updates.** It is not enough that some required checks exist.
   - List what Renovate updates: run through `renovate.json`'s managers and recent Renovate PRs (`gh pr list --author app/renovate --state all --limit 20 --json number,files`).
   - For each manifest or path, name the required check that builds and tests it. Anything without one is Tier-1 item 1.
   - On recent Renovate PRs, every required check completed `success` after its tests actually ran.
   - Recommended pattern, from `bcgov/quickstart-openshift`: each workflow ends with a distinctly named results job (for example `PR Results`, `Analysis Results`) that `needs:` every other job in that workflow, runs with `if: always()`, and fails when any needed job's result is `failure` or `cancelled`, or `skipped` when that job was not expected to skip. The ruleset then requires those results checks, one per workflow. A results job only gates the jobs listed in its `needs:`, so every new job must be added there; check that no job is missing. Test steps must fail normally: a step with `continue-on-error: true` leaves its job `success` even when tests fail, so the results job cannot see it. If the repo lacks this, propose it as a code PR (a human still adds the checks to the ruleset).
4. **renovate-approve can approve Renovate PRs.** Fixed policy, everywhere: the [`renovate-approve`](https://github.com/apps/renovate-approve) GitHub App's approval is the required review for Renovate PRs (ADR-020, "Maintenance-Mode Review, Secrets and CHEFS", in `DerekRoberts/brain`). Do not reopen that policy decision. Check, mechanically with `gh`, that it works on this repo now:
   - **Current access.** renovate-approve only approves Renovate PRs whose body contains `**Automerge**: Enabled`; those are the eligible PRs. List the eligible ones from the last 7 days and whether each has a `renovate-approve[bot]` review: `gh pr list --repo {owner}/{repo} --author app/renovate --state all --search "created:>=$(date -d '7 days ago' +%F)" --json number,body,reviews --jq '.[] | select(.body | contains("**Automerge**: Enabled")) | {number, approved: ([.reviews[].author.login] | index("renovate-approve") != null)}'`. `gh api repos/{owner}/{repo}/installation` needs an app token and fails with a user token.
     - **Eligible PRs exist, none has the review:** access is missing. Settings step: install the app (Workflow step 1, item 3).
     - **No eligible PR in the last 7 days:** the PRs can't tell. If the login is an org owner, read `gh api orgs/{owner}/installations` (app `renovate-approve`, its `repository_selection`; for `selected`, the repo must be in that installation's repository list). Otherwise check the latest eligible Renovate PR of any age (same command without `--search`). If that still can't tell, list it as a settings step: confirm or install the app (Workflow step 1, item 3).
   - **Active review rules.** Read the rules on the branch Renovate targets: `gh api repos/{owner}/{repo}/rules/branches/{branch} --jq '.[] | select(.type == "pull_request") | .parameters'`, plus `gh api repos/{owner}/{repo}/branches/{branch}/protection` for classic protection. An app approval cannot satisfy `require_code_owner_review` on files CODEOWNERS covers, since CODEOWNERS lists only users and teams. With `require_last_push_approval`, the `renovate-approve[bot]` review must come after the PR's last commit.
   - Every finding above is a settings step for the user, with evidence; a blocking review rule is a step naming that ruleset and rule. None is a question. Never suggest disabling required reviews.
5. **Release pipeline health.** Find the merge/release workflow(s) on the default branch (`gh run list --branch <default> --workflow <file> --limit 10`). The latest completed run must have succeeded, and there must be a success within about the last month. Otherwise it is Tier-1 item 4.
6. **Local Renovate overrides.** Read `renovate.json` / `renovate.json5` (and `package.json` `renovate` blocks). Flag any local setting that weakens the preset, such as `minimumReleaseAge: "0 days"`, `ignorePaths` / `ignoreDeps` that hide code from updates, `ignoreTests: true`, or disabled vulnerability alerts. Each must be removed in the follow-up PR unless the user approves keeping it: ask the user in chat; record the answer in the issue.
7. **End-of-life check.** List every runtime and image version the repo uses, including ones Renovate doesn't manage:
   - Images: `git grep -n -I -E '^\s*FROM |image:|repository:|tag:' -- '*Dockerfile*' '*Containerfile*' '*compose*.y*ml' '*.y*ml' '*.json'`. That covers Dockerfiles, compose files, OpenShift templates, Helm values and workflow `services:`. A Helm value split into `repository` and `tag` is one image. Follow a `${PARAM}` or `${{ inputs.x }}` reference to the template parameter, workflow input or caller that sets it.
   - Runtimes: `engines` in `package.json`, `.nvmrc`, `.node-version`, `.tool-versions`, `node-version` / `java-version` in workflows, `<java.version>` / `maven.compiler.release` in `pom.xml`, `toolchain` / `jvmToolchain` in Gradle files.
   - For each product and major (or cycle), read `curl -s https://endoflife.date/api/v1/products/<product>/releases/<cycle> | jq '.result | {isEol, eolFrom}'`, for example `postgresql/releases/12` or `nodejs/releases/22`. `isEol: true` is Tier-1 item 7. For a base image, check both the runtime and the OS release (for example `debian/releases/12`). A product endoflife.date doesn't list, or an image tag with no version (such as `latest`), goes in the report with its file and line as unknown.
   - **PostgreSQL and PostGIS behind quickstart.** Read quickstart's current major from `bcgov/quickstart-openshift`'s default branch each run; never use a number from this skill or from memory. Its PostgreSQL tag is the `PG_VERSION` parameter's `value:` in `common/openshift.database.yml` (`gh api repos/bcgov/quickstart-openshift/contents/common/openshift.database.yml --jq .content | base64 -d`), and its PostGIS image is the `postgis/postgis:<pg>-<postgis>` tag there or in its `docker-compose.yml`, if it has one. The PostgreSQL major is the part of the tag before the first `-` or `.`. Any PostgreSQL major in the repo below quickstart's, or any PostGIS image whose PostgreSQL major or PostGIS version is below quickstart's PostGIS tag, is a finding under Tier-1 item 7, even when it isn't end-of-life yet. Each finding gets its own not-safe upgrade PR to quickstart's version, with the data migration (`pg_upgrade` or dump/restore).

- **IF ANY TIER-1 BLOCKER MATCHES**: **HARD-STOP**. Change nothing. Report each blocker with evidence, the code PRs that would fix it, and click-by-click settings steps for the human.
- **IF ALL ITEMS PASS**: Proceed with the steps below.

## Workflow

### 1. Repository Settings (human steps)
You do not change settings. Read the current values and give the human only the steps still needed, for example:

1. Settings → General → Pull Requests → tick **Allow auto-merge**. (Check with `gh api repos/{owner}/{repo} --jq .allow_auto_merge`.)
2. Settings → Rules → Rulesets → *(ruleset for the default branch)* → **Require status checks to pass** → add each workflow's results check.
3. If pre-flight item 4 found `renovate-approve` without current access, get the [`renovate-approve`](https://github.com/apps/renovate-approve) app installed on the repository. Installing an app on an org repo needs an org owner: open the app page → **Configure** → choose the org → **Only select repositories** → add the repo, which submits a request for owners to approve if you are not one; or ask an org owner to add it. Do not loosen reviews for anyone else.

### 2. Renovate Configuration
Modify or create `renovate.json` (or `renovate.json5`) at the repository root.
- Resolve the latest stable three-segment release and inherit from it, for example: `"extends": ["github>bcgov/renovate-config#<YYYY.M.Patch>"]` (current releases look like `2026.9.26`). Do not use the unversioned `main` preset for production (`github>bcgov/renovate-config` with no ref, or `#main`). The preset README marks that as testing-only and warns it may contain breaking changes.
- Renovate can still propose pin updates. Leave the pin where its pin manager can see it. Do not add a local rule that freezes the preset forever.
- Know what the preset auto-merges before relying on it. As of release `2026.9.26`, its `default.json` sets `automerge: true` for **every** update type, majors included, after a 7-day `minimumReleaseAge` (3 days for vulnerability fixes). Major updates to database images (postgres, mysql, mariadb, mongo, redis) are disabled, so no PR opens for them, and package-manager overrides/resolutions are only bumped for security advisories. Re-read the pinned release's `default.json` each run, since this can change. That is why required checks must cover everything Renovate touches.
- Do not add custom local auto-merge rules.
- Remove the weakening overrides flagged in pre-flight item 6 unless the user approved keeping them (asked in chat, answer recorded in the issue).
- If the repo already pins the latest release and has no weakening overrides, make no Renovate change.

### 3. CI/CD Deployment Pipeline
Analyze `.github/workflows/` and bring the deploy path to one of the target patterns. Do not assume TEST deploys on `push` to `main`; find the real trigger.

- **Triggers.** TEST may deploy on `push` to `main`, or from a `workflow_run` that follows the `main` build. For `workflow_run`, the deploy must check `github.event.workflow_run.conclusion == 'success'`, `head_branch == 'main'`, and `event == 'push'`, and deploy the artifact built for `github.event.workflow_run.head_sha`, not whatever is newest.
- **Path filters.** Do not put `paths` / `paths-ignore` on the merge or PR workflow trigger to skip work. Put path conditions on jobs, so the workflow always runs and its results check always reports.
- **Same artifact means same digest.** Promotion must deploy the image digest that passed CI and TEST. Retagging a mutable tag (such as `latest` or `test` → `prod`) counts only if the workflow resolves and verifies the digest it is promoting. Prefer promoting by digest, for example recording and looking up digests with [`bcgov/actions` `image-tracker`](https://github.com/bcgov/actions/tree/main/image-tracker). A retag without digest verification is a finding to fix, not a pass.
- **PROD approval.** A required reviewer on the PROD environment is acceptable and should be kept if the team wants it. "Automatic" below means PROD needs no extra build or manual trigger, not that it skips an approval gate.
- **`workflow_dispatch` that can deploy PROD.** It may stay only if it can deploy nothing but a digest that already passed TEST (it looks up and verifies that digest; it never builds). Otherwise flag it and replace it with one of the target patterns.
- **Target Pattern 1: Release-Gated**:
  - `TEST` deploys automatically from `main` (push or `workflow_run`) and records the tested digest.
  - `PROD` deploys when a GitHub Release is published (`on: release: types: [published]`), only after verifying that its tag targets a commit on `main`; promote the same digest that passed CI and `TEST`.
  - A published release can point at an arbitrary tag or commit, so the release event alone is not enough. If the tag SHA is not on `main`, or the workflow rebuilds or cannot verify the digest, do not deploy PROD.
- **Target Pattern 2: Straight-to-TEST+PROD**:
  - `TEST` and `PROD` deploy sequentially from `main`, promoting the same digest from the pipeline that passed CI, with an optional PROD approval gate. PROD follows TEST for that digest; it does not build a second one.

If the existing pipeline already meets a target pattern, leave it alone and say so.

### 4. Stuck Renovate PRs
Renovate PRs can sit open because a required check was cancelled (for example by a concurrency group) and never reported success. Do not re-run them while the gates are fake or incomplete, or they will auto-merge untested changes. Act only after the real gates (results checks that cover every Renovate path) are merged and required in the ruleset. Then get a fresh run: have Renovate rebase the PR (its rebase checkbox) so the PR picks up the new workflows. A plain re-run reuses the original commit and workflow files, so only re-run when that commit already contains the final gates.

## Tracking Issue
Some repos carry an older maintenance-mode checklist issue. Where it conflicts with this skill, this skill wins. In particular, ignore any item asking for `paths-ignore` filters on the merge workflow: use job-level path conditions instead (see Path filters above). A suitable checklist for the issue is:

- [ ] Pre-flight passed (no Tier-1 blockers), report linked or summarized here
- [ ] Required results checks cover every path Renovate updates
- [ ] `renovate-approve` installed on the repo
- [ ] `bcgov/renovate-config` pinned to a release; weakening overrides removed, or kept with the user's answer recorded here
- [ ] Release pipeline green on the default branch
- [ ] No end-of-life runtimes, database majors or base images; PostgreSQL/PostGIS at quickstart-openshift's current major
- [ ] PROD promotes the tested digest (PROD approval gate optional)

## Rules
- **Hands off settings**: Never change repository settings, rulesets, environments, secrets, or app installs. Give the human steps.
- **Nothing written before pre-flight passes**: No branches, commits, or report files in the repo until every pre-flight item passes.
- **Pin `bcgov/renovate-config`**: Do not write verbose custom Renovate rules locally when the central preset applies, and do not float the preset on `main`.
- **Same digest to PROD**: PROD never deploys a digest that did not pass CI and TEST, and never a release tag whose SHA is off `main`.
- **Checks must actually run and cover what Renovate changes**: A test suite on disk, a skipped required check, a results job with `needs: []`, or a required check that ignores a Renovate-updated path is not a pass.
- **No end-of-life components**: An EOL runtime, database major or base image, or a PostgreSQL/PostGIS major behind quickstart-openshift's current one (read from its default branch), blocks maintenance mode until an upgrade PR (its own PR, versions from `bcgov/quickstart-openshift`) merges.
- **Shared secrets are fine**: Do not flag or fix secrets shared across environments as part of maintenance mode.
- **renovate-approve is settled**: Its approval is the required review for Renovate PRs (ADR-020). Never write a "does renovate-approve count" question or decision line into issues or PRs.
- **Decisions go to chat**: Never post decisions the user has to make in issues or PRs (bodies, checklists, "Decisions needed" or sign-off items, review threads). Ask the user in chat; record the answer in the issue. Issues and PRs may state decisions already made, as plain facts, and concrete steps the user has already agreed to.

## Examples
- The user asks: "Enable maintenance mode for this repo". You run the pre-flight without writing to the repo. All items pass, so you open a PR that pins the preset and fixes the deploy path, and list the settings steps for the human.
- First real run (2026-10-08): the repo's Renovate config updated a data crawler and utility scripts that no required check tested, and the only required test gate was a small end-to-end suite. Tier-1 item 1 matched, so the skill stopped, changed nothing, and proposed a code PR adding results-gated tests.

## Edge Cases
- **Monorepos**: map each Renovate-updated directory to a required check; one green check for one app does not cover the others.
- **Path-filtered workflows**: an event-level `paths` / `paths-ignore` filter means the workflow never starts, so its required results check never reports and the PR waits forever. Required workflows must trigger on every PR and apply path conditions at the job level, with the results job treating those skips as expected.

## References
- `bcgov/quickstart-openshift` workflows: results-job pattern (`PR Results`, `Analysis Results`).
- `bcgov/actions` `image-tracker`: digest lookup for promotion.
- `bcgov/renovate-config` releases (three-segment `YYYY.M.Patch` tags only; not `main`) and their `default.json`.
- `github-repo-setup` maturity audit: [bcgov/agent-marketplace](https://github.com/bcgov/agent-marketplace/blob/main/skills/community/github-repo-setup/SKILL.md). Evidence only; Tier-1 is defined in this skill.
