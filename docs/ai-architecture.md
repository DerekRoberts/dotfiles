# AI stack architecture (Derek)

Three-repo consumer model for Derek. Dotfiles does not install guardrails.

```
┌─────────────────────────────────────────────────────────────────┐
│  bcgov/agent-instructions            WORK STANDARDS (upstream)  │
│  .github/copilot-instructions.md     Shared BC Gov text (≤4k)   │
│  (org Copilot injects into VS Code hub — not read by dotfiles)  │
└────────────────────────────┬────────────────────────────────────┘
                             │  org / VS Code (outside dotfiles)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  ~/.config/Code/User/prompts/global.instructions.md             │
│  = work standards + personal instructions                       │
└────────────────────────────┬────────────────────────────────────┘
                             │  dotfiles/scripts/bundle-ai-instructions.sh
                             │  (fetch online standards + append personal instructions)
                             ▲
┌────────────────────────────┴────────────────────────────────────┐
│  GitHub main: DerekRoberts/dotfiles/config/ai/personal…md       │
│  (canonical personal source — not read from local clone)      │
└────────────────────────────┬────────────────────────────────────┘
┌────────────────────────────┴────────────────────────────────────┐
│  DerekRoberts/dotfiles (clone)           WIRING + DOCS          │
│  setup.sh: clone/pull → symlinks         bashrc, gitconfig, etc.│
│  scripts/bundle-ai-instructions.sh       Personal sync only     │
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

Tool-specific (not in bundle):
  ~/.cursor/rules/ponytail.mdc     Ponytail (Cursor)
  docs/agent-prompt-card.md        Optional @ reference / cheat sheet
```

## What goes where

| Put it in… | Examples |
|------------|----------|
| **agent-instructions** | Hard stops, git workflow, org macros, 4k-cap shared text |
| **agent-guardrails** | gitleaks, git/gh/npm safety wrappers, global hooks, git-setup.sh |
| **dotfiles personal** | Roasts, coach mode, TS prefs, `unset GITHUB_TOKEN` |
| **dotfiles scripts** | Personal block sync, tool symlinks |
| **Chat** | One-off scope, ponytail-review, “report only” |

## What does NOT go where

- Personal opinions → **not** agent-instructions
- Always-on guardrails → **not** instruction text (belongs in agent-guardrails)
- Guardrails or git-setup → **not** agent-instructions (belongs in agent-guardrails)
- Guardrails install → **not** dotfiles (use agent-guardrails `setup.sh` directly)
- Work standards merge manual work → **not** needed (dotfiles bundle script handles it)
- Instruction text → **not** dotfiles symlinks (symlinks wire tools only)
- Kilo → dropped; Cursor + Copilot + Antigravity cover you

## Machine setup

**Personal consumer (dotfiles) — hybrid bootstrap:**

```bash
# Fresh machine
curl -fsSL https://raw.githubusercontent.com/DerekRoberts/dotfiles/main/setup.sh | bash

# Already cloned
~/Repos/dotfiles/setup.sh
```

What `setup.sh` does:

1. **Clone or pull** dotfiles to `DOTFILES_DIR` (default `~/Repos/dotfiles`, branch `main`)
2. **Wire** bashrc, gitconfig, tool symlinks from the local clone
3. **Sync personal block** by fetching `config/ai/personal.instructions.md` from **GitHub main** (strict — not the local file)
4. **Symlink** Cursor, Antigravity, Ponytail, skills

Work standards are fetched from `bcgov/agent-instructions` (online) and concatenated with personal instructions.

Personal changes take effect after **push to main** and re-run setup. Local dev override:

```bash
PERSONAL_INSTRUCTIONS_URL="file://$HOME/Repos/dotfiles/config/ai/personal.instructions.md" \
  ~/Repos/dotfiles/setup.sh
```

**Guardrails (agent-guardrails — separate, once):**

```bash
# clone + run
git clone https://github.com/bcgov/agent-guardrails.git ~/Repos/agent-guardrails
~/Repos/agent-guardrails/setup.sh

# or curl bootstrap
curl -fsSL https://raw.githubusercontent.com/bcgov/agent-guardrails/main/setup.sh | bash

# or wrapper (local clone if present, else curl)
~/Repos/dotfiles/scripts/install-guardrails.sh
```

Re-sync personal block only:

```bash
~/Repos/dotfiles/scripts/bundle-ai-instructions.sh
```

## Personal block sync (bundle-ai-instructions.sh)

Dotfiles reads `bcgov/agent-instructions` (online) to bundle with personal instructions.

Canonical personal source (strict):

```
https://raw.githubusercontent.com/DerekRoberts/dotfiles/main/config/ai/personal.instructions.md
```

Direct concatenation in `global.instructions.md`:

The script overwrites `global.instructions.md` entirely with the fetched work standards followed by the personal instructions.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DOTFILES_DIR` | `~/Repos/dotfiles` | Clone location for wiring |
| `DOTFILES_BRANCH` | `main` | Branch to clone/pull |
| `PERSONAL_INSTRUCTIONS_URL` | raw GitHub `main` URL | Override for local dev only |
| `GLOBAL_INSTRUCTIONS_OUTPUT` | `~/.config/Code/User/prompts/global.instructions.md` | Hub file for personal sync |

## After editing work standards

Work standards are updated upstream in `bcgov/agent-instructions`. Dotfiles pulls them on next bundle sync.

## After editing personal standards

1. Edit `config/ai/personal.instructions.md` in this repo
2. **Push to `main`**
3. Run `~/Repos/dotfiles/scripts/bundle-ai-instructions.sh` or full setup

## After editing guardrails

1. Edit `~/Repos/agent-guardrails/` (hooks, git-safety.sh, setup.sh)
2. Run `~/Repos/agent-guardrails/setup.sh` — **not** dotfiles

## agent-instructions is standards text only

That repo holds `instructions.md` for org/project distribution. Dotfiles reads it online.

Guardrails live in **bcgov/agent-guardrails**. Personal block sync and tool symlinks live in **dotfiles**.
