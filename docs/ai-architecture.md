# AI Stack Architecture

Self-contained prompt and guardrail integration for Derek's developer workstation.

```
┌─────────────────────────────────────────────────────────────────┐
│  dotfiles/config/prompts/global.instructions.md                 │
│  (Canonical source of truth for guidelines, guardrails, style)  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │  setup.sh copies
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
~/.config/Code/User/prompts  ~/.cursor/prompts   ~/.gemini/GEMINI.md
(VS Code instructions)       (Cursor rules)      (Antigravity hub)

Tool-specific additions:
  ~/.cursor/rules/ponytail.mdc        Ponytail (Cursor)
  ~/.gemini/antigravity/skills/       Installed Antigravity skills
```

## How It Works

1. **Single Source of Truth**: All behavior guidelines, git hygiene rules, PR process definitions, and tone/style rules live directly in `config/prompts/global.instructions.md`.
2. **Deterministic Installation**: `setup.sh` copies this file into the appropriate directories for Cursor and Antigravity.
3. **Skill & Rule Plugins**: Tool-specific rules (such as Ponytail) and modular skills are installed via `setup.sh` directly into Cursor and Antigravity.
