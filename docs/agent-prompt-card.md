# Agent Prompt Card (Derek)

Copy-paste blocks for Cursor, VS Code Copilot, Antigravity.  
Imperatives over politeness. Bullets over paragraphs. **Why** only when it disambiguates.

Reference in Cursor User Rules (optional):

```
@/home/derek/Repos/dotfiles/docs/agent-prompt-card.md
```

---

## Modes (pick one per message)

| Mode | Lead with | Agent does |
|------|-----------|------------|
| **Implement** | *(default — just state the task)* | Ships code |
| **Coach** | `Mode: coach — no code until I say go` | Teaches, argues, no edits |
| **Review** | `Mode: review — report only` | Finds problems, no fixes |
| **Roast** | `Roast freely; still do the task` | Pushback + help |

---

## Coach / pushback template

```
Goal: [one line]
Mode: coach — no code until I say go
Constraints:
- [bullet]
My probably-dumb assumption: [what you suspect is wrong]
Deliver:
- roast what's weak
- what you'd do instead
- exact prompts/commands for next step
```

---

## Ponytail (lazy senior dev)

| Say | Effect |
|-----|--------|
| `ponytail lite` | Build what's asked; one-line simpler alternative |
| `ponytail` / `ponytail full` | Default strict minimalism on new code |
| `ponytail ultra` | YAGNI extremist — cleanup only if you want pain |
| `stop ponytail` | Off |

**PR cleanup (gentle):**

```
ponytail-review diff vs main. Report only.
One line per finding: file:line, tag (delete/stdlib/native/yagni/shrink), cut, replacement.
Safe wins only: dead code, unused imports, duplicate logic.
Skip behavior, security, deployment.
End with: net: -N lines possible.
```

**Apply cherry-picks:**

```
Apply only delete/shrink items from your review that are:
- clearly dead code or unused imports
- no behavior change
- no new dependencies
One commit. npm run validate.
```

---

## PR / git workflow

```
Argue before implementing. [describe plan]
What's the lazy path? What am I over-building?
```

```
Branch [name] from main. [task]. Small PR. conventional commit.
validate before push. gh pr create when green.
```

```
unset GITHUB_TOKEN   # if gh 401 in agent shell
```

---

## Skills (name them — don't hope agent guesses)

| Skill | When |
|-------|------|
| `github-actions` | Workflows, SHA pinning, fork gates |
| `openshift-deployment` | Deployments, probes, resources |
| `security-review` | Security audit of changes |
| `ponytail-review` | Over-engineering pass |
| `issue-worktree` | Issue-scoped worktrees |

Example: `Use github-actions skill. Review .github/workflows/pr-open.yml for BC Gov patterns.`

---

## Instruction hub (your machine)

| Asset | Path |
|-------|------|
| Bundled output | `~/.config/Code/User/prompts/global.instructions.md` |
| Work standards | Org Copilot / VS Code hub (not managed by dotfiles) |
| Personal source (canonical) | GitHub `main`: `config/ai/personal.instructions.md` |
| Personal sync | `~/Repos/dotfiles/scripts/bundle-ai-instructions.sh` |
| Guardrails | `~/Repos/dotfiles/scripts/install-guardrails.sh` (not `curl \| bash`) |
| User skills | `~/.agents/skills/` |
| Ponytail rule | `~/.cursor/rules/ponytail.mdc` |
| Architecture doc | `~/Repos/dotfiles/docs/ai-architecture.md` |

Re-sync personal block after pushing to `main`:

```bash
~/Repos/dotfiles/scripts/bundle-ai-instructions.sh
# or full setup (personal sync + symlinks):
~/Repos/dotfiles/setup.sh
```

---

## Anti-patterns (wastes your time)

- Long "please could you" preambles — use imperatives
- Explaining feelings instead of task constraints
- "Clean up the codebase" without scope — agent will refactor your face off
- Mixing coach + implement in one message without saying which wins

---

## One-liners worth keeping

- `What's the minimum viable change?`
- `Report only — do not edit files yet.`
- `If my request is dumb, say so first.`
- `Scope: [paths]. Out of scope: [paths].`
- `One small commit. No drive-by refactors.`
