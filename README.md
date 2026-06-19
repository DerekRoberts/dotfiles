# Derek's Dotfiles

Personal machine config: shell, git, AI personal-instruction sync, and tool symlinks.

See **[docs/ai-architecture.md](docs/ai-architecture.md)** for how this fits the wider AI stack.

## Quick start

```bash
cd ~/Repos/dotfiles && ./setup.sh
source ~/.bashrc
```

Guardrails are separate — install once from [bcgov/agent-guardrails](https://github.com/bcgov/agent-guardrails):

```bash
curl -fsSL https://raw.githubusercontent.com/bcgov/agent-guardrails/main/setup.sh | bash
# or: ~/Repos/agent-guardrails/setup.sh
```

## AI layout (summary)

| Component | Location |
|-----------|----------|
| Work standards | `~/.config/Code/User/prompts/global.instructions.md` (org Copilot / VS Code) |
| Personal instructions source | `config/ai/personal.instructions.md` |
| Personal block in hub | Delimited section synced by `bundle-ai-instructions.sh` |
| Guardrails | [bcgov/agent-guardrails](https://github.com/bcgov/agent-guardrails) — **not dotfiles** |
| Skills catalogue | `npx skills add bcgov/agent-skills` → `~/.agents/skills/` |
| Prompt recipes (optional) | `docs/agent-prompt-card.md` |

Tools symlinked to the hub: **VS Code Copilot**, **Cursor**, **Antigravity**.

## Structure

```
├── setup.sh
├── bashrc
├── gitconfig
├── bin/updown
├── scripts/
│   └── bundle-ai-instructions.sh   # sync personal block → global hub
├── config/
│   ├── ai/personal.instructions.md
│   ├── antigravity/
│   └── vscode/
└── docs/
    ├── ai-architecture.md
    └── agent-prompt-card.md
```
