# Agent Guardrails & Safety

AI-assisted development accelerates velocity, but autonomous coding agents require strict guardrails to protect shared environments, preserve git history integrity, and maintain compliance.

This repository establishes a client-side safety net and policy framework that enforces a **human-in-the-loop** workflow across all AI tooling (Cursor, Antigravity, and CLI agents).

---

## Core Philosophy

### Safety Belt, Not a Sandbox
Guardrails in this repository serve as a safety belt to prevent well-intentioned tools from making automated mistakes. They do not constitute an adversarial security sandbox. Bad-faith agents can override local configurations; genuine security boundaries must be enforced at the platform level (e.g., GitHub branch protection rules, least-privilege cloud IAM, and CI/CD pipelines).

### Human-in-the-Loop Lifecycle
Autonomous agents excel at writing code, generating tests, and drafting pull requests. However, **humans retain sole ownership of critical lifecycle events**:
* Deploying to or inspecting live infrastructure (`oc`, `kubectl`).
* Merging pull requests, closing issues, and managing releases or tags.
* Posting reviews or comments under human credentials (preventing impersonation).
* Modifying security configurations, repository secrets, or database destruction toggles.

### Soft Policy vs. Hard Checks
* **Soft Policy (Behavioral Guidelines)**: Structured behavioral constraints, communication standards, and planning expectations live in [`config/instructions.md`](file:///var/home/derek/Repos/dotfiles/config/instructions.md) and deploy directly to agent prompts (e.g., Cursor, Antigravity).
* **Hard Checks (Hooks & Guardians)**: Automated verification runs locally via global Git hooks (`~/.githooks/pre-commit`) to block secret leakage and version regressions before commits are recorded.

---

## Allowed vs. Blocked Matrix

### What Is Allowed (Agents)

| Tool / Domain | Permitted Actions | Rationale & Context |
| :--- | :--- | :--- |
| **`git`** | `commit`, `push` (non-force), branch creation, `fetch`, `merge origin/main` | Standard feature branch development. |
| **`gh`** | `pr create`, `pr edit`, `pr view`, `pr diff`, read-only `api GET` | Opening and updating pull requests, inspecting review feedback. |
| **Package Managers** (`npm`, `uv`, `pip`, etc.) | Standard package install, build, test, and typecheck commands | Regular dependency resolution without peer dependency bypasses. |
| **Diagnostics & Tests** | Running test suites, linters (`shellcheck`, `actionlint`, `eslint`), and build checks | Verifying code quality and runtime correctness prior to completion. |

---

### What Is Blocked (Hard Stops)

| Target / Tool | Blocked Action / Flag | Policy Rationale |
| :--- | :--- | :--- |
| **`oc` / `kubectl`** | All commands and subcommands | Prevents automated cluster access, data leakage, and unintended modifications to live OpenShift/Kubernetes environments. |
| **`git`** | `commit --no-verify`, `commit -n` | Prohibits agents from bypassing local pre-commit hooks and secret scanning. |
| **`git`** | `commit --amend` | Prevents history rewrites on shared or existing commit chains. |
| **`git`** | `config` subcommand | Prevents agents from altering global/local git configurations or disabling safety hooks. |
| **`git`** | write `tag`, `push --tags` | Restricts release tagging to human maintainers. |
| **`git`** | `rebase -i`, `--interactive`, `squash`, `fixup`, `--autosquash` | Prevents destructive history rewriting and obfuscating change history. |
| **`git`** | `merge --squash`, force-push (`-f`, `--force`, `--force-with-lease`) | Prohibits destructive overwrites on remote branches. |
| **`gh`** | `release` | Restricts release publication to human developers. |
| **`gh`** | `repo delete` | Prevents catastrophic repository deletion. |
| **`gh`** | `secret` | Prevents exposure or automated modification of repository/organization secrets. |
| **`gh`** | `issue comment`, `pr comment`, `pr review`, `-c`, `--comment` | Prevents agents from impersonating human developers in discussions or approvals. Feedback and drafts must be presented in chat. |
| **`gh`** | `pr merge`, `pr close`, `issue close`; mutating `api` (`/comments`, `/reviews`, `state=closed`) | Enforces human control over PR and issue lifecycles (issues close via merged PRs). |
| **`npm` / `npx`** | `--legacy-peer-deps`, `NPM_CONFIG_LEGACY_PEER_DEPS` | Prevents dirty dependency resolution bypasses; requires fixing root dependency conflicts. |
| **Data Layer** | Modifying `overwrite: false` to `true`, destructive storage class / volume changes | Protects database persistence layers and prevents accidental volume purging. |
| **Pipelines** | Modifying CI/CD deploy matrices, orchestrator flags, or safety toggles during bugfixes | Enforces Stateful Isolation Invariant: confine component fixes to component manifests. |

---

## Enforcement Architecture

The guardrails in this repository operate across multiple layers of defense:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           AI Agent Execution                            │
├──────────────────────────────────┬──────────────────────────────────────┤
│ Application / Prompt Layer       │ config/instructions.md               │
│                                  │ • Injected into Antigravity & Cursor │
│                                  │ • Prompt-Scope Fencing               │
│                                  │ • Hard Stop behavioral rules         │
├──────────────────────────────────┼──────────────────────────────────────┤
│ Global Git Hooks Layer           │ config/hooks/pre-commit (~/.githooks)│
│                                  │ • Gitleaks secret scanning           │
│                                  │ • General Version Regression Guardian│
├──────────────────────────────────┼──────────────────────────────────────┤
│ Shell & Environment Layer        │ config/bashrc                        │
│                                  │ • Agent marker detection             │
│                                  │ • Clean non-interactive subshells    │
│                                  │ • Token isolation (GH_TOKEN unsets)  │
└──────────────────────────────────┴──────────────────────────────────────┘
```

### 1. Global Git Pre-Commit Hook (`~/.githooks/pre-commit`)
Configured globally via `git config --global core.hooksPath ~/.githooks`:
* **Gitleaks Secret Protection**: Runs `gitleaks protect --staged --redact --no-banner` on every commit to block leaked API keys, tokens, or private certificates.
* **Version Regression Guardian**: Automatically inspects staged diffs across `package.json`, `Containerfile`, `Dockerfile`, `compose.yml`, `pyproject.toml`, and GitHub Actions workflow files (`.github/workflows/*.yml`). It detects and blocks accidental dependency or container version downgrades.

### 2. Prompt-Scope Fencing & Behavioral Instructions (`config/instructions.md`)
Deployed by [`setup.sh`](file:///var/home/derek/Repos/dotfiles/setup.sh) to:
* Antigravity: `~/.gemini/GEMINI.md`
* Cursor: `~/.config/Cursor/User/prompts/global.instructions.md`

Enforces strict rules including:
* **Prompt-Scope Fencing**: Refusing to touch adjacent files or execute out-of-scope refactors without explicit approval.
* **Diff-as-Receipt**: Mandating git diffs in collapsible blocks for every modification.
* **Fail Fast**: Prohibiting silent fallbacks, rescue scripts, or suppressed diagnostics (`eslint-disable`, `@ts-ignore`).
* **Database & Template Invariants**: Treating `overwrite: false` as immutable and isolating component fixes from pipeline configurations.

### 3. Shell & Agent Environment Isolation (`config/bashrc`)
When executed inside an AI agent runner (detected via `ANTIGRAVITY_AGENT`), shell configurations automatically:
* Neutralize prompts to minimal `$ ` to avoid parsing noise.
* Unset ambient `GITHUB_TOKEN` and `GH_TOKEN` environment variables so `gh` CLI commands run cleanly against local human credentials rather than restricted ephemeral tokens.

---

## Bypassing (Human Developers Only)

Guardrails and hooks are designed to prevent automated AI mistakes while remaining unobtrusive to human developers. When a human developer needs to perform an administrative action:

* **Override Git Aliases / Wrappers**: Use the shell `command` builtin:
  ```bash
  command git config --local user.email "developer@example.com"
  ```
* **Bypass Git Hooks (Emergency Only)**:
  ```bash
  git commit --no-verify -m "fix: emergency out-of-band hotfix"
  ```
