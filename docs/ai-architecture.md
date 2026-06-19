# AI stack architecture (Derek)

Four repos, four jobs. No profiles. Dotfiles does not install guardrails.

```
┌─────────────────────────────────────────────────────────────────┐
│  bcgov/copilot-instructions          WORK STANDARDS (upstream)  │
│  .github/copilot-instructions.md     Shared BC Gov text (≤4k)   │
│  (org Copilot injects into VS Code hub — not read by dotfiles)  │
└────────────────────────────┬────────────────────────────────────┘
                             │  org / VS Code (outside dotfiles)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  ~/.config/Code/User/prompts/global.instructions.md             │
│  = work standards + delimited personal block                    │
└────────────────────────────┬────────────────────────────────────┘
                             │  dotfiles/scripts/bundle-ai-instructions.sh
                             │  (personal block only: append / replace / skip)
                             ▲
┌────────────────────────────┴────────────────────────────────────┐
│  DerekRoberts/dotfiles                   PERSONAL CONSUMER       │
│  config/ai/personal.instructions.md    Tone, modes, prefs     │
│  scripts/bundle-ai-instructions.sh       Personal block sync    │
│  setup.sh                                Personal sync + symlinks│
└────────────────────────────┬────────────────────────────────────┘
                             │  symlinks only (no extra content)
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
    VS Code Copilot      Cursor prompts     Antigravity GEMINI.md

┌─────────────────────────────────────────────────────────────────┐
│  bcgov/agent-guardrails                  ENFORCEMENT (separate)  │
│  setup.sh  →  ~/.githooks + ~/.bashrc loader                    │
│  Install independently — dotfiles does not call this          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  bcgov/agent-skills                      ON-DEMAND SKILLS        │
│  npx skills add bcgov/agent-skills        Task playbooks        │
│  ~/.agents/skills/                       Not always-on rules  │
└─────────────────────────────────────────────────────────────────┘

Tool-specific (not in bundle):
  ~/.cursor/rules/ponytail.mdc     Ponytail (Cursor)
  docs/agent-prompt-card.md        Optional @ reference / cheat sheet
```

## What goes where

| Put it in… | Examples |
|------------|----------|
| **copilot-instructions** | Hard stops, git workflow, org macros, 4k-cap shared text |
| **agent-guardrails** | gitleaks, git/gh/npm safety wrappers, global hooks, git-setup.sh |
| **dotfiles personal** | Roasts, coach mode, TS prefs, `unset GITHUB_TOKEN` |
| **dotfiles scripts** | Personal block sync, tool symlinks |
| **agent-skills** | github-actions, openshift-deployment, repo audit playbooks |
| **Chat** | One-off scope, ponytail-review, “report only” |

## What does NOT go where

- Personal opinions → **not** copilot-instructions
- Always-on guardrails → **not** agent-skills (skills are invoked, not enforced)
- Guardrails or git-setup → **not** copilot-instructions (belongs in agent-guardrails)
- Guardrails install → **not** dotfiles (use agent-guardrails `setup.sh` directly)
- Work standards merge → **not** dotfiles (org Copilot / VS Code owns the hub)
- Instruction text → **not** dotfiles symlinks (symlinks wire tools only)
- Kilo → dropped; Cursor + Copilot + Antigravity cover you

## Machine setup (two independent steps)

**Personal consumer (dotfiles):**

```bash
~/Repos/dotfiles/setup.sh
```

Work standards must already be in the global hub (org Copilot / VS Code).

Order inside setup: personal sync → symlinks (Cursor, Antigravity, skills, Ponytail).

**Guardrails (agent-guardrails — separate, once):**

```bash
curl -fsSL https://raw.githubusercontent.com/bcgov/agent-guardrails/main/setup.sh | bash
# or: ~/Repos/agent-guardrails/setup.sh
```

Re-sync personal block only:

```bash
~/Repos/dotfiles/scripts/bundle-ai-instructions.sh
```

## Personal block sync (bundle-ai-instructions.sh)

Dotfiles does **not** clone or read `bcgov/copilot-instructions`. It manages only the personal section in the global hub.

Delimiters in `global.instructions.md`:

```html
<!-- dotfiles:personal-instructions:start -->
…content from config/ai/personal.instructions.md…
<!-- dotfiles:personal-instructions:end -->
```

| State | Action |
|-------|--------|
| Delimited block matches personal file | No-op |
| Delimited block differs | Replace block |
| Legacy `# Personal Instructions (Derek)` section | Upgrade to delimited block (replace if stale) |
| No personal section | Append delimited block |
| Hub file missing | Create with personal block only |

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `GLOBAL_INSTRUCTIONS_OUTPUT` | `~/.config/Code/User/prompts/global.instructions.md` | Hub file for personal sync |

## After editing work standards

Work standards are **not** managed by dotfiles. Update via org Copilot settings or VS Code — the hub updates outside this repo.

## After editing personal standards

1. Edit `~/Repos/dotfiles/config/ai/personal.instructions.md`
2. Run `~/Repos/dotfiles/scripts/bundle-ai-instructions.sh` or full setup

## After editing guardrails

1. Edit `~/Repos/agent-guardrails/` (hooks, git-safety.sh, setup.sh)
2. Run `~/Repos/agent-guardrails/setup.sh` — **not** dotfiles

## copilot-instructions is standards text only

That repo holds `.github/copilot-instructions.md` for org/project distribution. Dotfiles does not read it.

Guardrails live in **bcgov/agent-guardrails**. Personal block sync and tool symlinks live in **dotfiles**.

## agent-skills relationship

Install once (or per skill):

```bash
npx skills add bcgov/agent-skills
```

Skills complement instructions — they don't replace them. Name skills in chat when you care which one fires.
