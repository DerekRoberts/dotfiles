---
name: derive-uat-checklist
description: 'Turns an app''s README, training material and videos into a risk-ordered UAT checklist, a plain-language PO/end-user test plan, and automated tests that approximate the manual checks. Use when the user asks for a UAT or QA checklist, a test plan for a product owner, or tests derived from training material.'
---

> This file lives in `DerekRoberts/dotfiles` at `config/skills/derive-uat-checklist/`. `scripts/setup/ai.sh` copies every directory under `config/skills/` into `~/.agents/skills/`.

# Derive UAT Checklist

Turn an app's docs and training into three things, shipped as PRs to the app repo:
1. A risk-ordered UAT checklist (`docs/uat/checklist.md`).
2. A plain-language test plan for the product owner and end users (`docs/uat/po-test-plan.md`).
3. Automated tests that approximate the manual checks (API tests, plus browser e2e where a session matters).

## Use When
- The user asks for a UAT or QA checklist, or a PO test plan, from a README, training course or videos.
- An app is about to go to UAT or into maintenance mode and needs repeatable checks.

## Don't Use When
- There is no README or training material to ground the checks.

## Ground Rules
- **TEST only.** Never run checks, write data or point tests at PROD.
- **No credentials, ever.** A step that needs a human login (IDIR, BCeID, other SSO) is a sign-in handoff: the person signs in on screen. Automated tests use fake sessions, never real accounts or secrets.
- **Check the role first.** Before treating a permission result (403, hidden button, "Forbidden") as a bug, confirm which role the signed-in user has (for example FAM admin vs reviewer). Mark checks that need a specific role.
- **Verify against the code.** Before calling something a bug, confirm the behaviour in the API and UI code. Old checklists and training notes can be stale or wrong. If code and docs disagree and the behaviour is reasonable, write a neutral issue for the PO instead of a fix.
- **Restore test data.** Anything a check creates or changes in TEST is put back afterwards, or the plan says how.
- Keep each document short; prefer tables (`# | Step | Expected | If it fails`).

## Workflow

### 1. Gather sources
- README, runbooks, and any existing checklist in the repo or issue tracker.
- Training courses and videos. Articulate Rise course data is base64 JSON in `locales/und.js` (decode, then extract text). Turn videos into notes: roles, click paths, expected results.

### 2. Write the UAT checklist
- Group checks by role (for example public, holder, reviewer, admin).
- Order by risk: sign-in and permissions, data that is published or emailed, irreversible steps (finalize, delete), then everyday paths.
- Use the app's real URLs, labels and error strings. Tag each human-login and role-specific step.
- Add small fixtures under `docs/uat/` (for example a sample upload file).

### 3. Write the PO/end-user test plan
- Plain language, no jargon: what to open, what to click, what they should see, what to report.
- One section per role; say which account type each section needs.
- Note any checks that need a role the tester may not have.

### 4. Approximate the checks with automated tests
- **API tests** for each checklist rule: who can do what, state changes, notifications. Use the repo's existing test framework and fixtures; mark a test as an expected failure only for a confirmed bug with a linked issue.
- **Browser e2e with a fake session** (for example Playwright):
  - Seed the tokens the app reads (localStorage or storage state) with structurally valid, unexpired fake JWTs.
  - Mock the identity provider (token refresh, user info) and the API calls the page needs with `page.route`.
  - Open a protected page, hard reload, and assert the user stays signed in (no redirect through logout or the hosted sign-in page, user name still shown).
  - Negative case: an expired token whose refresh fails sends the user to sign-in.
  - Must run in the existing CI job without secrets.
- No app behaviour or version changes in a test PR.

### 5. Ship
- Small PRs off the default branch; drafts until CI is green. Point an existing `AGENTS.md` at `docs/uat/` with one line.
- Leave merging to the user.

## Worked examples
- [bcgov/nr-fom#1194](https://github.com/bcgov/nr-fom/pull/1194): UAT checklist from the README, reviewer course and how-to videos.
- [bcgov/nr-fom#1210](https://github.com/bcgov/nr-fom/pull/1210): PO test plan and API approximation tests.
- [bcgov/nr-fom#1206](https://github.com/bcgov/nr-fom/issues/1206): Playwright fake-session e2e with reload and expired-token cases.
