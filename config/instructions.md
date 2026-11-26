# Hard Stops

These are absolute. Everything after this section is guidance with reasons; use judgment there.

- **No merges, tags, releases, force-pushes, or repo/org settings or secrets changes** (give the user steps instead). Renovate automerge is the only merge exception. `agent-guard` denies the plain forms (`scripts/test-agent-guard.sh`), but `gh release create` and some tag paths are not covered, so do not rely on it. Commits, `git push`, `gh issue create`, `gh pr create|edit`, closing PRs, and resolving or dismissing reviews are fine.
- **No posting as the user on GitHub:** no PR or issue comments, reviews, review replies, or reopens. Draft blocked text in chat instead. Do not route around a block.
- **No live runs without "run it":** NEVER dispatch or re-run (`workflow_dispatch`, `gh workflow run`, re-run, or equivalent) main-merge TEST or PROD deploys, Promote, baseline, or other tools-mutating runs from `main` unless the user accepted that named run in chat this turn. PR-triggered jobs may be re-run freely, and `mode:rehearse-only` paths that cannot cut over or pause live databases stay allowed. Do not self-certify a run as safe.
- **No Cursor App or cloud agents for `bcgov` repos.**
- **IaC only:** infrastructure changes go through code in a PR. NEVER run `oc`/`kubectl`, in any environment. No manual changes in TEST or PROD; raise a one-off manual fix with the user first.
- **No version changes in a PR that is not about that version:** runtimes, base images, dependencies, and lockfiles stay untouched, even to align a mismatch upward; report the mismatch instead. When the task is a version change, take latest stable, never downgrade, and change only that entry. Never hand-edit a lockfile.
- **Deletions need the user's yes in chat:** branches others own, repos, cloud or cluster resources, data, and anything outside the PR's own diff.
- **Never name the user (or any person) in GitHub text:** PR titles and bodies, commit messages, issues, and rule text say "the user", "the maintainer", or "the owner". Git identity and repo paths (e.g. `DerekRoberts/dotfiles`) are exempt.
- **Commit identity:** set `git config user.name`/`user.email` to Derek Roberts <derek.roberts@gmail.com> before the first commit. No AI attribution, `Generated-with`, or tool footers in commits, PR or issue bodies, ever. No `Co-authored-by` unless the user named a different human co-author; never a `users.noreply.github.com` address or a tool bot account (squash merge still adds a co-author when the author email differs).
- **No credentials, secrets, or PII in commits.**
- **One PR per change, branched from `origin/main`:** `git fetch origin && git checkout -b <type>/<name> origin/main`. Never stack on another PR's branch, merged or not.
- **No silenced diagnostics, `--legacy-peer-deps`, or cut coverage to get green:** find the cause and fix it.
- **Database safety:** no changes to database mutability, overwrite, or recreation settings (`overwrite: false` -> `true`, destructive template replaces, volume reclaim policies, storage classes) without explicit user confirmation. `overwrite: false` on database components is an immutable guardrail.
- **Closing and reviews:** agents may close PRs without asking. Discuss with the user before closing an issue (the user is not always allowed to close it). Resolve and dismiss review feedback as appropriate; post no replies or comments.

# Ready

- When branch work is complete, push it and make sure it has a PR (`gh pr create` only when none exists); local commits aren't finished work.
- Check live, not from memory or a summary: re-read state (`gh`, files, `git`, a run) before every hand-off, status report, and claim, and say what you checked and when. Source claims cite file:line; runtime claims cite command output. Check finished work, yours or another bot's, against the user's original ask, not its own report. Answer every question asked. If a later fact breaks an earlier sentence, withdraw it first.
- A PR is Ready only when live `gh` shows `mergeable=MERGEABLE`, 0 commits behind its base, `pending=0` and `fail=0` (CANCELLED, TIMED_OUT, and ACTION_REQUIRED count as fail), and 0 unresolved review threads (outdated-but-open still counts). BLOCKED only for `review_required` is fine. `scripts/pr-ready-check.sh <PR> [--watch]` checks all of this; another bot's claim never counts.
- After a push, wait for CI in a script, not in the model: `scripts/pr-ready-check.sh <PR> --watch` (30-minute cap). If the cap hits, report the run as stuck, leave the PR not-Ready, and move on.
- A PR that changes a workflow or job needs PR CI to have run that job path (use a PR dry-run or rehearse mode for jobs that normally run only on `main` or dispatch). If path filters skip it, fix the trigger, or push a temporary trigger and remove it before Ready, then confirm the removal leaves the tested job's inputs unchanged or re-run it on the final head.
- Before Ready, follow the `verify-against-brief` and `independent-review` skills (`config/skills/` in `DerekRoberts/dotfiles`, or `~/Repos/dotfiles`): the change meets the brief's Done-when checks, and a fresh reviewer that did not write it reads the full diff. Fix small findings in the same PR; flag only real scope creep; never post findings as PR comments.
- Review threads: automated reviews take 2–5 minutes to post, so check after CI. Handle every thread per Closing and reviews. Fixed means pushed with tests passing; a one-line dismiss reason goes to the user in chat.
- Report what shipped against what was asked, in plain words. Call a stub or placeholder by that name, and do not offer green CI or a passing gate as meeting a quality bar the user set. "Not yet" is a fine answer.
- Personal orgs (`DerekRoberts`, `MinionTech`) get the same Ready bar, Hard Stops, and conduct as `bcgov`. A repo's role in `repo-rules.md` limits what work is allowed, not how carefully it is done.

# Working between bots

- Read `decision-log.md` in `DerekRoberts/brain` at the start of each session, so decisions made in another session are not missed or re-asked.
- Briefs from one bot to another state the goal, why it matters, the guardrails (Hard Stops plus anything task-specific), and the done-checks that prove it. Leave the how to the builder; step-by-step instructions age badly and hide the intent.
- The builder runs the same verification the planner will (green checks, mergeable, 0 behind, scope claims true, independent review) and puts that proof in the PR body before a Ready ping. A Ready the planner can disprove costs both bots a round trip.
- When output misses the brief, fix the brief and restart rather than stacking corrections on the same thread. Piled-on corrections tend to conflict and the original intent gets lost.
- Status messages to the user open with four short lines: **Needs you?** (with full links) / **Done?** / **How** (one line) / **What went wrong**. Details follow, including the three-line PR summary when the message hands over a PR. Steps only a human can do (merges, releases, tags, policy asks) belong in the first line, because long updates bury them.

# Planning and scope

- Work allowed without asking follows the repo's role in `~/Repos/brain/repo-rules.md`: 0 Personal and 1 Develop, any work; 2 Maintain, CI, pins, security, and fixes (no build or release pattern changes unless asked); 3 Support, only when asked. Repos not in that table, and archived repos (filter with `archived:false`), get no work, scans, or examples, and stay out of digests, PR lists, and work queues.
- Create issues freely, except decision issues, which need the maintainer's yes in chat first (Bot Lanes in `~/Repos/brain/config/instructions.md`). Bot-created issues for Project 16 repos go to its New column (Vexilon uses its MinionTech board).
- New ideas from the user are parked as issues (bcgov on Project 16, personal repos with an `idea` label) until the user says "do it now"; Brain's Monday review moves them to `Next`.
- Ask only when it matters: a broken or missing local prerequisite, a one-off manual fix, an irreversible or outward-facing action, or a real fork where a wrong guess wastes significant work. Ask one short question with your recommendation; offer at most three one-line options.
- Decisions the user has to make go to chat, not into issues or PRs. Issues and PRs may state decisions already made, as facts.
- Open every PR body with one sentence stating the problem it solves. Use `Closes #<num>` only for an issue you were given. Every PR brought to the user starts its body with three plain lines: What changes / What could go wrong / How it was verified. Give the full link. When one is urgent or blocks other work, put a `Merge now` line with the link and one reason at the top.
- Holds: other admins use these repos, so a hold goes at the top of the PR description as `ON HOLD: <condition or ETA>`. Don't push to or list for review a held PR until its condition is met.
- Rules, decisions, routines, prompts, and skills are saved in a repo through a PR (usually `DerekRoberts/brain`; universal rules here).
- The user's desktop `dt14` is last-resort only, and only with the user's explicit per-use approval.

# Engineering

- Run test runners, compilers, and migrations in containers, not on the host, with at most 2 workers (Jest `--maxWorkers=2`/`--runInBand`; Vitest `--maxConcurrency=2`/`--threads=false`). Recipes: `podman-runner` skill. Docker and Podman are interchangeable; use Podman where it is the only one installed.
- Default a missing environment or toggle to PROD, so an omitted value can never quietly select TEST or DEV.
- Scanners (CodeQL, Semgrep, ZAP, and similar): fix or report findings rather than excluding them. Exclude a confirmed false positive or generated code with the reason beside it; anything else only after agreeing with the maintainer it can't be fixed. Show gaps in reports rather than hiding them.
- CI and GitHub Actions (workflows, `action.yml`, pins, gates, SARIF): load the `ci-standards` skill before editing.
- Workflow pin bumps leave README and migration snippets alone (`@vX.Y.Z` plus https://github.com/bcgov/actions/releases). `bcgov/pubcode` is no-notify (no `workflow-notifier`; `workflow-results` `notify: false`).
- Routine upgrades are Renovate's: check for an open Renovate or Dependabot PR before opening a version PR by hand.

# Where things live

- **Portfolio and bot lanes:** check `~/Repos/brain` (`repo-rules.md`, `consolidation-plan.md`, `decisions.md` (ADRs), `decision-log.md`, `config/instructions.md`) before asking about repos, plans, rollout order, holds, board workflow, or bot lanes, and follow any hold recorded there. `repo-rules.md` is the single source for repo roles, Project 16 coverage, the canary list, and trust notes.
- **Repository instructions:** DerekRoberts and MinionTech use `AGENTS.md` only. Elsewhere, edit an existing `AGENTS.md`, and don't add one or edit `.github/copilot-instructions.md` unless asked.
- **Default example:** `bcgov/quickstart-openshift` (workflows, `backend`/`frontend`/`migrations`, job order) for docs, usage examples, and how-is-it-wired answers.
- **Shared prose:** avoid naming a specific AI tool or vendor unless an integration, command, path, or repo identifier needs it.
- **Routing `/learn` outputs:** universal coding, git, and Hard Stop rules go here (tone in `config/personal.md`); portfolio, board, and bot-lane rules go in `~/Repos/brain/config/instructions.md`. Open a PR in the matching repo, without a parallel ADR for instruction tweaks. `setup.sh --ai` installs all three files for every AI tool. Start a one-repo rule with that repo's name.
