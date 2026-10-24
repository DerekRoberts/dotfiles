---
name: ci-standards
description: 'CI and GitHub Actions authoring rules: SHA pins, minimum permissions, secret mapping for reusable workflows, diff-triggers gating, results gate names and SARIF uploads. Use before creating or editing GitHub Actions workflows, action.yml files, action pins, required checks or code-scanning uploads.'
---

> This file lives in `DerekRoberts/dotfiles` at `config/skills/ci-standards/`. `scripts/setup/ai.sh` copies every directory under `config/skills/` into `~/.agents/skills/`. Moved out of the always-loaded `config/instructions.md` (Project Standards), which points here.

# CI Standards

- ALWAYS use minimum permissions (e.g., `permissions: {}` in GitHub Actions).
- ALWAYS use the most recent releases of GitHub Actions and pin to full 40-character commit SHAs with a trailing tag comment; NEVER pin `@main`, NEVER use floating tags, and NEVER guess action versions or runner labels from memory (query live releases via `gh api` or inspect `quickstart-openshift` first). This applies across all action organizations: official platform actions (`actions/*`, `github/*`, `docker/*`), ministry actions (`bcgov/*`), and third parties (`astral-sh/*`, `grafana/*`, etc.). Examples:
  - `uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`
  - `uses: bcgov/actions/workflow-results@79aefe3a7abb2d0d00b1b3ea4cfbf12727a10638 # v0.9.0`
  - `uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4.4.1`
  - `uses: github/codeql-action/init@48ab28a6f5dbc2a99bf1e0131198dd8f1df78169 # v3.28.0`
- ALWAYS pin runner environments to explicit supported LTS versions (e.g., `runs-on: ubuntu-24.04`) or `ubuntu-slim`; NEVER use floating runner tags like `ubuntu-latest`.
- Reusable workflows: ALWAYS explicitly map secrets on caller jobs (`secrets: { key: ${{ secrets.KEY }} }`) alongside `with: environment: <env>`. NEVER use `secrets: inherit` unless explicitly requested.
- PR workflows must NOT fire unnecessarily: gate heavy jobs (matrices, deploys, container tests) with the established `bcgov/actions/diff-triggers` or path-skip pattern. Docs/Markdown-only changes NEVER trigger heavy jobs. Path filters list only the files a job actually depends on, NEVER a whole action folder that includes READMEs. Skipped jobs still report through `bcgov/actions/workflow-results` with their gate job names and no `title`, so required checks stay stable.
- Results gate job names are required check names: NEVER rename an existing gate or results job, even when it doesn't match the standard. Use the standard names (`PR Results`, `Validate Results`, `Analysis Results`, or `<Title Case Name> Results`) only for new gates in workflows that have none.
- SARIF uploads: Third-party security scans (e.g. Trivy) uploading SARIF to GitHub Code Scanning on `pull_request` must explicitly set `ref: refs/pull/${{ github.event.pull_request.number }}/head` and `sha: ${{ github.event.pull_request.head.sha }}`, and the scan job's existing `actions/checkout` step must set `ref: ${{ github.event.pull_request.head.sha || '' }}` so the scanned code matches the attributed sha (push and schedule runs unchanged; never add a second checkout step). Splitting PR uploads from default branch pushes prevents ephemeral merge ref recalculations from orphaning scan results and locking branch rulesets.
- PR validation and workflow linting: Use `.github/workflows/pr-validate.yml` calling `bcgov/actions/pr-validate` (which validates Conventional Commits PR titles and runs `actionlint` + `shellcheck`), gated by `Validate Results` (`bcgov/actions/workflow-results`). NEVER add or keep a standalone `actionlint.yml` workflow.
- Failure notifications (`bcgov/actions/workflow-notifier`): Add only to non-PR orchestrator or scheduled workflows (e.g., `merge.yml`, `release.yml`, `scheduled.yml`); NEVER notify on `pull_request` workflows. `workflow-notifier` resolves actors via the GitHub API and runs without `actions/checkout` unless `CODEOWNERS` fallback from the workspace is explicitly required.
