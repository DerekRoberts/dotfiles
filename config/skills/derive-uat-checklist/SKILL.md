---
name: derive-uat-checklist
description: 'Draft, in development. Turns an app''s README, training courses and videos into a QA/UAT checklist under docs/uat/. Not ready to ship. Use when the user asks for a UAT or QA checklist from training material.'
---

> **Draft, in development.** This skill is still being worked out. This file lives in `DerekRoberts/dotfiles` at `config/skills/derive-uat-checklist/`. `scripts/setup/ai.sh` copies every directory under `config/skills/` into `~/.agents/skills/`, which is what Derek's tools load. Do not copy this into a template or its `AGENTS.md` until it settles.

# Derive UAT Checklist

Build a short, role-grouped manual QA/UAT checklist from the app's docs and training, then open it as a PR.

## Use When
- The user asks for a UAT or QA checklist from a README, training course, or how-to videos.
- An app needs a reusable `docs/uat/` checklist after a platform or security release.

## Don't Use When
- The user only wants automated tests (Playwright, Jest, k6).
- There is no README or training material to ground the checks.

## Ground Rules
- Keep the checklist short and generic; prefer tables (`# | Step | Expected | If it fails`).
- Group checks by user role: public (anon), licensee/holder, ministry reviewer.
- Flag every step that needs a human login. The user signs in through a screen handoff and never shares credentials.
- **PROD is read-only.** Never include write steps (create, edit, comment, upload, toggle) against PROD.
- Output via a PR to the app repo: `docs/uat/checklist.md` plus any small test fixtures under `docs/uat/`.

## Workflow

### 1. Gather sources
- README and any linked runbooks.
- Training courses and videos. Articulate Rise course data is base64 JSON in `locales/und.js` (decode, then extract text).
- Any existing checklist in the repo or issue tracker.

### 2. Watch the videos
Have the videos watched and turned into notes (titles, roles, click paths, expected outcomes). Prefer notes over paraphrasing from memory.

### 3. Derive checks
From the notes and docs, write checks grouped by role. Cover happy paths and the failure modes the training calls out. Reuse the app's real URLs, labels and error strings when known.

### 4. Mark human-login steps
Tag IDIR, BCeID or other SSO steps clearly. Stop for a screen handoff; never ask for or store credentials.

### 5. Ship as a PR
Open a small PR off the app's default branch with `docs/uat/checklist.md` and any fixtures (for example a sample GeoJSON/JSON upload). Point `AGENTS.md` at `docs/uat/` with one tool-neutral line when that file already exists. Iterate until CI is green; leave merge to the user.

## Worked example
[bcgov/nr-fom#1194](https://github.com/bcgov/nr-fom/pull/1194) — FOM TEST checklist from the README, Ministry Reviewers Articulate course, and public/holder how-to videos; fixtures under `docs/uat/`.
